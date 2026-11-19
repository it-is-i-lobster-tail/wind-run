//
//  DisplayReadingTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// How each display reading reads at its edges: countdowns rounding up, short distances, holding still at the
/// finish, the on-pace band, level ground, empty states and what VoiceOver says.
struct DisplayReadingTests {
    private func snapshot(_ unit: DistanceUnit = .kilometers, elapsed: TimeInterval = 600, meters: Double = 2_000) -> RunSnapshot {
        RunSnapshot(elapsed: elapsed, meters: meters, unit: unit)
    }

    // MARK: Short distances

    @Test func shortDistancesReadInMetersUnderAKilometer() {
        #expect(DisplayMetric.shortDistance(999.4, unit: .kilometers).number == "999")
        #expect(DisplayMetric.shortDistance(999.4, unit: .kilometers).unit == "m")
        #expect(DisplayMetric.shortDistance(0.2, unit: .kilometers, rounding: .up).number == "1")
        #expect(DisplayMetric.shortDistance(0.2, unit: .kilometers, rounding: .up).unit == "m")
        #expect(DisplayMetric.shortDistance(1_000, unit: .kilometers).unit == "km")
    }

    @Test func shortDistancesReadInFeetUnderATenthOfAMile() {
        #expect(DisplayMetric.shortDistance(100, unit: .miles).number == "328")
        #expect(DisplayMetric.shortDistance(100, unit: .miles).unit == "ft")
        #expect(DisplayMetric.shortDistance(160, unit: .miles).number == "525")
        #expect(DisplayMetric.shortDistance(160, unit: .miles).unit == "ft")
        #expect(DisplayMetric.shortDistance(161, unit: .miles).unit == "mi")
    }

    // MARK: Steps and goals

    @Test func aTimedStepCountsDownRoundingUp() {
        var run = snapshot()
        run.step = RunSnapshot.StepReading(name: "Work", remaining: .time(4.2), inStep: 50)

        let reading = DisplayMetric.stepLeft.reading(run)

        #expect(reading.value == "0:05")
        #expect(reading.label == "WORK LEFT")
        #expect(reading.spoken == "Work, 0:05 left")
    }

    @Test func aDistanceStepCountsDownInMetersRoundingUp() {
        var run = snapshot()
        run.step = RunSnapshot.StepReading(name: "Work", remaining: .distance(meters: 4.4), inStep: 50)

        let reading = DisplayMetric.stepLeft.reading(run)

        #expect(reading.value == "5")
        #expect(reading.unit == "m")
        #expect(reading.spoken == "Work, 5 m left")
    }

    @Test func anOpenStepCountsUpAndAFinishedOneIsDone() {
        var run = snapshot()
        run.step = RunSnapshot.StepReading(name: "Warm up", remaining: .open, inStep: 65)
        let open = DisplayMetric.stepLeft.reading(run)
        #expect(open.value == "1:05")
        #expect(open.label == "WARM UP")
        #expect(open.spoken == "Warm up, 1:05 so far")

        run.step = RunSnapshot.StepReading(name: "Cool down", remaining: nil, inStep: 0, isFinished: true)
        let done = DisplayMetric.stepLeft.reading(run)
        #expect(done.value == "Done")
        #expect(done.label == "ALL STEPS")
        #expect(done.spoken == "All steps done")
    }

    @Test func aRunWithoutStepsSaysSo() {
        let reading = DisplayMetric.stepLeft.reading(snapshot())

        #expect(reading.value == "––")
        #expect(reading.label == "STEP")
        #expect(reading.spoken == "Left in step, no steps in this run")
    }

    @Test func theLastStretchToADistanceGoalNeverReadsZero() {
        var run = snapshot(meters: 4_999.6)
        run.goalMeters = 5_000
        let reading = DisplayMetric.goalLeft.reading(run)
        #expect(reading.value == "1")
        #expect(reading.unit == "m")
        #expect(reading.label == "LEFT")
        #expect(reading.spoken == "1 m left")

        run.meters = 5_000
        #expect(DisplayMetric.goalLeft.reading(run).label == "GOAL REACHED")
    }

    @Test func theLastSecondToATimeGoalNeverReadsZero() {
        var run = snapshot(elapsed: 599.2)
        run.goalSeconds = 600
        let reading = DisplayMetric.goalLeft.reading(run)
        #expect(reading.value == "0:01")
        #expect(reading.spoken == "0:01 left")

        run.elapsed = 600
        #expect(DisplayMetric.goalLeft.reading(run).value == "Done")
    }

    @Test func noGoalSaysSo() {
        let reading = DisplayMetric.goalLeft.reading(snapshot())

        #expect(reading.label == "NO GOAL")
        #expect(reading.spoken == "Left to goal, no goal for this run")
    }

    @Test func theFinishTimeHoldsStillOnceTheGoalIsReached() {
        var run = snapshot(elapsed: 1_800, meters: 5_100)
        run.goalMeters = 5_000
        run.goalReachedElapsed = 1_500
        let reading = DisplayMetric.projectedFinish.reading(run)
        #expect(reading.value == "25:00")
        #expect(reading.label == "FINISHED IN")
        #expect(reading.spoken == "Goal reached in 25:00")

        // Carried on after the app was closed: from the average pace, then the clock.
        run.goalReachedElapsed = nil
        run.averagePace = 300
        #expect(DisplayMetric.projectedFinish.reading(run).value == "25:00")
        run.averagePace = nil
        #expect(DisplayMetric.projectedFinish.reading(run).value == "30:00")
    }

    // MARK: Ahead or behind

    @Test func underFiftyMetersThereIsNothingToCompare() {
        var run = snapshot(elapsed: 15, meters: 49)
        run.paceTarget = 300...300

        let reading = DisplayMetric.aheadBehind.reading(run)

        #expect(reading.value == "––")
        #expect(reading.label == "VS TARGET")
    }

    @Test func withinThreeSecondsIsOnPace() {
        var run = snapshot(elapsed: 298, meters: 1_000)
        run.paceTarget = 300...300
        let onPace = DisplayMetric.aheadBehind.reading(run)
        #expect(onPace.value == "0:00")
        #expect(onPace.label == "ON PACE")
        #expect(onPace.spoken == "On pace")

        run.elapsed = 297
        let ahead = DisplayMetric.aheadBehind.reading(run)
        #expect(ahead.value == "0:03")
        #expect(ahead.label == "AHEAD")
    }

    @Test func aheadAndBehindSayBy() {
        var run = snapshot(elapsed: 290, meters: 1_000)
        run.paceTarget = 300...300
        #expect(DisplayMetric.aheadBehind.reading(run).spoken == "0:10 ahead of target pace")

        run.elapsed = 310
        let behind = DisplayMetric.aheadBehind.reading(run)
        #expect(behind.value == "0:10")
        #expect(behind.label == "BEHIND")
        #expect(behind.spoken == "0:10 behind target pace")
    }

    @Test func aTargetOfOnePaceIsSpokenOnce() {
        var run = snapshot()
        run.currentPace = 310
        run.paceTarget = 300...300
        let single = DisplayMetric.currentPace.reading(run).spoken
        #expect(single.contains(", target "))
        #expect(!single.contains(" to "))

        run.paceTarget = 300...330
        let range = DisplayMetric.currentPace.reading(run).spoken
        #expect(range.contains(", target "))
        #expect(range.contains(" to "))
    }

    // MARK: Hills

    @Test func smallClimbingSpeedsReadAsLevel() {
        var run = snapshot()
        run.verticalSpeed = 29
        let level = DisplayMetric.verticalSpeed.reading(run)
        #expect(level.label == "LEVEL")
        #expect(level.value == "29")
        #expect(level.unit == "m/h")
        #expect(level.spoken == "Vertical speed, level")

        run.verticalSpeed = 30
        let climbing = DisplayMetric.verticalSpeed.reading(run)
        #expect(climbing.label == "CLIMBING")
        #expect(climbing.spoken == "Climbing 30 meters an hour")

        run.verticalSpeed = -45
        let descending = DisplayMetric.verticalSpeed.reading(run)
        #expect(descending.label == "DESCENDING")
        #expect(descending.value == "45")
        #expect(descending.spoken == "Descending 45 meters an hour")
    }

    @Test func climbingSpeedInFeetHasAWiderLevelBand() {
        var run = snapshot(.miles)
        // 30 m/h is 98 ft/h, under the 100 ft/h band.
        run.verticalSpeed = 30
        let reading = DisplayMetric.verticalSpeed.reading(run)

        #expect(reading.label == "LEVEL")
        #expect(reading.value == "98")
        #expect(reading.unit == "ft/h")
    }

    @Test func pausedDropsTheGradeAndClimbingSpeed() {
        var run = snapshot()
        run.isPaused = true
        run.grade = 0.05
        run.verticalSpeed = 400

        #expect(DisplayMetric.grade.reading(run).value == "––")
        #expect(DisplayMetric.verticalSpeed.reading(run).value == "––")
        #expect(DisplayMetric.verticalSpeed.reading(run).unit == "m/h")
    }

    @Test func gradeReadsWithItsSign() {
        var run = snapshot()
        run.grade = 0.04
        #expect(DisplayMetric.grade.reading(run).value == "+4")
        #expect(DisplayMetric.grade.reading(run).spoken == "Grade, 4 percent")
        run.grade = -0.031
        #expect(DisplayMetric.grade.reading(run).value == "−3")
        run.grade = 0.004
        #expect(DisplayMetric.grade.reading(run).value == "0")
    }

    @Test func elevationReadsClimbAndDropSideBySide() {
        var run = snapshot()
        run.totalAscent = 186.4
        run.totalDescent = 142.6
        let reading = DisplayMetric.elevation.reading(run)
        #expect(reading.value == "186")
        #expect(reading.unit == "m")
        #expect(reading.label == "ELEVATION")
        #expect(reading.symbol == "arrow.up")
        #expect(reading.tint == .accent)
        #expect(reading.then == DisplayReading.Then(symbol: "arrow.down", value: "143"))
        #expect(reading.spoken == "Elevation, 186 meters up, 143 meters down")
    }

    @Test func elevationInFeet() {
        var run = snapshot(.miles)
        // 186 m is 610 ft, 12.6 m is 41.3 ft.
        run.totalAscent = 186
        run.totalDescent = 12.6
        let reading = DisplayMetric.elevation.reading(run)

        #expect(reading.value == "610")
        #expect(reading.unit == "ft")
        #expect(reading.then?.value == "41")
        #expect(reading.spoken == "Elevation, 610 feet up, 41 feet down")
    }

    @Test func noElevationYetIsADash() {
        let reading = DisplayMetric.elevation.reading(snapshot())

        #expect(reading.value == "––")
        #expect(reading.unit == "m")
        #expect(reading.label == "ELEVATION")
        #expect(reading.symbol == nil)
        #expect(reading.then == nil)
        #expect(reading.tint == nil)
        #expect(reading.spoken == "Elevation, none yet")
    }

    @Test func heightsReadInFeetOrMetersAloud() {
        var run = snapshot(.miles)
        run.totalAscent = 186
        run.totalDescent = 0
        let elevation = DisplayMetric.elevation.reading(run)
        #expect(elevation.value == "610")
        #expect(elevation.unit == "ft")
        #expect(elevation.spoken == "Elevation, 610 feet up, 0 feet down")

        var metric = snapshot()
        metric.altitude = 312
        let altitude = DisplayMetric.altitude.reading(metric)
        #expect(altitude.value == "312")
        #expect(altitude.unit == "m")
        #expect(altitude.spoken == "Altitude, 312 meters")
    }

    @Test func strideReadsInFeetOrMeters() {
        var run = snapshot()
        run.currentPace = 300
        run.cadence = 180
        let meters = DisplayMetric.strideLength.reading(run)
        #expect(meters.unit == "m")
        #expect(meters.spoken.hasSuffix(" meters"))

        run.unit = .miles
        let feet = DisplayMetric.strideLength.reading(run)
        #expect(feet.unit == "ft")
        #expect(feet.spoken.hasSuffix(" feet"))
    }

    // MARK: Paces

    @Test func gradeAdjustedPaceDropsWhilePaused() {
        var run = snapshot()
        run.currentPace = 300
        run.isPaused = true

        let reading = DisplayMetric.gradeAdjustedPace.reading(run)

        #expect(reading.value == "–:––")
        #expect(reading.unit == "/km")
        #expect(reading.label == "FLAT PACE")
        #expect(reading.spoken == "Grade-adjusted pace, none yet")
    }

    @Test func gradeAdjustedPaceReadsLikeAnyPace() {
        var run = snapshot(.miles)
        run.currentPace = 300
        run.grade = 0.05
        let adjusted = DisplayMetric.gradeAdjusted(300, grade: 0.05)

        let reading = DisplayMetric.gradeAdjustedPace.reading(run)

        #expect(reading.value == RunFormat.pace(adjusted, unit: .miles, withUnit: false))
        #expect(reading.unit == "/mi")
        #expect(reading.label == "FLAT PACE")
        #expect(reading.spoken == "Grade-adjusted pace, \(DisplayMetric.spokenPace(adjusted, unit: .miles))")
    }

    @Test func theLastSplitNamesItsUnit() {
        var run = snapshot()
        run.lastSplit = 308
        let kilometer = DisplayMetric.lastSplit.reading(run)
        #expect(kilometer.label == "LAST KM")
        #expect(kilometer.spoken == "Last kilometer, 5:08")

        run.unit = .miles
        let mile = DisplayMetric.lastSplit.reading(run)
        #expect(mile.label == "LAST MI")
        #expect(mile.spoken == "Last mile, 5:08")
    }

    // MARK: Daylight

    @Test func hoursAndMinutesCutDownToTheMinute() {
        #expect(DisplayMetric.hoursAndMinutes(3_600) == "1h 0m")
        #expect(DisplayMetric.hoursAndMinutes(3_599) == "59m")
        #expect(DisplayMetric.hoursAndMinutes(4_330) == "1h 12m")
        #expect(DisplayMetric.hoursAndMinutes(-5) == "0m")
    }

    @Test func daylightSaysWhyItHasNothing() {
        var run = snapshot()
        #expect(DisplayMetric.daylight.reading(run).spoken == "Daylight left, after the first GPS fix")

        run.metersToStart = 120
        #expect(DisplayMetric.daylight.reading(run).spoken == "Daylight left, no sunrise or sunset in the next two days")
    }

    // MARK: Clocks

    @Test func totalTimeCountsOnThroughAPause() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var run = snapshot(elapsed: 500)
        run.isPaused = true
        run.startDate = start
        run.date = start.addingTimeInterval(700)
        let screen = DisplayScreen(name: "Clocks", primary: .totalTime, secondary: .elapsed, tiles: [.distance, .currentPace, .heartRate, .cadence])

        let counting = screen.readings(run, clockRunsAt: run.date)
        #expect(counting.primary.value == "11:40")
        #expect(counting.primary.clockStart == start)
        // Elapsed time stops while paused.
        #expect(counting.secondary.clockStart == nil)

        #expect(screen.readings(run).primary.clockStart == nil)
    }

    @Test func theCompactIslandClockIsTheRunningTimeWhereverElapsedSits() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var run = snapshot(elapsed: 500)
        run.startDate = start
        run.date = start.addingTimeInterval(700)
        // Total time leads, elapsed sits in a tile.
        let screen = DisplayScreen(name: "Clocks", primary: .totalTime, secondary: .distance, tiles: [.elapsed, .currentPace, .heartRate, .cadence])

        let going = screen.readings(run, clockRunsAt: run.date)
        #expect(going.compactClock == .counting(from: run.date.addingTimeInterval(-500)))

        // Paused, it holds still on the running time, rather than switching to total time counting on.
        run.isPaused = true
        let paused = screen.readings(run, clockRunsAt: run.date)
        #expect(paused.compactClock == .fixed(RunFormat.duration(500)))
    }

    @Test func withoutElapsedTheCompactIslandClockFollowsThePrimary() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var run = snapshot(elapsed: 500)
        run.isPaused = true
        run.startDate = start
        run.date = start.addingTimeInterval(700)
        let clock = DisplayScreen(name: "Total", primary: .totalTime, secondary: .distance, tiles: [.currentPace, .heartRate, .cadence, .averagePace])
        #expect(clock.readings(run, clockRunsAt: run.date).compactClock == .counting(from: start))

        let pace = DisplayScreen(name: "Pace", primary: .distance, secondary: .heartRate, tiles: [.currentPace, .cadence, .averagePace, .totalTime])
        let readings = pace.readings(run, clockRunsAt: run.date)
        #expect(readings.compactClock == .fixed(readings.primary.value))
    }
}
