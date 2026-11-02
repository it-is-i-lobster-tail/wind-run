//
//  StepHaptics.swift
//  Wind Run
//

import Foundation
#if os(watchOS)
import WatchKit
#elseif os(iOS)
import AudioToolbox
import UIKit
#endif

/// A buzz when a structured run moves on, in a timed step's last seconds, or when auto-pause stops or
/// starts the clock. Coach sessions and saved interval workouts both get them, on whichever device records
/// the run.
enum StepHaptic: Equatable, CaseIterable {
    /// A work step starts: time to go.
    case work
    /// An easier step starts: warm up, recovery, walk or cool down.
    case easy
    /// The last step is done.
    case finished
    /// An open step, such as a walk break, has gone on a while.
    case reminder
    /// One of the last seconds of a timed step.
    case countdown
    /// Auto-pause stopped the clock.
    case paused
    /// Auto-pause started the clock again.
    case resumed

    /// What a step's start feels like.
    static func starting(_ step: PlannedIntervalStep) -> StepHaptic {
        step.kind == .work && !step.isWalk ? .work : .easy
    }
}

/// Which devices buzz. Each device buzzes during the runs it records.
enum HapticDevices: String, CaseIterable, Identifiable {
    case both
    case iPhone
    case watch
    case off

    static let storageKey = "hapticDevices"

    var id: Self { self }

    var name: String {
        switch self {
        case .both: "iPhone and Watch"
        case .iPhone: "iPhone only"
        case .watch: "Watch only"
        case .off: "Off"
        }
    }

    /// Whether the device this runs on buzzes.
    var includesThisDevice: Bool {
        #if os(watchOS)
        return self == .both || self == .watch
        #else
        return self == .both || self == .iPhone
        #endif
    }

    static func current(in defaults: UserDefaults = .standard) -> HapticDevices {
        defaults.string(forKey: storageKey).flatMap(HapticDevices.init) ?? .both
    }
}

/// How hard and how often the buzzes are. The iPhone and the watch share it.
enum HapticPattern: String, CaseIterable, Identifiable {
    case gentle
    case standard
    case strong

    static let storageKey = "hapticPattern"

    var id: Self { self }

    var name: String {
        switch self {
        case .gentle: "Gentle"
        case .standard: "Standard"
        case .strong: "Strong"
        }
    }

    /// What it feels like, for the settings footer.
    var summary: String {
        switch self {
        case .gentle: "One soft tap when a step changes, and no countdown."
        case .standard: "A firm tap for work, a softer one for easy steps, and a tap in each of a timed step's last 3 seconds."
        case .strong: "Three buzzes for work, two for easy steps, and a firm tap in each of a timed step's last 3 seconds."
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> HapticPattern {
        defaults.string(forKey: storageKey).flatMap(HapticPattern.init) ?? .standard
    }

    /// The taps for a haptic, in order. Empty means this pattern skips it.
    func taps(for haptic: StepHaptic) -> [HapticTap] {
        switch self {
        case .gentle:
            switch haptic {
            case .work, .easy, .reminder, .paused, .resumed: [.click]
            case .finished: [.click, .click]
            case .countdown: []
            }
        case .standard:
            switch haptic {
            case .work: [.start]
            case .easy: [.stop]
            case .finished: [.success]
            case .reminder: [.notification]
            case .countdown: [.click]
            case .paused: [.down]
            case .resumed: [.up]
            }
        case .strong:
            switch haptic {
            case .work: [.start, .start, .start]
            case .easy: [.stop, .stop]
            case .finished: [.success, .success]
            case .reminder: [.notification, .notification]
            case .countdown: [.start]
            case .paused: [.down, .down]
            case .resumed: [.up, .up]
            }
        }
    }
}

/// One tap of a pattern, named after the watch's haptics. The iPhone plays the nearest it has.
enum HapticTap: Equatable {
    case click
    case start
    case stop
    case success
    case notification
    case down
    case up
}

enum StepHaptics {
    /// The gap between taps in one pattern. Taps closer than this run together on the watch.
    private static let tapGap: Duration = .milliseconds(350)
    /// A locked iPhone can only give its plain vibration, which lasts about 0.4 s, so its taps sit further apart.
    private static let vibrationGap: Duration = .milliseconds(600)

    /// Plays a haptic on this device straight away, as the settings ask: on the wrist during the run's
    /// workout session, and on the iPhone with the screen on, locked or in a pocket.
    static func play(_ haptic: StepHaptic, defaults: UserDefaults = .standard) {
        guard HapticDevices.current(in: defaults).includesThisDevice else { return }
        play(HapticPattern.current(in: defaults).taps(for: haptic))
    }

    /// Plays a work step's start in a pattern, so the runner can feel it in Settings.
    static func sample(_ pattern: HapticPattern) {
        play(pattern.taps(for: .work))
    }

    private static func play(_ taps: [HapticTap]) {
        guard !taps.isEmpty else { return }
        Task { @MainActor in
            for (index, tap) in taps.enumerated() {
                if index > 0 {
                    try? await Task.sleep(for: gap)
                }
                play(tap)
            }
        }
    }

    @MainActor
    private static var gap: Duration {
        #if os(iOS)
        return UIApplication.shared.applicationState == .active ? tapGap : vibrationGap
        #else
        return tapGap
        #endif
    }

    @MainActor
    private static func play(_ tap: HapticTap) {
        #if os(watchOS)
        let type: WKHapticType = switch tap {
        case .click: .click
        case .start: .start
        case .stop: .stop
        case .success: .success
        case .notification: .notification
        case .down: .directionDown
        case .up: .directionUp
        }
        WKInterfaceDevice.current().play(type)
        #elseif os(iOS)
        // The Taptic Engine's taps only play while the app is on screen. Locked or in a pocket, the run keeps
        // going in the background, and the plain vibration still plays.
        guard UIApplication.shared.applicationState == .active else {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }
        switch tap {
        case .click: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .start: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .stop: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .notification: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .down: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .up: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
        #endif
    }
}
