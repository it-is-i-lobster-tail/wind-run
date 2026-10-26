//
//  StepHaptics.swift
//  Wind Run
//

import Foundation
import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// A tap on the wrist, or on the iPhone while its run screen is on, when a structured run moves on.
enum StepHaptic: Equatable {
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

    /// What a step's start feels like.
    static func starting(_ step: PlannedIntervalStep) -> StepHaptic {
        step.kind == .work && !step.isWalk ? .work : .easy
    }
}

/// One haptic as it happened, numbered so the same haptic twice in a row still counts as a change.
struct StepHapticEvent: Equatable {
    let haptic: StepHaptic
    let number: Int
}

enum StepHaptics {
    /// Plays a haptic on the wrist straight away, during the run's workout session too. The iPhone plays its
    /// haptics from the run screen instead (`feedback(for:)`), since they're only felt while it's on screen.
    static func play(_ haptic: StepHaptic) {
        #if os(watchOS)
        let type: WKHapticType = switch haptic {
        case .work: .start
        case .easy: .stop
        case .finished: .success
        case .reminder: .notification
        case .countdown: .click
        }
        WKInterfaceDevice.current().play(type)
        #endif
    }

    /// The run screen's feedback for a haptic.
    static func feedback(for haptic: StepHaptic) -> SensoryFeedback {
        switch haptic {
        case .work: .impact(weight: .heavy)
        case .easy: .impact(weight: .medium)
        case .finished: .success
        case .reminder: .warning
        case .countdown: .impact(weight: .light)
        }
    }
}
