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

/// A buzz when a structured run moves on, in a timed step's last seconds, or when auto-pause or the runner
/// stops or starts the clock. Coach sessions and saved interval workouts both get them, on whichever device
/// records the run.
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
    /// The clock stopped, by auto-pause or the runner's Pause.
    case paused
    /// The clock started again, by auto-pause or the runner.
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

/// How the buzzes feel. The iPhone and the watch share this setting.
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
        #if os(watchOS)
        switch self {
        case .gentle: "One tap when a step changes, two when the workout is done, and no countdown."
        case .standard: "Two taps for work, one for easy steps, and three when the workout is done. Countdown taps start in the last 3 seconds or 30 meters."
        case .strong: "Three taps for work, two for easy steps, and four when the workout is done. Countdown taps start in the last 3 seconds or 30 meters."
        }
        #else
        switch self {
        case .gentle: "One soft tap when a step changes, two when the workout is done, and no countdown."
        case .standard: "A firm tap for work, a softer one for easy steps, and a tap in each of a step's last 3 seconds or last 30 meters."
        case .strong: "Three buzzes for work, two for easy steps, and a firm tap in each of a step's last 3 seconds or last 30 meters."
        }
        #endif
    }

    /// What a locked iPhone feels, for the settings footer. It only has one plain vibration, so steps are
    /// told apart by how many.
    var lockedSummary: String {
        switch self {
        case .gentle: "With the iPhone locked, every change is one buzz, and the end of the workout is two."
        case .standard: "With the iPhone locked, work is two buzzes, easy steps one, and a reached goal or the last step three."
        case .strong: "With the iPhone locked, work is three buzzes, easy steps two, and a reached goal or the last step four."
        }
    }

    /// The number of plain taps on the watch or vibrations on a locked iPhone. The count distinguishes work
    /// from easy steps and, in the standard and strong patterns, pause from resume.
    func vibrations(for haptic: StepHaptic) -> Int {
        switch self {
        case .gentle:
            switch haptic {
            case .countdown: 0
            case .finished: 2
            case .work, .easy, .reminder, .paused, .resumed: 1
            }
        case .standard:
            switch haptic {
            case .work: 2
            case .easy: 1
            case .finished: 3
            case .reminder: 2
            case .countdown: 1
            case .paused: 1
            case .resumed: 2
            }
        case .strong:
            switch haptic {
            case .work: 3
            case .easy: 2
            case .finished: 4
            case .reminder: 3
            case .countdown: 1
            case .paused: 2
            case .resumed: 3
            }
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

/// One tap of a pattern. The iPhone uses different feedback styles while the app is active.
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
        play(haptic, pattern: HapticPattern.current(in: defaults))
    }

    /// Plays a work step's start in a pattern, so the runner can feel it in Settings.
    static func sample(_ pattern: HapticPattern) {
        play(.work, pattern: pattern)
    }

    private static func play(_ haptic: StepHaptic, pattern: HapticPattern) {
        #if os(watchOS)
        // Use plain clicks because watchOS can pair its other haptic cues with a tone.
        play(Array(repeating: .click, count: pattern.vibrations(for: haptic)))
        #elseif os(iOS)
        // Locked or in a pocket, every tap is the same plain vibration, so the count tells steps apart.
        if UIApplication.shared.applicationState != .active {
            play(Array(repeating: .click, count: pattern.vibrations(for: haptic)))
            return
        }
        play(pattern.taps(for: haptic))
        #endif
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
        WKInterfaceDevice.current().play(.click)
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
