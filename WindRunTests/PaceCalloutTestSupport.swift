//
//  PaceCalloutTestSupport.swift
//  Wind Run Tests
//

import Foundation
@testable import WindRun

/// Shortcuts the tests use to build a call-out and read its paces. The app reads only `spokenText`.
extension PaceCallout {
    /// A call-out that says only this split's pace.
    init(mark: Mark, secondsPerKilometer: TimeInterval?, unit: DistanceUnit) {
        self.init(mark: mark, readings: [PaceReading(kind: .split, secondsPerKilometer: secondsPerKilometer)], unit: unit)
    }

    /// The split's own pace, for tests that check it.
    var secondsPerKilometer: TimeInterval? {
        pace(.split)
    }

    /// The reading of one kind, or nil when it wasn't picked or there was no pace.
    func pace(_ kind: PaceKind) -> TimeInterval? {
        readings.first { $0.kind == kind }?.secondsPerKilometer
    }
}
