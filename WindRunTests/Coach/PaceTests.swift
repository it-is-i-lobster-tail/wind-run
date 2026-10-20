//
//  PaceTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Paces and anchors against the rules' worked examples: PZ-5's paces, PZ-3's 12-minute test, SW-7a's retest
/// and its messages, PZ-7's 1% steps under HL-27, PZ-3a's GPS rule and PZ-2's volume and expiry rules.
@MainActor
struct PaceTests {
    let calendar = CoachFixtures.calendar

    func intake(_ goal: GoalChoice, race seconds: Double? = nil, raceDay: Int = -7) -> CoachIntake {
        var intake = CoachFixtures.regularIntake(goal)
        if let seconds {
            intake.race = RaceResult(date: CoachFixtures.day(raceDay), meters: 5_000, seconds: seconds)
        }
        return intake
    }

    func fiveK(race seconds: Double? = nil, raceDay: Int = -7) -> CoachState {
        CoachFixtures.start(intake(GoalChoice(flavor: .speedWork, distance: .fiveK), race: seconds, raceDay: raceDay))
    }

    /// A test run on `day`: warm-up and cool-down around one work step, or the work alone.
    func testRun(meters: Double, seconds: Double, day: Int, steps: Bool = false) -> LoggedRun {
        guard steps else {
            return LoggedRun(start: CoachFixtures.day(day), movingSeconds: seconds, meters: meters)
        }
        let work = [
            LoggedStep(isWork: false, meters: 2_400, seconds: 900),
            LoggedStep(isWork: true, meters: meters, seconds: seconds),
            LoggedStep(isWork: false, meters: 1_600, seconds: 600),
        ]
        return LoggedRun(start: CoachFixtures.day(day), movingSeconds: seconds + 1_500, meters: meters + 4_000, steps: work)
    }

    func record(_ run: LoggedRun, meters: Double? = nil, seconds: Double? = nil, controlled: Bool = false, measured: Bool = true, state: CoachState) -> (CoachState, [CoachNote]) {
        PaceCalculator.recordTest(
            run,
            testMeters: meters,
            testSeconds: seconds,
            controlled: controlled,
            measured: measured,
            state: state,
            now: run.end.addingTimeInterval(600),
            calendar: calendar
        )
    }

    func clock(_ pace: Double?) -> String {
        CoachFormat.clock(pace ?? 0)
    }

    // MARK: PZ-5

    /// PZ-5's examples: a 25:00 5K gives easy 6:24-7:00, threshold 5:27 and interval 5:00; a 22:00 5K with a
    /// usual easy pace of 6:00 gives threshold 4:50 (slower than its 4:37 10K pace), interval 4:24 and easy 6:00-6:36.
    @Test func trainingPaceExamples() throws {
        let now = CoachFixtures.day(0)
        var runner = intake(GoalChoice(flavor: .speedWork, distance: .fiveK), race: 25 * 60)
        runner.easyPace = nil
        let paces = PaceCalculator.initialPaces(runner, now: now, calendar: calendar)
        let easy = try #require(paces.easy)
        #expect(clock(easy.fast) == "6:24")
        #expect(clock(easy.slow) == "7:00")
        #expect(paces.easySource == .anchor)
        #expect(clock(paces.thresholdPace) == "5:27")
        #expect(clock(paces.intervalPace) == "5:00")

        let faster = PaceCalculator.initialPaces(intake(GoalChoice(flavor: .speedWork, distance: .fiveK), race: 22 * 60), now: now, calendar: calendar)
        #expect(clock(faster.thresholdPace) == "4:50")
        #expect(clock(faster.intervalPace) == "4:24")
        #expect(clock(PaceCalculator.equivalent(seconds: 22 * 60, meters: 5_000, to: 10_000) / 10) == "4:37")
        #expect(faster.easySource == .reported)
        #expect(clock(faster.easy?.fast) == "6:00")
        #expect(clock(faster.easy?.slow) == "6:36")
    }

    // MARK: PZ-3

    /// PZ-3: 2.6 km in a 12-minute test equals a 5K in about 24:09. The work step is the test, the result is the
    /// first anchor and an all-out app test, and the easy band follows it because its fast edge is slower.
    @Test func twelveMinuteTestSetsTheFirstAnchor() throws {
        let state = fiveK()
        #expect(state.paces.anchor == nil)
        let (updated, notes) = record(testRun(meters: 2_600, seconds: 720, day: 9, steps: true), seconds: 720, state: state)
        let anchor = try #require(updated.paces.anchor)
        #expect(anchor.meters == 2_600)
        #expect(anchor.seconds == 720)
        #expect(anchor.source == .appTest)
        #expect(!anchor.official)
        #expect(notes == [CoachNote(.pace, "Your test equals a 24:09 5K. Your session paces now come from it.")])
        let fiveK = PaceCalculator.equivalent(seconds: 720, meters: 2_600, to: 5_000)
        #expect(abs(try #require(updated.paces.intervalPace) - fiveK / 5) < 1e-6)
        #expect(updated.paces.easySource == .anchor)
        #expect(abs(try #require(updated.paces.easy).fast - fiveK / 5 * 1.28) < 1e-6)
        #expect(!updated.paces.anchorRaisePending)
    }

    /// PZ-2, PZ-3: a controlled test counts and is marked low precision, and so is its forecast.
    @Test func controlledTestIsLowPrecision() throws {
        let (updated, notes) = record(testRun(meters: 2_500, seconds: 720, day: 9), seconds: 720, controlled: true, state: fiveK())
        let anchor = try #require(updated.paces.anchor)
        #expect(anchor.source == .controlledTest)
        #expect(anchor.lowPrecision)
        #expect(notes.count == 1)
        let forecast = try #require(PaceCalculator.forecast(.tenK, state: updated, runs: [], now: CoachFixtures.day(10), calendar: calendar))
        #expect(forecast.lowPrecision)
    }

    /// A test needs exactly one of a distance or a time; recording the same run twice changes nothing.
    @Test func testInputsAndRepeats() {
        let state = fiveK(race: 25 * 60)
        let run = testRun(meters: 5_000, seconds: 24 * 60, day: 28)
        #expect(record(run, state: state).1.isEmpty)
        #expect(record(run, meters: 5_000, seconds: 1_440, state: state).1.isEmpty)
        let (once, notes) = record(run, meters: 5_000, state: state)
        #expect(notes.count == 1)
        let (twice, again) = record(run, meters: 5_000, state: once)
        #expect(twice == once)
        #expect(again.isEmpty)
    }

    // MARK: SW-7a and PZ-7

    /// SW's worked example: a 22:00 5K runner whose paces rose 1% in block week 6 (4:47 and 4:21) retests in week 8
    /// with 2.4 km in 9:48, a 21:30 5K and 2.3% faster. R and the verdict move at once (sub-20 is 7.0% away, still
    /// Unlikely, and block 2 aims at 20:51); training paces step toward 4:44 and 4:18, 1% at most every 2 weeks.
    @Test func subTwentyRetest() throws {
        var runner = intake(GoalChoice(flavor: .speedWork, distance: .fiveK, targetSeconds: 20 * 60), race: 22 * 60, raceDay: -35)
        runner.lastFourWeeks = RecentRunning(runsPerWeek: 3, weeklyLow: .distance(meters: 25_000), longest: .distance(meters: 10_000))
        var state = CoachFixtures.start(runner)
        state.paces.qualityFactor = 0.99
        state.paces.lastRaise = CoachFixtures.day(35)
        state.quality.blocksDone = 1
        #expect(clock(state.paces.thresholdPace) == "4:47")
        #expect(clock(state.paces.intervalPace) == "4:21")

        let (updated, notes) = record(testRun(meters: 2_400, seconds: 588, day: 49), meters: 2_400, state: state)
        #expect(notes == [CoachNote(.pace, "Your test equals a 21:30 5K, 2.3% faster than 12 weeks ago. Your session paces will move up over the next few weeks.")])
        let time = try #require(updated.eventReview.timeGoal)
        #expect(CoachFormat.clock(time.currentEquivalent) == "21:30")
        #expect(abs(time.improvementNeeded - 0.0695) < 0.0005)
        #expect(time.verdict == .unlikely)
        #expect(CoachFormat.clock(try #require(time.interimGoal)) == "20:51")
        #expect(updated.paces.racePace == nil)

        // One 1% step at the test (14 days after the week-6 raise), then the rest 2 weeks later.
        let target = PaceCalculator.qualityPaces(from: try #require(updated.paces.anchor))
        #expect(clock(target.threshold) == "4:44")
        #expect(clock(target.interval) == "4:18")
        let threshold = try #require(updated.paces.thresholdPace)
        #expect(abs(threshold - (try #require(state.paces.thresholdPace)) * 0.99) < 1e-6)
        #expect(updated.paces.anchorRaisePending)
        let early = PaceCalculator.weekEnded(8, state: updated, runs: [], now: CoachFixtures.day(55), calendar: calendar).state
        #expect(early.paces == updated.paces)
        let later = PaceCalculator.weekEnded(9, state: updated, runs: [], now: CoachFixtures.day(63, hour: 20), calendar: calendar).state
        #expect(abs(try #require(later.paces.thresholdPace) - target.threshold) < 1e-6)
        #expect(abs(try #require(later.paces.intervalPace) - (try #require(target.interval))) < 1e-6)
        #expect(!later.paces.anchorRaisePending)
    }

    /// PZ-7a: a faster retest moves quality paces 1% at a time, at most once per 2 weeks, until they reach the
    /// new anchor's; SW-7a's message says how much faster and since when.
    @Test func fasterRetestStepsOnePercentEveryTwoWeeks() throws {
        let state = fiveK(race: 25 * 60)
        let before = try #require(state.paces.thresholdPace)
        let (updated, notes) = record(testRun(meters: 5_000, seconds: 24 * 60, day: 28), meters: 5_000, state: state)
        #expect(notes == [CoachNote(.pace, "Your test equals a 24:00 5K, 4% faster than 5 weeks ago. Your session paces will move up over the next few weeks.")])
        let target = PaceCalculator.qualityPaces(from: try #require(updated.paces.anchor))
        var last = (threshold: try #require(updated.paces.thresholdPace), interval: try #require(updated.paces.intervalPace))
        #expect(abs(last.threshold - before * 0.99) < 1e-6)
        var current = updated
        var raises: [Date] = [try #require(updated.paces.lastRaise)]
        for week in 5 ..< 20 {
            current = PaceCalculator.weekEnded(week, state: current, runs: [], now: CoachFixtures.day(7 * week + 6, hour: 20), calendar: calendar).state
            let threshold = try #require(current.paces.thresholdPace)
            let interval = try #require(current.paces.intervalPace)
            #expect(threshold >= last.threshold * 0.99 - 1e-9)
            #expect(interval >= last.interval * 0.99 - 1e-9)
            if let raised = current.paces.lastRaise, raised != raises.last {
                #expect(raised.timeIntervalSince(raises[raises.count - 1]) >= 14 * 86_400 - 3_600)
                raises.append(raised)
            }
            last = (threshold, interval)
        }
        // The threshold needs 4 steps from 5:27 and the interval 5 from 5:00.
        #expect(abs(last.threshold - target.threshold) < 1e-6)
        #expect(abs(last.interval - (try #require(target.interval))) < 1e-6)
        #expect(!current.paces.anchorRaisePending)
        #expect(raises.count == 5)
    }

    /// PZ-2, SW-7a: a slower retest moves paces down at once, with SW-7a's message.
    @Test func slowerRetestMovesPacesAtOnce() throws {
        var state = fiveK(race: 25 * 60)
        state.paces.qualityFactor = 0.99
        let (updated, notes) = record(testRun(meters: 5_000, seconds: 26 * 60, day: 28), meters: 5_000, state: state)
        let target = PaceCalculator.qualityPaces(from: try #require(updated.paces.anchor))
        #expect(updated.paces.thresholdPace == target.threshold)
        #expect(updated.paces.intervalPace == target.interval)
        #expect(updated.paces.qualityFactor == 1)
        #expect(!updated.paces.anchorRaisePending)
        #expect(notes == [CoachNote(.pace, "Your test came in slower, so your paces move down to match and sessions feel right again. If something got in the way, like illness or a busy stretch, tap 'Life happens' to tell me.")])
    }

    /// SW-7a: under 1% either way is "no clear change". PZ-3a: off a track, a measured course or a saved route,
    /// under 5% is kept but moves nothing; 8% faster still counts.
    @Test func noClearChange() throws {
        let state = fiveK(race: 25 * 60)
        let race = try #require(state.paces.anchor)
        let message = [CoachNote(.pace, "No clear change this block. That's common, and the next block will look at why.")]

        let (close, closeNotes) = record(testRun(meters: 5_000, seconds: 24 * 60 + 50, day: 28), meters: 5_000, state: state)
        #expect(closeNotes == message)
        #expect(close.paces.anchor?.source == .appTest)

        let (gps, gpsNotes) = record(testRun(meters: 5_000, seconds: 24 * 60, day: 28), meters: 5_000, measured: false, state: state)
        #expect(gpsNotes == message)
        #expect(gps.paces.anchor == race)
        #expect(gps.paces.thresholdPace == state.paces.thresholdPace)
        #expect(gps.paces.results.contains { $0.noClearChange && $0.seconds == 24 * 60 })

        let (clear, clearNotes) = record(testRun(meters: 5_000, seconds: 23 * 60, day: 28), meters: 5_000, measured: false, state: state)
        #expect(clear.paces.anchor?.seconds == Double(23 * 60))
        #expect(clearNotes.first?.text.hasPrefix("Your test equals a 23:00 5K, 8% faster than 5 weeks ago.") == true)
    }

    // MARK: PZ-2

    /// PZ-2: weekly distance under 60% of the month before the anchor makes quality paces 5% slower; once it is
    /// back, they return through PZ-7's 1% steps (HL-27).
    @Test func lowVolumeSlowsQualityPaces() throws {
        var state = fiveK(race: 25 * 60)
        state.paces.anchor?.weeklyMetersBefore = 40_000
        state.paces.results = state.paces.results.map { result in
            var result = result
            result.weeklyMetersBefore = 40_000
            return result
        }
        let base = try #require(state.paces.thresholdPace)
        let now = CoachFixtures.day(27, hour: 20)
        let light = (0 ..< 8).map { LoggedRun(start: CoachFixtures.day(1 + 3 * $0), movingSeconds: 2_700, meters: 7_500) }
        let slowed = PaceCalculator.weekEnded(3, state: state, runs: light, now: now, calendar: calendar)
        #expect(slowed.state.paces.volumeAdjusted)
        #expect(abs(try #require(slowed.state.paces.thresholdPace) - base * 1.05) < 1e-6)
        #expect(slowed.notes == [CoachNote(.pace, "You're running less than in the month before your last race or test, so your quality paces are 5% easier until your weekly distance is back.")])
        let again = PaceCalculator.weekEnded(3, state: slowed.state, runs: light, now: now, calendar: calendar)
        #expect(again.state == slowed.state)
        #expect(again.notes.isEmpty)

        let full = (0 ..< 16).map { LoggedRun(start: CoachFixtures.day(28 + 2 * $0), movingSeconds: 3_600, meters: 10_000) }
        let back = PaceCalculator.weekEnded(7, state: slowed.state, runs: light + full, now: CoachFixtures.day(59, hour: 20), calendar: calendar)
        #expect(!back.state.paces.volumeAdjusted)
        #expect(back.state.paces.anchorRaisePending)
        #expect(abs(try #require(back.state.paces.thresholdPace) - base * 1.05 * 0.99) < 1e-6)
    }

    /// PZ-2, PZ-7: a break of more than 28 days expires the anchor, and quality sessions go back to effort.
    @Test func longBreakExpiresTheAnchor() throws {
        var state = fiveK(race: 25 * 60)
        state.gap = GapRamp(
            tier: .g3,
            daysOff: 35,
            reference: 16_000,
            referenceLongRun: Load(meters: 8_000, seconds: 2_880),
            share: 0.5,
            step: 0.1,
            weeksDone: 0,
            dropsInRow: 0,
            startedAt: CoachFixtures.day(42)
        )
        let update = PaceCalculator.weekEnded(6, state: state, runs: [], now: CoachFixtures.day(48, hour: 20), calendar: calendar)
        #expect(update.state.paces.anchor == nil)
        #expect(update.state.paces.thresholdPace == nil)
        #expect(update.state.paces.intervalPace == nil)
        #expect(update.notes == [CoachNote(.pace, "Your last race or test is too old to set paces now, so quality sessions run by effort until your next test.")])
        #expect(PaceCalculator.forecast(.fiveK, state: update.state, runs: [], now: CoachFixtures.day(48), calendar: calendar) == nil)
        let rerun = PaceCalculator.weekEnded(6, state: update.state, runs: [], now: CoachFixtures.day(48, hour: 20), calendar: calendar)
        #expect(rerun.state == update.state)
        #expect(rerun.notes.isEmpty)
    }
}
