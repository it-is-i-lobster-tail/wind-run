//
//  FormattingRulesTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The rules the screen and the voice share, so the two never disagree about a number.
@MainActor
struct SharedFormattingRuleTests {
    @Test func secondsAreCutDownToTheWholeSecond() {
        // The tiny nudge keeps a hair under 250 s at 250.
        #expect(RunFormat.wholeSeconds(249.9996) == 250)
        #expect(RunFormat.wholeSeconds(299.6) == 299)
        #expect(RunFormat.wholeSeconds(0) == 0)
        #expect(RunFormat.wholeSeconds(-5) == 0)
    }

    @Test func paceInTheRunnersUnit() {
        #expect(RunFormat.secondsPerUnit(300, unit: .kilometers) == 300)
        #expect(RunFormat.secondsPerUnit(3_599, unit: .kilometers) == 3_599)
        #expect(RunFormat.secondsPerUnit(nil, unit: .kilometers) == nil)
        #expect(RunFormat.secondsPerUnit(0, unit: .kilometers) == nil)
        #expect(RunFormat.secondsPerUnit(-5, unit: .miles) == nil)
        #expect(RunFormat.secondsPerUnit(.infinity, unit: .kilometers) == nil)
        #expect(RunFormat.secondsPerUnit(.nan, unit: .kilometers) == nil)
    }

    @Test func screenAndVoiceShareTheHourCutoff() {
        #expect(RunFormat.secondsPerUnit(3_600, unit: .kilometers) == nil)
        #expect(RunFormat.pace(3_600, unit: .kilometers) == "–:–– /km")
        #expect(SpokenFormat.pace(3_600, unit: .kilometers) == nil)
        #expect(RunFormat.pace(3_599, unit: .kilometers) == "59:59 /km")
        #expect(SpokenFormat.pace(3_599, unit: .kilometers) == "59 minutes 59 seconds per kilometer")
    }

    @Test func timeOptionsReadAsMinutesOrAClock() {
        #expect(RunFormat.wholeMinutes(180) == "3 min")
        #expect(RunFormat.wholeMinutes(0) == "0 min")
        #expect(RunFormat.wholeMinutes(90) == nil)
        #expect(RunFormat.goal(.time(180), unit: .kilometers) == "3 min")
        #expect(RunFormat.goal(.time(90), unit: .kilometers) == "1:30")
        #expect(PaceCalloutSettings.secondsName(1_800) == "30 min")
        #expect(PaceCalloutSettings.secondsName(90) == "1:30")
        #expect(PaceCalloutSettings.secondsName(30) == "30 sec")
    }
}
