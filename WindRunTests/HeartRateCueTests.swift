//
//  HeartRateCueTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The in-run heart-rate cue (PZ-12): which parts of a session cue, the 60-second hold, the
/// device margin, the quiet start on a watch, and re-arming.
@MainActor
struct HeartRateCueTests {
    /// Age 40: an estimated max of 180, so an easy ceiling of 135 and a threshold band of 153-162.
    private let zones = HeartRateZones.estimated(age: 40)

    private func easyRun() -> PlannedSession {
        PlannedSession(dayOffset: 0, kind: .easy, effort: .easy, target: Load(meters: 6_000, seconds: 40 * 60))
    }

    private func session(_ kind: SessionKind, effort: Effort, repeats: Int, work: StepGoal, pace: PaceBand? = nil) -> PlannedSession {
        PlannedSession(
            dayOffset: 0,
            kind: kind,
            effort: effort,
            target: Load(meters: 8_000, seconds: 50 * 60),
            blocks: [
                SessionBlock(steps: [SessionStep(kind: .warmup, goal: .time(seconds: 600), effort: .easy)]),
                SessionBlock(repeats: repeats, steps: [
                    SessionStep(kind: .work, goal: work, effort: effort, pace: pace),
                    SessionStep(kind: .recovery, goal: .time(seconds: 120), effort: .easy),
                ]),
                SessionBlock(steps: [SessionStep(kind: .cooldown, goal: .time(seconds: 600), effort: .easy)]),
            ]
        )
    }

    /// Feeds the tracker one reading a second and returns the seconds at which the cue played.
    private func cues(_ tracker: inout HeartRateCueTracker, from start: Int = 0, to end: Int, beatsPerMinute: (Int) -> Double?) -> [Int] {
        var played: [Int] = []
        for second in start...end where tracker.update(elapsed: TimeInterval(second), meters: Double(second) * 2.5, beatsPerMinute: beatsPerMinute(second)) {
            played.append(second)
        }
        return played
    }

    // MARK: Which parts cue

    @Test func anEasyRunHoldsTheEasyCeilingToTheEnd() {
        let parts = HeartRateCue.parts(for: easyRun(), zones: zones, device: .chestStrap, thresholdPace: nil)
        #expect(parts == [HeartRateCue.Part(span: .toEnd, ceiling: zones.easyCeiling)])
    }

    @Test func thresholdRepsCueFromTheirSecondMinute() {
        let parts = HeartRateCue.parts(for: session(.threshold, effort: .threshold, repeats: 3, work: .time(seconds: 8 * 60)), zones: zones, device: .chestStrap, thresholdPace: nil)
        let work = parts.filter { $0.ceiling != nil }
        #expect(work.count == 3)
        #expect(work.allSatisfy { $0.ceiling == zones.thresholdBand.upperBound && $0.delay == 60 })
        // Warm-up, recoveries and cool-down never cue.
        #expect(parts.count == 8)
        #expect(parts.first?.ceiling == nil)
        #expect(parts.last?.ceiling == nil)
    }

    @Test func shortThresholdRepsDontCue() {
        let twoMinutes = session(.threshold, effort: .threshold, repeats: 6, work: .time(seconds: 120))
        #expect(HeartRateCue.parts(for: twoMinutes, zones: zones, device: .chestStrap, thresholdPace: nil).isEmpty)

        // 3.5-minute reps cue with a strap, but an Apple Watch needs 4 minutes.
        let threeAndAHalf = session(.threshold, effort: .threshold, repeats: 4, work: .time(seconds: 210))
        #expect(!HeartRateCue.parts(for: threeAndAHalf, zones: zones, device: .chestStrap, thresholdPace: nil).isEmpty)
        #expect(HeartRateCue.parts(for: threeAndAHalf, zones: zones, device: .appleWatch, thresholdPace: nil).isEmpty)

        // Distance reps are timed at their pace: 1 km at 4:00 is 4 minutes.
        let kilometers = session(.threshold, effort: .threshold, repeats: 4, work: .distance(meters: 1_000), pace: PaceBand(fast: 235, slow: 245))
        #expect(!HeartRateCue.parts(for: kilometers, zones: zones, device: .appleWatch, thresholdPace: nil).isEmpty)
    }

    @Test func hardSessionsAndTestsNeverCue() {
        let vo2 = session(.intervals, effort: .interval, repeats: 5, work: .time(seconds: 180))
        let hills = session(.hills, effort: .interval, repeats: 8, work: .time(seconds: 60))
        let test = PlannedSession(dayOffset: 0, kind: .test, effort: .race, target: Load(meters: 3_000, seconds: 30 * 60), appTest: AppTest(goal: .time(seconds: 720), controlled: false))
        let race = PlannedSession(dayOffset: 0, kind: .race, effort: .race, target: Load(meters: 10_000, seconds: 50 * 60))
        for session in [vo2, hills, test, race] {
            #expect(HeartRateCue.parts(for: session, zones: zones, device: .chestStrap, thresholdPace: nil).isEmpty, "\(session.kind)")
        }
    }

    @Test func steadyWorkWaitsFiveMinutesOnAWatch() {
        let steady = session(.racePace, effort: .steady, repeats: 1, work: .time(seconds: 20 * 60))
        let strap = HeartRateCue.parts(for: steady, zones: zones, device: .chestStrap, thresholdPace: nil).first { $0.ceiling != nil }
        let watch = HeartRateCue.parts(for: steady, zones: zones, device: .appleWatch, thresholdPace: nil).first { $0.ceiling != nil }
        #expect(strap?.ceiling == zones.steadyCeiling)
        #expect(strap?.delay == 0)
        #expect(watch?.delay == 300)
    }

    // MARK: Trigger

    @Test func theCuePlaysAfterAMinuteOver() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        // Over from second 10: the cue plays at second 70, not before.
        let played = cues(&tracker, to: 100) { $0 >= 10 ? 145 : 120 }
        #expect(played == [70])
    }

    @Test func aDipUnderTheMarginRestartsTheHold() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        // A strap's margin is 5: 139 is over the ceiling but not over the margin.
        let played = cues(&tracker, to: 150) { second in
            if second < 40 { return 145 }
            if second < 50 { return 139 }
            return 145
        }
        #expect(played == [110])
    }

    @Test func theMarginDependsOnTheDevice() {
        // 142 is 7 over: past a strap's 5 but inside a watch's 10.
        var strap = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        var watch = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .appleWatch)
        #expect(!cues(&strap, from: 400, to: 500) { _ in 142 }.isEmpty)
        #expect(cues(&watch, from: 400, to: 500) { _ in 142 }.isEmpty)
    }

    @Test func aWatchStaysQuietForTheFirstFiveMinutes() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .appleWatch)
        let played = cues(&tracker, to: 400) { _ in 160 }
        #expect(played == [360])
    }

    @Test func noReadingNeverCues() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        #expect(cues(&tracker, to: 200) { _ in nil }.isEmpty)
    }

    @Test func itReArmsUnderTheCeilingAndWaitsThreeMinutes() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        let played = cues(&tracker, to: 600) { second in
            switch second {
            case ..<100: 145
            // Back under the ceiling, which re-arms it.
            case 100..<110: 130
            // Over again: a minute passes at 170, but only 3 minutes after the first cue may it play.
            case 110..<500: 145
            default: 130
            }
        }
        #expect(played == [60, 240])
    }

    @Test func stayingOverDoesntRepeatWithoutComingBackUnder() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        #expect(cues(&tracker, to: 900) { _ in 145 } == [60])
    }

    @Test func onlyPartsWithACeilingCue() {
        // A 2-minute warm-up with no ceiling, then a part with one, counted from its second minute.
        let parts = [
            HeartRateCue.Part(span: .seconds(120), ceiling: nil),
            HeartRateCue.Part(span: .seconds(600), ceiling: 160, delay: 60),
        ]
        var tracker = HeartRateCueTracker(parts: parts, device: .chestStrap)
        let played = cues(&tracker, to: 800) { _ in 175 }
        // The work part starts at 120, cues from 180, and the hold ends at 240. After the part ends, nothing.
        #expect(played == [240])
    }

    @Test func distancePartsEndByDistance() {
        let parts = [
            HeartRateCue.Part(span: .meters(500), ceiling: nil),
            HeartRateCue.Part(span: .toEnd, ceiling: 135),
        ]
        var tracker = HeartRateCueTracker(parts: parts, device: .chestStrap)
        // At 2.5 m a second, 500 m ends at second 200; the cue plays a minute later.
        #expect(cues(&tracker, to: 400) { _ in 150 } == [260])
    }

    // MARK: Answers through CoachEngine.answer

    @Test func yesOrNoCardsMapToTheirAnswers() {
        #expect(CoachQuestionCard.coachAnswer(for: .lighterWeek, value: "yes") == .lighterWeek(true))
        #expect(CoachQuestionCard.coachAnswer(for: .lighterWeek, value: "no") == .lighterWeek(false))
        #expect(CoachQuestionCard.coachAnswer(for: .levelUp(.ambitious), value: "yes") == .levelUp(true))
        #expect(CoachQuestionCard.coachAnswer(for: .ladderEasierRestart, value: "no") == .ladderEasierRestart(false))
        #expect(CoachQuestionCard.coachAnswer(for: .missedRuns, value: "wornOut") == .missedRuns(.wornOut))
        #expect(CoachQuestionCard.coachAnswer(for: .runCheckIn(runID: UUID()), value: "yes") == nil)
    }

    @Test func theCardsChoicesAreTheValuesTheMappingReads() {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        for question in [CoachQuestion.lighterWeek, .levelUp(.ambitious), .ladderEasierRestart] {
            let values = CoachEngine.prompt(for: question, state: state, calendar: CoachFixtures.calendar).choices.map(\.value)
            #expect(values == ["yes", "no"], "\(question)")
            #expect(values.allSatisfy { CoachQuestionCard.coachAnswer(for: question, value: $0) != nil })
        }
    }

    @Test func aLighterWeekShortensTheRestOfTheWeek() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let week = try #require(state.weeks.first?.plan)
        let now = CoachFixtures.day(0, hour: 6, from: week.start)
        let (update, _) = CoachEngine.answer(.lighterWeek(true), state: state, runs: [], now: now, calendar: CoachFixtures.calendar)
        let before = week.sessions.filter { $0.kind.isRun && !$0.isKey }.map(\.target.meters)
        let after = try #require(update.state.weeks.first?.plan).sessions.filter { $0.kind.isRun && !$0.isKey }.map(\.target.meters)
        #expect(!before.isEmpty)
        #expect(zip(before, after).allSatisfy { $1 < $0 })
    }

    @Test func movingUpALevelChangesIt() {
        let state = CoachFixtures.start(CoachFixtures.regularIntake(level: .gentle))
        let (update, _) = CoachEngine.answer(.levelUp(true), state: state, runs: [], now: CoachFixtures.day(1), calendar: CoachFixtures.calendar)
        #expect(state.level == .gentle)
        #expect(update.state.level == min(.steady, state.assessment.levels.ceiling))
    }
}
