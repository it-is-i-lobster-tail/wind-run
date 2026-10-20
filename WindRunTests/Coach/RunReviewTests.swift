//
//  RunReviewTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// PZ-11 and PZ-12: the heart-rate numbers the app reads from the logged runs, on the device.
@MainActor
struct HeartRateZoneTests {
    let calendar = CoachFixtures.calendar
    let state = CoachFixtures.start(CoachFixtures.regularIntake())
    let watch = HeartRateSettings(device: .appleWatch)
    let strap = HeartRateSettings(device: .chestStrap)

    var estimate: Double { (208 - 0.7 * Double(state.assessment.age)).rounded() }

    /// A run with decision-grade heart rate unless a check says otherwise.
    func run(
        day: Int,
        minutes: Double = 45,
        rpe: Int = 3,
        talkTest: Bool? = true,
        allOut: Bool = false,
        heat: HeatAnswer? = nil,
        source: HeartRateDevice = .appleWatch,
        mean: Double? = 140,
        peak: Double? = nil,
        fromMinute10: Double? = nil,
        coverage: Double = 0.95
    ) -> LoggedRun {
        var checkIn = RunCheckIn(answeredAt: CoachFixtures.day(day, hour: 9), rpe: rpe, talkTest: talkTest, feel: .ok)
        checkIn.raceOrAllOut = allOut
        checkIn.heat = heat
        let heartRate = RunHeartRate(source: source, coverage: coverage, mean: mean, peak30s: peak, fromMinute10: fromMinute10)
        return LoggedRun(start: CoachFixtures.day(day), movingSeconds: minutes * 60, meters: minutes * 60 / 330 * 1_000, checkIn: checkIn, heartRate: heartRate)
    }

    func zones(_ runs: [LoggedRun], settings: HeartRateSettings? = nil, state: CoachState? = nil) -> HeartRateZones {
        let state = state ?? self.state
        return RunHeartRate.zones(age: state.assessment.age, settings: settings ?? watch, runs: runs, state: state, calendar: calendar)
    }

    @Test func twoRacesRaiseMaxToTheLowerPeak() {
        let runs = [run(day: 1, allOut: true, peak: estimate + 9), run(day: 5, allOut: true, peak: estimate + 5)]
        let zones = zones(runs)
        #expect(zones.max == estimate + 5)
        #expect(zones.maxObserved)
        #expect(zones.easyCeiling == ((estimate + 5) * 0.80).rounded())
    }

    @Test func oneRaceIsEnoughOnlyWithAStrap() {
        #expect(zones([run(day: 1, allOut: true, source: .chestStrap, peak: estimate + 6)], settings: strap).max == estimate + 6)
        let watchOnly = zones([run(day: 1, allOut: true, peak: estimate + 6)])
        #expect(watchOnly.max == estimate)
        #expect(!watchOnly.maxObserved)
    }

    @Test func observedMaxNeverPassesTheEstimatePlus22() {
        let runs = [run(day: 1, allOut: true, peak: estimate + 40), run(day: 5, allOut: true, peak: estimate + 30)]
        #expect(zones(runs).max == estimate + 22)
    }

    @Test func peaksBelowTheEstimateNeverLowerIt() {
        let runs = [run(day: 1, allOut: true, peak: estimate - 10), run(day: 5, allOut: true, peak: estimate - 12)]
        #expect(zones(runs).max == estimate)
    }

    @Test func onlyRunsMarkedAllOutCount() {
        let runs = [run(day: 1, peak: estimate + 9), run(day: 5, peak: estimate + 8)]
        #expect(zones(runs).max == estimate)
    }

    @Test func patchyHeartRateNeverRaisesMax() {
        let runs = [run(day: 1, allOut: true, peak: estimate + 9, coverage: 0.5), run(day: 5, allOut: true, peak: estimate + 8, coverage: 0.5)]
        #expect(zones(runs).max == estimate)
    }

    @Test func startersAndNovicesKeepTheEstimate() {
        var novice = state
        novice.assessment.tier = .novice
        let runs = [run(day: 1, allOut: true, peak: estimate + 9), run(day: 5, allOut: true, peak: estimate + 8)]
        #expect(zones(runs, state: novice).max == estimate)
    }

    @Test func aLowerLabMaxReplacesTheEstimate() {
        let settings = HeartRateSettings(device: .appleWatch, labMax: estimate - 8)
        #expect(zones([], settings: settings).max == estimate - 8)
    }

    @Test func showOnlyUsesTheEstimateAlone() {
        let runs = [run(day: 1, allOut: true, source: .chestStrap, peak: estimate + 6)]
        let zones = zones(runs, settings: HeartRateSettings(device: .chestStrap, useForCoaching: false))
        #expect(zones.max == estimate)
        #expect(zones.threshold == nil)
        #expect(zones.personalEasyCeiling == nil)
    }

    @Test func thresholdComesFromTheNewestAllOutRunOf40To70Minutes() {
        let runs = [
            run(day: 1, minutes: 50, rpe: 9, allOut: true, fromMinute10: 158),
            run(day: 4, minutes: 52, rpe: 9, allOut: true, fromMinute10: 162),
            // Too long, and not marked: neither sets threshold HR.
            run(day: 6, minutes: 80, rpe: 9, allOut: true, fromMinute10: 150),
            run(day: 7, minutes: 45, rpe: 8, fromMinute10: 170),
        ]
        let zones = zones(runs)
        #expect(zones.threshold == 162)
        #expect(zones.thresholdBand == (162 * 0.95).rounded() ... 162)
    }

    @Test func aHotRunNeverSetsThreshold() {
        let runs = [
            run(day: 1, minutes: 50, rpe: 9, allOut: true, fromMinute10: 158),
            run(day: 4, minutes: 50, rpe: 9, allOut: true, heat: .warm, fromMinute10: 168),
        ]
        #expect(zones(runs).threshold == 158)
    }

    @Test func personalCeilingNeedsThreeEasyRunsThatFeltEasy() {
        let two = [run(day: 1, mean: 128), run(day: 3, mean: 130)]
        #expect(zones(two).personalEasyCeiling == nil)
        let runs = two + [
            run(day: 5, mean: 132),
            // Rated 4, and a failed talk test: neither counts.
            run(day: 6, rpe: 4, mean: 150),
            run(day: 7, talkTest: false, mean: 150),
        ]
        let zones = zones(runs)
        #expect(zones.personalEasyCeiling == 130)
        #expect(zones.easyCeiling == 130)
    }

    @Test func personalCeilingUsesTheLatestFiveAndOnlyWhenLower() {
        let means: [Double] = [120, 150, 150, 150, 150, 150]
        let runs = means.enumerated().map { run(day: $0.offset, mean: $0.element) }
        let zones = zones(runs)
        #expect(zones.personalEasyCeiling == 150)
        #expect(zones.easyCeiling == (estimate * 0.75).rounded())
    }

    @Test func personalCeilingKeepsToOneDevice() {
        let runs = [run(day: 1, source: .chestStrap, mean: 128), run(day: 3, mean: 130), run(day: 5, mean: 132), run(day: 6, mean: 134)]
        #expect(zones(runs).personalEasyCeiling == 132)
        #expect(zones(runs, settings: strap).personalEasyCeiling == nil)
    }

    @Test func personalCeilingStartsAgainAfterABreak() {
        let before = [run(day: 1, mean: 120), run(day: 2, mean: 120), run(day: 3, mean: 120)]
        let after = [run(day: 20, mean: 135), run(day: 21, mean: 137)]
        #expect(zones(before + after).personalEasyCeiling == nil)
    }
}

/// BD-5c's benchmark comparison and AD-6c's fatigue check.
@MainActor
struct BenchmarkTests {
    let calendar = CoachFixtures.calendar
    let state = CoachFixtures.start(CoachFixtures.regularIntake())

    func benchmark(day: Int, pace: Double, rpe: Int = 3, meters: Double = 5_000, temperature: Double? = 12, treadmill: Bool = false) -> LoggedRun {
        LoggedRun(
            start: CoachFixtures.day(day),
            movingSeconds: meters / 1_000 * pace,
            meters: meters,
            source: treadmill ? .treadmill : .gps,
            checkIn: RunCheckIn(answeredAt: CoachFixtures.day(day, hour: 9), rpe: rpe, talkTest: true, feel: .ok),
            track: treadmill ? nil : TrackSummary(climbFirstHalf: 10, climbSecondHalf: 12),
            temperature: temperature
        )
    }

    func compare(_ run: LoggedRun, _ earlier: [LoggedRun], state: CoachState? = nil) -> (notes: [CoachNote], fatigueCheck: Bool) {
        RunReviewer.compareBenchmark(run, earlier: earlier, state: state ?? self.state, now: run.end.addingTimeInterval(3_600), calendar: calendar)
    }

    @Test func aFasterBenchmarkAtTheSameEffortIsAGain() {
        let result = compare(benchmark(day: 42, pace: 376), [benchmark(day: 0, pace: 400)])
        #expect(result.notes == [CoachNote(.insight, "Same easy effort, 6% faster than 6 weeks ago.")])
        #expect(!result.fatigueCheck)
    }

    @Test func theSamePaceRatedLowerIsAGain() {
        let result = compare(benchmark(day: 28, pace: 396, rpe: 2), [benchmark(day: 0, pace: 400, rpe: 3)])
        #expect(result.notes == [CoachNote(.insight, "Same pace as 4 weeks ago, at an easier effort.")])
    }

    @Test func underFivePercentIsNoClearChange() {
        let result = compare(benchmark(day: 35, pace: 388), [benchmark(day: 0, pace: 400)])
        #expect(result.notes == [CoachNote(.insight, "Same easy effort, about the same pace as 5 weeks ago.")])
    }

    @Test func muchSlowerWithWorseFatigueStartsTheFatigueCheck() {
        var tired = state
        tired.morningChecks.append(MorningCheck(date: CoachFixtures.day(35, hour: 6), fatigue: 6, soreness: 4))
        let run = benchmark(day: 35, pace: 445)
        let result = compare(run, [benchmark(day: 0, pace: 400)], state: tired)
        #expect(result.fatigueCheck)
        #expect(result.notes == [CoachNote(.plan, "Your check run was well off your usual at the same effort. Let's rest or run easy for a week.")])
        // Without the worse fatigue it is only a slower run.
        #expect(!compare(run, [benchmark(day: 0, pace: 400)]).fatigueCheck)
    }

    @Test func onlyLikeForLikeRunsAreCompared() {
        let earlier = benchmark(day: 0, pace: 400, temperature: 5)
        #expect(compare(benchmark(day: 35, pace: 370, temperature: 14), [earlier]).notes.isEmpty)
        #expect(compare(benchmark(day: 35, pace: 370, temperature: 5, treadmill: true), [earlier]).notes.isEmpty)
        #expect(compare(benchmark(day: 35, pace: 370, meters: 7_000, temperature: 5), [earlier]).notes.isEmpty)
        // The newest like-for-like run is the one compared.
        let result = compare(benchmark(day: 35, pace: 370, temperature: 5), [earlier, benchmark(day: 21, pace: 392, temperature: 6)])
        #expect(result.notes == [CoachNote(.insight, "Same easy effort, 6% faster than 2 weeks ago.")])
    }

    @Test func noRPENoComparison() {
        var run = benchmark(day: 35, pace: 370)
        run.checkIn = nil
        #expect(compare(run, [benchmark(day: 0, pace: 400)]).notes.isEmpty)
    }
}

/// The run review of one run: the data gate, FB-3's check, FB-1's insights, FB-4g's outcomes, the pace changes and
/// what heart rate may touch (FB-1 to FB-6, PZ-7, PZ-8, PZ-13, BD-1e).
@MainActor
struct RunReviewTests {
    let calendar = CoachFixtures.calendar

    func plan() -> CoachState {
        CoachFixtures.start(CoachFixtures.regularIntake())
    }

    func session(_ state: CoachState, day: Int) throws -> PlannedSession {
        try #require(state.weeks[0].plan.sessions.first { $0.dayOffset == day })
    }

    func review(_ run: LoggedRun, _ state: CoachState, runs: [LoggedRun]) -> (CoachState, RunReview) {
        RunReviewer.review(run, state: state, runs: runs, now: run.end.addingTimeInterval(1_800), calendar: calendar)
    }

    func checkIn(day: Int, rpe: Int, talkTest: Bool? = nil) -> RunCheckIn {
        RunCheckIn(answeredAt: CoachFixtures.day(day, hour: 9), rpe: rpe, talkTest: talkTest ?? (rpe <= 3), feel: .ok)
    }

    /// A band equal to these paces, up to rounding.
    func band(_ band: PaceBand?, is fast: Double, _ slow: Double) -> Bool {
        guard let band else { return false }
        return abs(band.fast - fast) < 1e-6 && abs(band.slow - slow) < 1e-6
    }

    // MARK: FB-6's race-pace session

    /// FB-6: an Event runner's race-pace sessions on these days of plan week 0: 10 min easy, 20 min at 5:30/km,
    /// 10 min easy.
    func racePaceState(days: [Int]) -> (CoachState, [PlannedSession]) {
        var state = plan()
        state.goal = GoalChoice(flavor: .event, distance: .halfMarathon)
        var sessions: [PlannedSession] = []
        for day in days {
            let session = PlannedSession(
                dayOffset: day,
                kind: .racePace,
                effort: .steady,
                target: Load(meters: 6_650, seconds: 2_400),
                paceBand: PaceBand(fast: 320, slow: 340),
                dose: QualityDose(type: .racePace, step: 1, reps: 1, repSeconds: 1_200, recoverySeconds: 0, continuous: true)
            )
            state.weeks[0].plan.sessions.removeAll { $0.dayOffset == day }
            state.weeks[0].plan.sessions.append(session)
            sessions.append(session)
        }
        state.weeks[0].plan.sessions.sort { $0.dayOffset < $1.dayOffset }
        return (state, sessions)
    }

    /// FB-6's run: the segment's first km in 5:12, its halves at 5:18 and 5:40/km, rated 5, cool, on a route whose
    /// halves differ by 8 m of climb.
    func fadingRun(for session: PlannedSession, day: Int) -> LoggedRun {
        let segment = [
            Split(meters: 1_000, seconds: 312, climbMeters: 0),
            Split(meters: 825, seconds: 268.35, climbMeters: 0),
            Split(meters: 1_000, seconds: 340, climbMeters: 0),
            Split(meters: 825, seconds: 280.5, climbMeters: 0),
        ]
        var checkIn = checkIn(day: day, rpe: 5)
        checkIn.heat = .cool
        return LoggedRun(
            start: CoachFixtures.day(day),
            movingSeconds: 2_400.85,
            meters: 6_650,
            plannedSessionID: session.id,
            checkIn: checkIn,
            track: TrackSummary(climbFirstHalf: 10, climbSecondHalf: 18),
            steps: [
                LoggedStep(isWork: false, meters: 1_500, seconds: 600),
                LoggedStep(isWork: true, meters: 3_650, seconds: 1_200.85, splits: segment),
                LoggedStep(isWork: false, meters: 1_500, seconds: 600),
            ]
        )
    }

    // MARK: FB-2

    @Test func aRunUnder500mIsDroppedAndChangesNothing() throws {
        let state = plan()
        let tuesday = try session(state, day: 1)
        let run = LoggedRun(start: CoachFixtures.day(1), movingSeconds: 180, meters: 400, plannedSessionID: tuesday.id)
        let (after, review) = review(run, state, runs: [run])
        #expect(review.gate == .dropped)
        #expect(review.match == .extra)
        #expect(after.weeks == state.weeks)
    }

    @Test func patchyGPSCountsTheRunButSkipsPaceFeedback() throws {
        let state = plan()
        let tuesday = try session(state, day: 1)
        var run = CoachFixtures.run(for: tuesday, on: CoachFixtures.day(1), pace: 378)
        run.track = TrackSummary(poorGPSShare: 0.3)
        let (after, review) = review(run, state, runs: [run])
        #expect(review.gate == .volumeOnly)
        #expect(after.weeks[0].plan.sessions.first { $0.id == tuesday.id }?.status == .done(runID: run.id))
        #expect(review.insights.last?.text == "GPS was patchy, so I've counted the distance but skipped pace feedback.")
    }

    // MARK: FB-3

    /// Tuesday's easy run with its last quarter 28% slower than its second.
    func toughRun(_ session: PlannedSession, whatHappened: WhatHappened? = nil) -> LoggedRun {
        var checkIn = checkIn(day: 1, rpe: 4)
        checkIn.whatHappened = whatHappened
        let splits = [360.0, 360, 380, 460].map { Split(meters: 1_000, seconds: $0, climbMeters: 0) }
        return LoggedRun(start: CoachFixtures.day(1), movingSeconds: 1_560, meters: 4_000, plannedSessionID: session.id, checkIn: checkIn, track: TrackSummary(splits: splits))
    }

    @Test func aToughRunAsksWhatHappenedBeforeAnyCoaching() throws {
        let state = plan()
        let tuesday = try session(state, day: 1)
        let run = toughRun(tuesday)
        let (after, review) = review(run, state, runs: [run])
        #expect(review.questions.first == .whatHappened(runID: run.id))
        #expect(review.showsSafetyLine)
        #expect(review.insights == [CoachNote(.insight, "Easy run done, as planned.")])
        #expect(RunReviewer.questions(after, runs: [run], now: CoachFixtures.day(1, hour: 12), calendar: calendar).contains(.whatHappened(runID: run.id)))

        // Ill, hurt or heat answers get no coaching text: their own rules speak.
        let ill = toughRun(tuesday, whatHappened: .feltIll)
        let routed = self.review(ill, state, runs: [ill]).1
        #expect(routed.insights.isEmpty)
        #expect(!routed.questions.contains(.whatHappened(runID: ill.id)))

        // "Tired" lets coaching speak, and counts toward family E.
        let tired = toughRun(tuesday, whatHappened: .tired)
        let coached = self.review(tired, state, runs: [tired])
        #expect(coached.1.insights.count == 2)
        #expect(!coached.1.questions.contains(.whatHappened(runID: tired.id)))
        #expect(RunReviewer.weekSignals(week: 0, state: coached.0, runs: [tired], calendar: calendar).extraEffortFlags == 1)
    }

    // MARK: FB-6 and FB-4g

    @Test func theOwnersFadeExample() throws {
        let (state, sessions) = racePaceState(days: [2])
        let run = fadingRun(for: sessions[0], day: 2)
        let (after, review) = review(run, state, runs: [run])
        #expect(review.outcome == .struggled)
        #expect(review.questions.allSatisfy { $0 != .whatHappened(runID: run.id) })
        #expect(review.insights == [
            CoachNote(.insight, "You ran all 20 minutes at race pace, as planned."),
            CoachNote(.insight, "Your pace dropped 7% in the second half after a fast first kilometre. Let's practise an even tempo: your next race-pace run repeats this one, with a pace band to hold from the start."),
        ])
        let advice = try #require(after.runReview.advice.first { $0.kind == .evenBand })
        let band = try #require(advice.band)
        #expect(CoachFormat.paceRange(band, unit: .kilometers) == "5:14-5:47/km")
        #expect(CoachFormat.paceRange(band, unit: .miles) == "8:25-9:18/mi")
        #expect(after.quality.outcomes.map(\.outcome) == [.struggled])
        #expect(after.paces.qualityFactor == 1)

        // The next race-pace session gets the band.
        let next = PlannedSession(dayOffset: 0, kind: .racePace, effort: .steady, target: Load(meters: 6_650, seconds: 2_400))
        #expect(RunReviewer.advice(for: next, on: CoachFixtures.day(7, hour: 0), state: after, calendar: calendar).map(\.kind) == [.evenBand])
    }

    @Test func aSecondFadeInARowFailsAndAsksForARetest() throws {
        let (state, sessions) = racePaceState(days: [2, 4])
        let first = fadingRun(for: sessions[0], day: 2)
        let second = fadingRun(for: sessions[1], day: 4)
        var after = review(first, state, runs: [first]).0
        let result = review(second, after, runs: [first, second])
        after = result.0
        #expect(result.1.outcome == .failed)
        #expect(after.quality.outcomes.map(\.outcome) == [.struggled, .failed])
        #expect(after.quality.retestWeek == 2)
        #expect(abs(after.paces.qualityFactor - PaceUpdates.cutFactor) < 1e-9)
        #expect(result.1.insights.last?.text == "Your pace dropped 7% in the second half after a fast first kilometre. Let's practise an even tempo: your next race-pace run is shorter and a little slower, with a pace band to hold from the start.")
        #expect(result.1.notes.contains(CoachNote(.plan, "Because your pace faded in 2 of your last 3 race-pace runs, your next one is split into 5-minute repeats and Sunday's long run starts at easy pace.")))
        #expect(RunReviewer.weekSignals(week: 0, state: after, runs: [first, second], calendar: calendar).secondDownStep == false)

        // Reviewing it again changes nothing.
        let again = review(second, after, runs: [first, second])
        #expect(again.0 == after)
    }

    @Test func twoEvenSessionsRaisePacesOncePerTwoWeeks() throws {
        var state = plan()
        let days = [0, 2, 4, 6]
        var sessions: [PlannedSession] = []
        for day in days {
            let session = PlannedSession(
                dayOffset: day,
                kind: .threshold,
                effort: .threshold,
                target: Load(meters: 6_000, seconds: 2_400),
                paceBand: PaceBand(fast: 290, slow: 300),
                dose: QualityDose(type: .threshold, step: 1, reps: 1, repSeconds: 1_200, recoverySeconds: 0, continuous: true)
            )
            state.weeks[0].plan.sessions.removeAll { $0.dayOffset == day }
            state.weeks[0].plan.sessions.append(session)
            sessions.append(session)
        }
        var runs: [LoggedRun] = []
        var reviews: [RunReview] = []
        for (day, session) in zip(days, sessions) {
            let work = LoggedStep(isWork: true, meters: 1_200 / 0.295, seconds: 1_200)
            let run = LoggedRun(
                start: CoachFixtures.day(day),
                movingSeconds: 2_400,
                meters: 1_200 / 0.295 + 3_000,
                plannedSessionID: session.id,
                checkIn: checkIn(day: day, rpe: 5, talkTest: false),
                steps: [LoggedStep(isWork: false, meters: 1_500, seconds: 600), work, LoggedStep(isWork: false, meters: 1_500, seconds: 600)]
            )
            runs.append(run)
            let result = review(run, state, runs: runs)
            state = result.0
            reviews.append(result.1)
        }
        #expect(reviews.map(\.outcome) == Array(repeating: .evenAndOnTarget, count: 4))
        #expect(reviews[0].insights.first == CoachNote(.insight, "Even pacing, right on target. Nice work."))
        #expect(reviews[1].notes.contains(PaceUpdates.raiseNote))
        // The next two would raise again, but not within 2 weeks of the last raise (HL-27).
        #expect(!reviews[3].notes.contains(PaceUpdates.raiseNote))
        #expect(abs(state.paces.qualityFactor - PaceUpdates.raiseFactor) < 1e-9)
        #expect(state.quality.evenStreak == 2)
    }

    // MARK: PZ-8 and FB-4c

    @Test func theThirdComfortableEasyRunChecksTheReportedPace() throws {
        var state = plan()
        var runs: [LoggedRun] = []
        var last: RunReview?
        for day in [0, 2, 4] {
            let run = LoggedRun(start: CoachFixtures.day(day), movingSeconds: 4 * 420, meters: 4_000, checkIn: checkIn(day: day, rpe: 3))
            runs.append(run)
            (state, last) = review(run, state, runs: runs)
        }
        #expect(band(state.paces.easy, is: 420, 462))
        #expect(state.paces.easySource == .logged)
        #expect(last?.notes.contains(CoachNote(.pace, "Your easy runs have been about 17% slower than the pace you gave me, so I've set your easy pace from your runs.")) == true)
    }

    @Test func easyRunsTooFastMoveTheBandOnce() throws {
        var state = plan()
        var runs: [LoggedRun] = []
        var last: RunReview?
        for day in [1, 3] {
            let session = try session(state, day: day)
            let run = LoggedRun(start: CoachFixtures.day(day), movingSeconds: 3.2 * 330, meters: 3_200, plannedSessionID: session.id, checkIn: checkIn(day: day, rpe: 4, talkTest: false))
            runs.append(run)
            (state, last) = review(run, state, runs: runs)
        }
        #expect(band(state.paces.easy, is: 375, 411))
        #expect(last?.insights.contains { $0.text == PaceUpdates.easySlowerNote.text } == true)
        // A second review of the same run keeps the one move.
        let again = review(runs[1], state, runs: runs).0
        #expect(band(again.paces.easy, is: 375, 411))
    }

    // MARK: BD-1e and PZ-13

    @Test func aLongestRunYetIsTheFirstInsight() {
        let state = plan()
        let run = LoggedRun(start: CoachFixtures.day(4), movingSeconds: 10.5 * 378, meters: 10_500, checkIn: checkIn(day: 4, rpe: 3))
        let review = review(run, state, runs: [run]).1
        #expect(review.milestones == [.longestRun(meters: 10_500)])
        #expect(review.insights.first == CoachNote(.milestone, "Longest run yet: 10.5 km."))
    }

    @Test func heartRateStaysOnTheRunAndNeverReachesTheState() throws {
        let state = plan()
        let tuesday = try session(state, day: 1)
        var run = CoachFixtures.run(for: tuesday, on: CoachFixtures.day(1), pace: 378)
        run.heartRate = RunHeartRate(source: .appleWatch, coverage: 0.95, mean: 147.25)
        run.cadence = 163.5
        let (after, review) = review(run, state, runs: [run])
        #expect(review.heartRate == .usedForCoaching)
        let json = try #require(String(data: JSONEncoder().encode(after), encoding: .utf8))
        #expect(!json.contains("147.25"))
        #expect(!json.contains("163.5"))

        var shown = run
        shown.heartRate = RunHeartRate(source: .appleWatch, useForCoaching: false, coverage: 0.95, mean: 147.25)
        #expect(self.review(shown, state, runs: [shown]).1.heartRate == .shownOnly)
    }

    // MARK: FB-4n

    @Test func theCadenceCueIsOfferedOnceAndStopsWithACalfReport() throws {
        var state = plan()
        let baseline = InjuryBaseline(volumeUnit: .distance, weekVolume: 16_000, longRun: Load(meters: 8_000, seconds: 3_024))
        let knee = InjuryReport(reportedAt: CoachFixtures.day(0, hour: 8), origin: .planScreen, level: .mild, area: .knee, baseline: baseline)
        state.injuries.append(knee)
        var first = CoachFixtures.run(for: try session(state, day: 1), on: CoachFixtures.day(1), pace: 378)
        first.cadence = 162
        let (offered, review) = review(first, state, runs: [first])
        #expect(review.questions.contains(.cadenceCue))
        #expect(RunReviewer.prompt(for: .cadenceCue, state: offered, calendar: calendar)?.text == "Slightly shorter, quicker steps can ease the load on your knee. Want a cue on easy runs?")
        #expect(RunReviewer.questions(offered, runs: [first], now: CoachFixtures.day(1, hour: 12), calendar: calendar).contains(.cadenceCue))

        let yes = RunReviewer.answer(.cadenceCue(true), state: offered, runs: [first], now: CoachFixtures.day(1, hour: 12), calendar: calendar).state
        #expect(yes.runReview.cadence?.reportID == knee.id)
        #expect(!RunReviewer.questions(yes, runs: [first], now: CoachFixtures.day(1, hour: 13), calendar: calendar).contains(.cadenceCue))
        #expect(RunReviewer.cadenceCue(state: yes, runs: [first], now: CoachFixtures.day(3), calendar: calendar)
            == "Try slightly shorter, quicker steps: about 170 steps per minute instead of your usual 162.")
        #expect(RunReviewer.cadenceCue(state: yes, runs: [first], now: CoachFixtures.day(16), calendar: calendar)
            == "Try slightly shorter, quicker steps: about 174 steps per minute instead of your usual 162.")

        // The cue shows after the next easy run with step-rate data.
        var thursday = CoachFixtures.run(for: try session(yes, day: 3), on: CoachFixtures.day(3), pace: 378)
        thursday.cadence = 166
        #expect(self.review(thursday, yes, runs: [first, thursday]).1.insights.last?.text
            == "Try slightly shorter, quicker steps: about 170 steps per minute instead of your usual 162.")

        var calf = yes
        calf.injuries.append(InjuryReport(reportedAt: CoachFixtures.day(4), origin: .planScreen, level: .mild, area: .calfAchilles, baseline: baseline))
        #expect(RunReviewer.cadenceCue(state: calf, runs: [first], now: CoachFixtures.day(5), calendar: calendar) == nil)
    }

    // MARK: Baselines

    @Test func aRestoredBaselineGetsTheRunsChangesBack() throws {
        let (state, sessions) = racePaceState(days: [2, 4])
        let baseline = PlanBaseline(state)
        let first = fadingRun(for: sessions[0], day: 2)
        let second = fadingRun(for: sessions[1], day: 4)
        var after = review(first, state, runs: [first]).0
        after = review(second, after, runs: [first, second]).0

        // Planning restores the cycle and the Q state: the outcomes and the retest come back.
        var planned = after
        baseline.restorePlanning(into: &planned)
        #expect(planned.quality.outcomes.isEmpty)
        RunReviewer.restoreRunFacts(into: &planned, week: 0, since: baseline, paces: false)
        #expect(planned.quality.outcomes.map(\.outcome) == [.struggled, .failed])
        #expect(planned.quality.retestWeek == 2)

        // A full restore puts the paces back too; the cut is made again, once.
        var reviewed = after
        baseline.restore(into: &reviewed)
        #expect(reviewed.paces.qualityFactor == 1)
        RunReviewer.restoreRunFacts(into: &reviewed, week: 0, since: baseline, paces: true)
        #expect(abs(reviewed.paces.qualityFactor - PaceUpdates.cutFactor) < 1e-9)

        // A change the baseline holds whose run is gone is taken back.
        let later = PlanBaseline(after)
        var forgotten = RunReviewer.syncMatches(after, runs: [first], now: CoachFixtures.day(5), calendar: calendar)
        #expect(forgotten.quality.retestWeek == nil)
        later.restore(into: &forgotten)
        RunReviewer.restoreRunFacts(into: &forgotten, week: 0, since: later, paces: true)
        #expect(abs(forgotten.paces.qualityFactor - 1) < 1e-9)
        #expect(forgotten.quality.retestWeek == nil)
        #expect(forgotten.quality.outcomes.map(\.outcome) == [.struggled])
    }
}

/// AD-8: extra runs and spikes, checked hard, spike, total, rest, then the habit offer.
@MainActor
struct ExtraRunTests {
    let calendar = CoachFixtures.calendar

    func review(_ run: LoggedRun, _ state: CoachState, runs: [LoggedRun]) -> (CoachState, RunReview) {
        RunReviewer.review(run, state: state, runs: runs, now: run.end.addingTimeInterval(1_800), calendar: calendar)
    }

    func checkIn(day: Int, rpe: Int, friends: Bool = false) -> RunCheckIn {
        var checkIn = RunCheckIn(answeredAt: CoachFixtures.day(day, hour: 9), rpe: rpe, talkTest: rpe <= 3, feel: .ok)
        checkIn.unplannedOrWithFriends = friends
        return checkIn
    }

    /// The owner's example: a Regular runner's plan of Tue 6 km, Thu 6 km and Sun 12 km (24 km), P-L30 12 km,
    /// W4max 24 km, easy 6:30/km.
    func example() throws -> CoachState {
        var intake = CoachFixtures.regularIntake()
        intake.lastFourWeeks = RecentRunning(runsPerWeek: 3, weeklyLow: .distance(meters: 24_000), weeklyHigh: .distance(meters: 26_000), longest: .distance(meters: 13_400))
        intake.easyPace = 390
        var state = CoachFixtures.start(intake)
        let pace = try #require(state.paces.easyPace)
        for index in state.weeks[0].plan.sessions.indices where state.weeks[0].plan.sessions[index].kind == .easy {
            state.weeks[0].plan.sessions[index].target = Load(meters: 6_000, seconds: 6 * pace)
        }
        state.weeks[0].plan.plannedVolume = 24_000
        #expect(state.weeks[0].plan.sessions.first { $0.kind == .long }?.target.meters == 12_000)
        return state
    }

    /// The example with Tuesday's 6 km done.
    func afterTuesday() throws -> (CoachState, [LoggedRun]) {
        let state = try example()
        let tuesday = try #require(state.weeks[0].plan.sessions.first { $0.dayOffset == 1 })
        let run = CoachFixtures.run(for: tuesday, on: CoachFixtures.day(1), pace: 390)
        return (review(run, state, runs: [run]).0, [run])
    }

    func run(day: Int, meters: Double, pace: Double = 390, rpe: Int = 3, friends: Bool = false) -> LoggedRun {
        LoggedRun(start: CoachFixtures.day(day), movingSeconds: meters / 1_000 * pace, meters: meters, checkIn: checkIn(day: day, rpe: rpe, friends: friends))
    }

    @Test func aSocialRunTrimsThursday() throws {
        var (state, runs) = try afterTuesday()
        let friend = run(day: 2, meters: 4_000, friends: true)
        runs.append(friend)
        let review: RunReview
        (state, review) = self.review(friend, state, runs: runs)
        #expect(review.match == .extra)
        #expect(review.notes == [CoachNote(.plan, "Nice social run. I've shortened Thursday a little so your week stays in range.")])
        let thursday = try #require(state.weeks[0].plan.sessions.first { $0.dayOffset == 3 })
        #expect(abs(thursday.target.meters - 4_400) < 0.5)
        #expect(thursday.target.seconds >= 20 * 60)
        #expect(state.weeks[0].plan.sessions.first { $0.kind == .long }?.target.meters == 12_000)
    }

    @Test func anExtraRunNeverMatchesTheRunItTrimmed() throws {
        var (state, runs) = try afterTuesday()
        let friend = run(day: 2, meters: 4_000, friends: true)
        runs.append(friend)
        state = review(friend, state, runs: runs).0
        let thursday = try #require(state.weeks[0].plan.sessions.first { $0.dayOffset == 3 })
        #expect(RunReviewer.match(friend, state: state, calendar: calendar) == .extra)
        // Without the record, 4 km would now be Thursday's 4.4 km run a day early.
        var unmarked = state
        unmarked.runReview.extraRunIDs = []
        #expect(RunReviewer.match(friend, state: unmarked, calendar: calendar) == .planned(sessionID: thursday.id))
    }

    @Test func aReplanKeepsTheTrimAndItsSentence() throws {
        var (state, runs) = try afterTuesday()
        let friend = run(day: 2, meters: 4_000, friends: true)
        runs.append(friend)
        state = review(friend, state, runs: runs).0
        let index = try #require(state.weeks[0].plan.sessions.firstIndex { $0.dayOffset == 3 })
        let pace = try #require(state.paces.easyPace)

        // A fresh layout puts Thursday back at 6 km; the trim is made again, and only once.
        var replanned = state
        replanned.weeks[0].plan.sessions[index].target = Load(meters: 6_000, seconds: 6 * pace)
        let now = CoachFixtures.day(2, hour: 12)
        replanned = RunReviewer.adjustPlan(replanned, week: 0, runs: runs, now: now, calendar: calendar)
        #expect(abs(replanned.weeks[0].plan.sessions[index].target.meters - 4_400) < 0.5)
        #expect(RunReviewer.adjustPlan(replanned, week: 0, runs: runs, now: now, calendar: calendar) == replanned)
        #expect(review(friend, replanned, runs: runs).1.notes == [CoachNote(.plan, "Nice social run. I've shortened Thursday a little so your week stays in range.")])
    }

    @Test func aRunADayEarlyIsThursdaysAndAnotherOneHoldsNextWeek() throws {
        var (state, runs) = try afterTuesday()
        let wednesday = run(day: 2, meters: 6_000, friends: true)
        runs.append(wednesday)
        let early: RunReview
        (state, early) = review(wednesday, state, runs: runs)
        #expect(early.notes == [CoachNote(.plan, "Looks like you ran Thursday's run a day early.")])

        let thursday = run(day: 3, meters: 6_000)
        runs.append(thursday)
        let extra: RunReview
        (state, extra) = review(thursday, state, runs: runs)
        #expect(extra.match == .extra)
        #expect(extra.notes == [CoachNote(.plan, "Nice extra run. Your week is now over its range, so next week holds at this level.")])

        let sunday = try #require(state.weeks[0].plan.sessions.first { $0.kind == .long })
        let long = CoachFixtures.run(for: sunday, on: CoachFixtures.day(6), pace: 390)
        runs.append(long)
        state = review(long, state, runs: runs).0
        #expect(RunReviewer.weekSignals(week: 0, state: state, runs: runs, calendar: calendar).overPlan)
    }

    @Test func aHardExtraRunTakesTheWeeksSpeedSession() throws {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        state.quality.gateMetOn = CoachFixtures.day(0)
        let index = try #require(state.weeks[0].plan.sessions.firstIndex { $0.dayOffset == 3 })
        state.weeks[0].plan.sessions[index].kind = .threshold
        state.weeks[0].plan.sessions[index].effort = .threshold
        state.weeks[0].plan.sessions[index].dose = QualityDose(type: .threshold, step: 1, reps: 1, repSeconds: 1_200, recoverySeconds: 0, continuous: true)
        // 35 minutes, so it can't be Tuesday's 20-minute run a day late.
        let fast = run(day: 2, meters: 7_000, pace: 300, rpe: 7)
        let (after, review) = review(fast, state, runs: [fast])
        #expect(review.match == .extra)
        #expect(review.notes.contains(CoachNote(.plan, "That run was hard, so it counts as this week's speed session and Thursday's tempo run is an easy run instead.")))
        let thursday = after.weeks[0].plan.sessions[index]
        #expect(thursday.madeEasy == .extraRun)
        #expect(!thursday.isQuality)
        #expect(!review.notes.contains { $0.text.hasPrefix("Fun run!") })
        // AD-2: a Q, so the morning check comes the next day.
        #expect(RunReviewer.questions(after, runs: [fast], now: CoachFixtures.day(3), calendar: calendar).contains(.morningCheck(runID: fast.id)))
    }

    @Test func aHardRunBeforeTheGateIsAFunRunAndTheLongRunWaits() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let parkrun = run(day: 5, meters: 5_000, pace: 300, rpe: 7)
        let (after, review) = review(parkrun, state, runs: [parkrun])
        #expect(review.notes.contains(CoachNote(.plan, "Fun run! For now I keep your plan easy so your legs adapt first.")))
        #expect(review.notes.contains(CoachNote(.plan, "Your legs need 48 hours after that run, so I've dropped Sunday's long run this week.")))
        #expect(after.weeks[0].plan.sessions.first { $0.kind == .long }?.status == .dropped)

        // Said once.
        let again = LoggedRun(start: CoachFixtures.day(6, hour: 10), movingSeconds: 1_500, meters: 5_000, checkIn: checkIn(day: 6, rpe: 7))
        #expect(!self.review(again, after, runs: [parkrun, again]).1.notes.contains { $0.text.hasPrefix("Fun run!") })
    }

    @Test func aSpikeAsksTheMorningCheckOnDays1And2() {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let spike = run(day: 2, meters: 12_000, pace: 360)
        let after = review(spike, state, runs: [spike]).0
        #expect(after.runReview.spikes.map(\.runID) == [spike.id])
        #expect(after.runReview.spikes.first?.large == false)
        func asks(on day: Int, _ state: CoachState) -> Bool {
            RunReviewer.questions(state, runs: [spike], now: CoachFixtures.day(day), calendar: calendar).contains(.morningCheck(runID: spike.id))
        }
        #expect(asks(on: 3, after))
        #expect(asks(on: 4, after))
        #expect(!asks(on: 5, after))
        var answered = after
        answered.morningChecks.append(MorningCheck(date: CoachFixtures.day(4, hour: 6), fatigue: 4, soreness: 4))
        #expect(!asks(on: 4, answered))
        // A run that isn't long, new, hard or a spike asks nothing.
        let easy = run(day: 2, meters: 3_000)
        let plain = review(easy, state, runs: [easy]).0
        #expect(!RunReviewer.questions(plain, runs: [easy], now: CoachFixtures.day(3), calendar: calendar).contains(.morningCheck(runID: easy.id)))
    }

    @Test func extraRunsMostWednesdaysOfferAPlannedSlot() throws {
        let simulation = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake()), days: 21)
        let extras = [2, 9, 16].map { run(day: $0, meters: 2_000, friends: true) }
        let runs = simulation.runs + extras
        let offer = try #require(ExtraRuns.habitOffer(extras[2], state: simulation.state, runs: runs, calendar: calendar))
        #expect(offer.question == .extraRunSlot(day: .wednesday))
        #expect(offer.text == "You've run with a friend most Wednesdays. Want me to make it a planned run? Your weekly total stays the same.")
        // Two weeks aren't a habit yet.
        #expect(ExtraRuns.habitOffer(extras[1], state: simulation.state, runs: runs, calendar: calendar) == nil)

        var state = simulation.state
        state.runReview.offers.append(offer)
        let update = RunReviewer.answer(.extraRunSlot(day: .wednesday, accept: true), state: state, runs: runs, now: CoachFixtures.day(16, hour: 12), calendar: calendar)
        #expect(update.notes == [CoachNote(.plan, "Done: Wednesday is now a planned run. Your weekly total stays the same.")])
        #expect(update.state.intake.runDays.contains(.wednesday))
        #expect(update.state.cycle.runsPerWeek == simulation.state.cycle.runsPerWeek + 1)
        #expect(update.state.cycle.lastRunAddedWeek == 2)
        #expect(update.state.runReview.offers.last?.answeredAt != nil)
        #expect(RunReviewer.questions(update.state, runs: runs, now: CoachFixtures.day(16, hour: 13), calendar: calendar).isEmpty)
    }

    @Test func yesToABenchmarkSoonerBringsTheRetestForward() {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let update = RunReviewer.answer(.benchmarkSooner(true), state: state, runs: [], now: CoachFixtures.day(10), calendar: calendar)
        #expect(update.state.quality.retestWeek == 2)
        #expect(update.state.runReview.benchmarkAnsweredAt == CoachFixtures.day(10))
        #expect(update.notes == [CoachNote(.plan, "I'll bring your next check run forward.")])
        #expect(RunReviewer.prompt(for: .benchmarkSooner, state: state, calendar: calendar)?.detail == "I'll bring your next check run forward.")
    }
}

/// PZ-13's resting-HR flag and family H: worked out on the device from HealthKit's values, never kept.
@MainActor
struct RestingHeartRateTests {
    let calendar = CoachFixtures.calendar
    let state = CoachFixtures.start(CoachFixtures.regularIntake())
    let watch = HeartRateSettings(device: .appleWatch)

    /// 50 bpm each morning for the 4 weeks before day 4 of plan week 0, then these values on days 4 and 5.
    func readings(day4: Double, day5: Double, device5: String = "watch") -> [RestingHeartRate] {
        (-24 ... 3).map { RestingHeartRate(date: CoachFixtures.day($0, hour: 8), bpm: 50, device: "watch") }
            + [RestingHeartRate(date: CoachFixtures.day(4, hour: 8), bpm: day4, device: "watch"),
               RestingHeartRate(date: CoachFixtures.day(5, hour: 8), bpm: day5, device: device5)]
    }

    @Test func twoRaisedDaysOfferTheLongRunEasy() throws {
        let long = try #require(state.weeks[0].plan.sessions.first { $0.kind == .long && $0.dayOffset == 6 })
        let check = RestingHeartRate.check(readings(day4: 53, day5: 54), settings: watch, state: state, now: CoachFixtures.day(6), calendar: calendar)
        #expect(check == RestingHeartRateCheck(note: CoachNote(.insight, HeartRateRules.restingNote), easySessionID: long.id))
        #expect(RunReviewer.weekSignals(week: 0, state: state, runs: [], calendar: calendar, resting: readings(day4: 53, day5: 54), heartRateSettings: watch).heartRateNegative)
        #expect(!RunReviewer.weekSignals(week: 0, state: state, runs: [], calendar: calendar).heartRateNegative)
    }

    @Test func oneDayAnotherDeviceOrShowOnlyIsNoFlag() {
        let now = CoachFixtures.day(6)
        // 5.8% above on day 4 is under the line.
        #expect(RestingHeartRate.check(readings(day4: 52.9, day5: 54), settings: watch, state: state, now: now, calendar: calendar) == nil)
        // Day 5's raised value came from another device, so the watch has no value that day.
        #expect(RestingHeartRate.check(readings(day4: 54, day5: 54, device5: "ring"), settings: watch, state: state, now: now, calendar: calendar) == nil)
        let showOnly = HeartRateSettings(device: .appleWatch, useForCoaching: false)
        #expect(RestingHeartRate.check(readings(day4: 54, day5: 54), settings: showOnly, state: state, now: now, calendar: calendar) == nil)
    }

    @Test func aBaselineNeedsSevenValues() {
        let few = readings(day4: 60, day5: 60).filter { $0.date >= CoachFixtures.day(-2) }
        #expect(few.count == 8)
        #expect(!HeartRateRules.restingRaised(few, settings: watch, on: CoachFixtures.day(6), calendar: calendar))
        #expect(HeartRateRules.restingRaised(readings(day4: 60, day5: 60), settings: watch, on: CoachFixtures.day(6), calendar: calendar))
    }
}
