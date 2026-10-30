//
//  BuildSetupTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Build Distance setup's inputs (Brendon, 2026-10-29): the peak week follows the event, a custom event takes up to
/// 999 km or mi, and event climb up to 9,999 m or ft.
@MainActor
struct BuildSetupTests {
    static let mile = 1_609.344
    static let foot = 0.3048

    static func model(_ unit: DistanceUnit = .miles) -> BuildSetupModel {
        BuildSetupModel(saved: nil, unit: unit, now: BuildPlannerTests.now, calendar: BuildPlannerTests.calendar)
    }

    @Test func peakWeekFollowsTheEvent() {
        let model = Self.model()
        model.event = .marathon
        #expect(model.settings.goal.peakWeekMeters == 42_195 * 1.5)
        model.event = .custom
        model.customDistance = 100
        #expect(abs(model.settings.goal.peakWeekMeters - 150 * Self.mile) < 0.01)
        model.eventClimb = 2_000
        #expect(abs(model.settings.goal.peakWeekClimbMeters - 3_000 * Self.foot) < 0.01)
    }

    @Test func savedAnswersNoLongerKeepAPeak() throws {
        // An older setup saved a peak week of its own; the next setup works it out from the event instead.
        let old = #"{"event":"marathon","peakWeekMeters":1000,"peakWeekClimbMeters":50}"#
        let saved = try JSONDecoder().decode(SavedBuildAnswers.self, from: Data(old.utf8))
        let settings = saved.settings(recent: nil, now: BuildPlannerTests.now, calendar: BuildPlannerTests.calendar)
        #expect(settings.goal.peakWeekMeters == 42_195 * 1.5)
        #expect(settings.goal.peakWeekClimbMeters == 0)
    }

    @Test func customDistanceAndClimbStopAtTheirLimits() {
        let model = Self.model(.kilometers)
        model.event = .custom
        model.customDistance = 5_000
        #expect(model.customDistance == 999)
        model.eventClimb = 25_000
        #expect(model.eventClimb == 9_999)
    }

    @Test func typingKeepsTheDigitLimit() {
        #expect(NumberRow.kept("1234", whole: false, maxDigits: 3) == "123")
        #expect(NumberRow.kept("999.55", whole: false, maxDigits: 3) == "999.5")
        #expect(NumberRow.kept("12,5", whole: false, maxDigits: 3) == "12,5")
        #expect(NumberRow.kept("1.2.3", whole: false, maxDigits: 3) == "1.2")
        #expect(NumberRow.kept("012000", whole: true, maxDigits: 4) == "1200")
        #expect(NumberRow.kept("99999", whole: true, maxDigits: 4) == "9999")
        #expect(NumberRow.kept("12.5", whole: true, maxDigits: 4) == "125")
        #expect(NumberRow.kept("", whole: true, maxDigits: 4) == "")
        #expect(NumberRow.kept("123456", whole: false, maxDigits: nil) == "123456")
    }
}
