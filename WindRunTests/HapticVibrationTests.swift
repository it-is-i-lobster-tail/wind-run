//
//  HapticVibrationTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The plain vibrations a locked iPhone plays in place of each pattern's taps.
@MainActor
struct HapticVibrationTests {
    @Test func lockedVibrationsTellWorkFromEasyAndPauseFromResume() {
        for pattern in [HapticPattern.standard, .strong] {
            #expect(pattern.vibrations(for: .work) != pattern.vibrations(for: .easy), "\(pattern)")
            #expect(pattern.vibrations(for: .paused) != pattern.vibrations(for: .resumed), "\(pattern)")
        }
    }

    @Test func lockedVibrationsMatchTheFooter() {
        #expect(HapticPattern.standard.vibrations(for: .work) == 2)
        #expect(HapticPattern.standard.vibrations(for: .easy) == 1)
        #expect(HapticPattern.standard.vibrations(for: .finished) == 3)
        #expect(HapticPattern.strong.vibrations(for: .work) == 3)
        #expect(HapticPattern.strong.vibrations(for: .easy) == 2)
        #expect(HapticPattern.strong.vibrations(for: .finished) == 4)
        #expect(HapticPattern.gentle.vibrations(for: .countdown) == 0)
    }

    @Test func everyLockedStepChangeVibrates() {
        for pattern in HapticPattern.allCases {
            for haptic in StepHaptic.allCases where haptic != .countdown {
                #expect(pattern.vibrations(for: haptic) >= 1, "\(pattern) \(haptic)")
            }
        }
    }
}
