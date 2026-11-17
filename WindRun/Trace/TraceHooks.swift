//
//  TraceHooks.swift
//  Wind Run
//

import AVFoundation
import CoreData
import SwiftData
import UIKit

/// The trace lines that come from the system rather than from Wind Run's own code: every touch, every
/// UIKit control action, every screen shown, keyboard and text-field edits, app lifecycle changes, every
/// setting written and every save to the run store. Wind Run's own screens add what each tap meant
/// (`Trace.tap`).
///
/// Nothing here logs what was on screen or typed: touches give a position and the kind of view, text
/// fields give their length, and settings that hold personal details give no value.
enum TraceHooks {
    private static var isInstalled = false
    private static var observers: [any NSObjectProtocol] = []
    private static var defaultsSnapshot: [String: String] = [:]
    /// Whether a keyboard is up, so no touch gives where it was.
    private static var isKeyboardShown = false

    /// Starts listening. Safe to call more than once; it does nothing until trace logging is on.
    static func installIfOn() {
        guard Trace.isOn else { return }
        guard !isInstalled else {
            // Turned on again: settings changed while it was off aren't news, and the state may have moved.
            defaultsSnapshot = TraceSettings.snapshot()
            logState()
            return
        }
        isInstalled = true
        swizzle(UIApplication.self, #selector(UIApplication.sendEvent(_:)), #selector(UIApplication.windRunTrace_sendEvent(_:)))
        swizzle(
            UIApplication.self,
            #selector(UIApplication.sendAction(_:to:from:for:)),
            #selector(UIApplication.windRunTrace_sendAction(_:to:from:for:))
        )
        swizzle(UIViewController.self, #selector(UIViewController.viewDidAppear(_:)), #selector(UIViewController.windRunTrace_viewDidAppear(_:)))
        swizzle(UIViewController.self, #selector(UIViewController.viewDidDisappear(_:)), #selector(UIViewController.windRunTrace_viewDidDisappear(_:)))
        observeApp()
        observeText()
        observeDefaults()
        observeSaves()
        observeAudio()
        logState()
    }

    private static func swizzle(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(type, original),
              let replacementMethod = class_getInstanceMethod(type, replacement) else { return }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }

    // MARK: - Touches, controls and screens

    static func record(_ event: UIEvent) {
        guard Trace.isOn, event.type == .touches, let touches = event.allTouches else { return }
        for touch in touches {
            let phase: String
            switch touch.phase {
            case .began: phase = "down"
            case .ended: phase = "up"
            case .cancelled: phase = "cancelled"
            default: continue
            }
            if isOnKeyboard(touch.view, in: touch.window) {
                // Where each key was pressed would give back what was typed.
                Trace.log(.touch, "\(phase) on keyboard")
            } else if isKeyboardShown {
                // Taps near a keyboard drawn in a way not caught above still say what they were on.
                Trace.log(.touch, phase, ["taps": touch.tapCount, "view": touch.view.map { describe($0) } ?? "none"])
            } else {
                let point = touch.location(in: touch.window)
                Trace.log(.touch, phase, [
                    "x": Int(point.x.rounded()),
                    "y": Int(point.y.rounded()),
                    "taps": touch.tapCount,
                    "view": touch.view.map { describe($0) } ?? "none",
                ])
            }
        }
    }

    /// Whether a touch landed on a keyboard, such as a number pad, from the class names of the view, the views
    /// holding it and its window.
    static func isOnKeyboard(_ view: UIView?, in window: UIView?) -> Bool {
        var names: [String] = []
        var current = view
        while let next = current {
            names.append(NSStringFromClass(type(of: next)))
            current = next.superview
        }
        if let window { names.append(NSStringFromClass(type(of: window))) }
        return names.contains { $0.contains("Keyboard") || $0.contains("UIKB") || $0.hasPrefix("UIInput") }
    }

    static func record(action: Selector, sender: Any?) {
        guard Trace.isOn else { return }
        let control = sender.map { shortName(of: type(of: $0)) } ?? "none"
        switch sender {
        case let toggle as UISwitch:
            Trace.log(.control, "Switch", ["action": NSStringFromSelector(action), "on": toggle.isOn])
        case let segments as UISegmentedControl:
            Trace.log(.control, "Segments", ["action": NSStringFromSelector(action), "selected": segments.selectedSegmentIndex])
        default:
            Trace.log(.control, control, ["action": NSStringFromSelector(action)])
        }
    }

    static func record(_ controller: UIViewController, appeared: Bool) {
        guard Trace.isOn, !isPlumbing(controller) else { return }
        let name = "\(shortName(of: type(of: controller))) \(appeared ? "appeared" : "went away")"
        let how = controller.navigationController != nil ? "pushed"
            : controller.presentingViewController != nil ? "presented" : "shown"
        if let alert = controller as? UIAlertController {
            // An alert's words can name a run or workout, so only its buttons are counted.
            Trace.log(.screen, name, ["as": how, "buttons": alert.actions.count])
        } else {
            Trace.log(.screen, name, ["as": how])
        }
    }

    /// Keyboards, menus and other system containers, which appear on nearly every tap.
    private static func isPlumbing(_ controller: UIViewController) -> Bool {
        let name = NSStringFromClass(type(of: controller))
        return name.hasPrefix("_UI") || name.hasPrefix("UIInput") || name.hasPrefix("UICompatibilityInput")
            || name.hasPrefix("UISystemKeyboard") || name.hasPrefix("UIEditing") || name.contains("Keyboard")
    }

    /// The touched view's kind, its developer-set identifier and what it acts as, never its text.
    private static func describe(_ view: UIView) -> String {
        var parts = [shortName(of: type(of: view))]
        if let identifier = view.accessibilityIdentifier, !identifier.isEmpty { parts.append("#\(identifier)") }
        let traits = view.accessibilityTraits
        if traits.contains(.button) { parts.append("button") }
        if traits.contains(.link) { parts.append("link") }
        if traits.contains(.adjustable) { parts.append("adjustable") }
        if traits.contains(.selected) { parts.append("selected") }
        if traits.contains(.notEnabled) { parts.append("disabled") }
        return parts.joined(separator: " ")
    }

    /// "UIHostingController<SettingsView>" rather than the full nest of SwiftUI's generic wrappers.
    static func shortName(of type: Any.Type) -> String {
        let name = String(describing: type)
        guard name.count > 80 else { return name }
        return String(name.prefix(80)) + "…"
    }

    // MARK: - App, keyboard and text

    private static func observeApp() {
        let lifecycle: [(Notification.Name, String)] = [
            (UIApplication.didBecomeActiveNotification, "Became active"),
            (UIApplication.willResignActiveNotification, "Going inactive"),
            (UIApplication.didEnterBackgroundNotification, "In the background"),
            (UIApplication.willEnterForegroundNotification, "Coming to the foreground"),
            (UIApplication.willTerminateNotification, "Closing"),
            (UIApplication.didReceiveMemoryWarningNotification, "Memory warning"),
            (UIApplication.significantTimeChangeNotification, "Significant time change"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "Phone locking: protected files closing"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "Phone unlocked: protected files open"),
            (UIApplication.userDidTakeScreenshotNotification, "Screenshot taken"),
            (UIScene.didActivateNotification, "Scene active"),
            (UIScene.willDeactivateNotification, "Scene going inactive"),
            (UIScene.didEnterBackgroundNotification, "Scene in the background"),
            (UIScene.willEnterForegroundNotification, "Scene coming to the foreground"),
            (UIScene.willConnectNotification, "Scene connected"),
            (UIScene.didDisconnectNotification, "Scene disconnected"),
            (NSUbiquitousKeyValueStore.didChangeExternallyNotification, "iCloud settings changed elsewhere"),
        ]
        for (name, message) in lifecycle {
            observe(name) { _ in Trace.log(.app, message) }
        }
        // What these changed to, as these are the first suspects when GPS drops or the run screen stutters.
        observe(UIApplication.backgroundRefreshStatusDidChangeNotification) { _ in
            Trace.log(.app, "Background refresh setting changed", ["status": backgroundRefresh])
        }
        observe(UIContentSizeCategory.didChangeNotification) { _ in
            Trace.log(.app, "Text size changed", ["textSize": UIApplication.shared.preferredContentSizeCategory.rawValue])
        }
        observe(UIAccessibility.voiceOverStatusDidChangeNotification) { _ in
            Trace.log(.app, "VoiceOver changed", ["on": UIAccessibility.isVoiceOverRunning])
        }
        observe(UIAccessibility.reduceMotionStatusDidChangeNotification) { _ in
            Trace.log(.app, "Reduce Motion changed", ["on": UIAccessibility.isReduceMotionEnabled])
        }
        observe(Notification.Name.NSProcessInfoPowerStateDidChange) { _ in
            Trace.log(.app, "Low Power Mode changed", ["on": ProcessInfo.processInfo.isLowPowerModeEnabled])
        }
        observe(ProcessInfo.thermalStateDidChangeNotification) { _ in
            Trace.log(.app, "Thermal state changed", ["thermal": thermal])
        }
        observe(UIResponder.keyboardWillShowNotification) { _ in isKeyboardShown = true }
        observe(UIResponder.keyboardDidShowNotification) { _ in
            isKeyboardShown = true
            Trace.log(.keyboard, "Shown")
        }
        observe(UIResponder.keyboardDidHideNotification) { _ in
            isKeyboardShown = false
            Trace.log(.keyboard, "Hidden")
        }
        observe(NSPersistentCloudKitContainer.eventChangedNotification) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let kind = switch event.type {
            case .setup: "setup"
            case .import: "import"
            case .export: "export"
            @unknown default: "other"
            }
            // How long it took, as a slow sync reads the same as a stuck one otherwise.
            let seconds = event.endDate.map { $0.timeIntervalSince(event.startDate) }
            if let error = event.error {
                let error = error as NSError
                Trace.log(.icloud, "Sync \(kind) failed", ["domain": error.domain, "code": error.code, "seconds": seconds as Any])
            } else if let seconds {
                Trace.log(.icloud, "Sync \(kind) finished", ["succeeded": event.succeeded, "seconds": seconds])
            } else {
                Trace.log(.icloud, "Sync \(kind) started")
            }
        }
    }

    private static func observeText() {
        observe(UITextField.textDidBeginEditingNotification) { note in logText("Editing began", note.object) }
        observe(UITextField.textDidChangeNotification) { note in logText("Changed", note.object) }
        observe(UITextField.textDidEndEditingNotification) { note in logText("Editing ended", note.object) }
        observe(UITextView.textDidBeginEditingNotification) { note in logText("Editing began", note.object) }
        observe(UITextView.textDidChangeNotification) { note in logText("Changed", note.object) }
        observe(UITextView.textDidEndEditingNotification) { note in logText("Editing ended", note.object) }
    }

    /// A text edit by its length only. The words typed never go in the trace.
    private static func logText(_ what: String, _ object: Any?) {
        switch object {
        case let field as UITextField:
            Trace.log(.text, "Field: \(what)", [
                "length": field.text?.count ?? 0,
                "keyboard": keyboardName(field.keyboardType),
                "secure": field.isSecureTextEntry,
            ])
        case let view as UITextView:
            Trace.log(.text, "Text box: \(what)", ["length": view.text.count])
        default:
            Trace.log(.text, what)
        }
    }

    private static func keyboardName(_ type: UIKeyboardType) -> String {
        switch type {
        case .numberPad: "number pad"
        case .decimalPad: "decimal pad"
        case .numbersAndPunctuation: "numbers"
        default: "text"
        }
    }

    private static func observeAudio() {
        observe(AVAudioSession.routeChangeNotification) { notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            // Port kinds only: a port's name is often the runner's name for their headphones.
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+")
            Trace.log(.callout, "Audio route changed", ["reason": reason.map { "\($0.rawValue)" } ?? "?", "outputs": outputs])
        }
        observe(AVAudioSession.interruptionNotification) { notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Trace.log(.callout, type == AVAudioSession.InterruptionType.began.rawValue ? "Audio interrupted" : "Audio interruption ended")
        }
    }

    private static func logState() {
        let application = UIApplication.shared
        let state = switch application.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "other"
        }
        Trace.log(.app, "Listening", [
            "state": state,
            "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "thermal": thermal,
            "backgroundRefresh": backgroundRefresh,
            "textSize": application.preferredContentSizeCategory.rawValue,
            "voiceOver": UIAccessibility.isVoiceOverRunning,
            "reduceMotion": UIAccessibility.isReduceMotionEnabled,
        ])
    }

    /// "nominal", "fair", "serious" or "critical".
    private static var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "other"
        }
    }

    /// Whether Background App Refresh is on for Wind Run: "available", "denied" or "restricted".
    private static var backgroundRefresh: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: "available"
        case .denied: "denied"
        case .restricted: "restricted"
        @unknown default: "other"
        }
    }

    // MARK: - Settings and saves

    private static func observeDefaults() {
        defaultsSnapshot = TraceSettings.snapshot()
        observe(UserDefaults.didChangeNotification) { _ in
            // The hooks stay once installed, so this does nothing while logging is off.
            guard Trace.isOn else { return }
            let now = TraceSettings.snapshot()
            for line in TraceSettings.changes(from: defaultsSnapshot, to: now) {
                Trace.log(.setting, line.key, ["value": line.value])
            }
            defaultsSnapshot = now
        }
    }

    private static func observeSaves() {
        observe(ModelContext.willSave) { _ in Trace.log(.data, "Saving") }
        observe(ModelContext.didSave) { notification in
            let info = notification.userInfo ?? [:]
            func counts(_ key: ModelContext.NotificationKey) -> String {
                let ids = info[key.rawValue] as? [PersistentIdentifier] ?? []
                let byEntity = Dictionary(grouping: ids, by: \.entityName).map { "\($0.key)×\($0.value.count)" }
                return byEntity.isEmpty ? "none" : byEntity.sorted().joined(separator: ",")
            }
            Trace.log(.data, "Saved", [
                "inserted": counts(.insertedIdentifiers),
                "updated": counts(.updatedIdentifiers),
                "deleted": counts(.deletedIdentifiers),
            ])
        }
    }

    private static func observe(_ name: Notification.Name, _ handle: @escaping @MainActor (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated { handle(notification) }
        })
    }
}

extension UIApplication {
    @objc dynamic func windRunTrace_sendEvent(_ event: UIEvent) {
        TraceHooks.record(event)
        // Swapped with the original, so this calls UIKit's own sendEvent.
        windRunTrace_sendEvent(event)
    }

    @objc dynamic func windRunTrace_sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool {
        TraceHooks.record(action: action, sender: sender)
        return windRunTrace_sendAction(action, to: target, from: sender, for: event)
    }
}

extension UIViewController {
    @objc dynamic func windRunTrace_viewDidAppear(_ animated: Bool) {
        windRunTrace_viewDidAppear(animated)
        TraceHooks.record(self, appeared: true)
    }

    @objc dynamic func windRunTrace_viewDidDisappear(_ animated: Bool) {
        windRunTrace_viewDidDisappear(animated)
        TraceHooks.record(self, appeared: false)
    }
}
