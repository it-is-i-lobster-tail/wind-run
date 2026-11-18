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

@MainActor
struct UnitWordTests {
    @Test func singularNames() {
        #expect(DistanceUnit.kilometers.singularName == "kilometer")
        #expect(DistanceUnit.miles.singularName == "mile")
    }

    @Test func lastUnitLabelsInBothUnits() {
        #expect(PaceKind.lastUnit.name(unit: .miles) == "Last mile")
        #expect(PaceKind.lastUnit.name(unit: .kilometers) == "Last kilometer")
        #expect(PaceKind.lastUnit.detail(unit: .miles) == "Your pace over the last mile, however long your splits are.")
        #expect(PaceKind.lastUnit.detail(unit: .kilometers) == "Your pace over the last kilometer, however long your splits are.")
        #expect(PaceKind.lastUnit.spokenLabel(unit: .miles) == "last mile pace")
        #expect(PaceKind.lastUnit.spokenLabel(unit: .kilometers) == "last kilometer pace")
    }

    @Test func spokenPaceEndsInTheUnitWord() {
        #expect(SpokenFormat.pace(300, unit: .kilometers) == "5 minutes per kilometer")
        #expect(SpokenFormat.pace(1_000 / DistanceUnit.miles.meters * 600, unit: .miles)?.hasSuffix(" per mile") == true)
    }
}

@MainActor
struct HeightUnitTests {
    @Test func heightsFollowTheDistanceUnit() {
        #expect(DistanceUnit.miles.heightValue(DistanceUnit.metersPerFoot) == 1)
        #expect(DistanceUnit.miles.heightValue(0) == 0)
        #expect(DistanceUnit.kilometers.heightValue(37) == 37)
        #expect(DistanceUnit.miles.heightSymbol == "ft")
        #expect(DistanceUnit.kilometers.heightSymbol == "m")
        #expect(RunFormat.elevation(DistanceUnit.metersPerFoot * 100, unit: .miles) == "100 ft")
    }
}
