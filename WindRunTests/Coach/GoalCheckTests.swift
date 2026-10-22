//
//  GoalCheckTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// The realism check against the rules' worked examples: RC-11's owner example, RC-6's time goals, SW-1a's
/// strong first half, the refusals (RC-1, HL-26) and RC-8's messages.
@MainActor
struct GoalCheckTests {
    let calendar = CoachFixtures.calendar
    let now = CoachFixtures.day(0)

    func weeksLater(_ weeks: Int) -> Date {
        CoachFixtures.day(7 * weeks)
    }

    /// RC-11's runner: 8 months of running, longest 5 km, about 10 km a week, easy 6:00/km, no injury or gym.
    func ownerIntake(_ goal: GoalChoice) -> CoachIntake {
        var intake = CoachIntake(goal: goal, answeredAt: now)
        intake.finished = .no
        intake.birthYear = 1996
        intake.runs30Minutes = true
        intake.history = .threeToTwelveMonths
        intake.monthsRunning = 8
        intake.lastFourWeeks = RecentRunning(runsPerWeek: 3, weeklyLow: .distance(meters: 10_000), longest: .distance(meters: 5_000))
        intake.easyPace = 360
        intake.otherTraining = []
        intake.physicalWork = false
        intake.runDays = [.tuesday, .thursday, .sunday]
        intake.longRunDay = .sunday
        return intake
    }

    func check(_ intake: CoachIntake, _ goal: GoalChoice? = nil, level: CommitmentLevel = .steady) -> GoalCheck {
        let assessment = RunnerAssessor.assess(intake, now: now, calendar: calendar)
        let paces = PaceCalculator.initialPaces(intake, now: now, calendar: calendar)
        return GoalChecker.check(goal ?? intake.goal, intake: intake, assessment: assessment, paces: paces, level: level, now: now, calendar: calendar)
    }

    func input(_ intake: CoachIntake, level: CommitmentLevel = .steady) -> FeasibilityInput {
        let assessment = RunnerAssessor.assess(intake, now: now, calendar: calendar)
        let paces = PaceCalculator.initialPaces(intake, now: now, calendar: calendar)
        return FeasibilityInput(intake: intake, assessment: assessment, paces: paces, level: level, now: now, calendar: calendar)
    }

    func event(_ distance: RaceDistance, weeks: Int, target: Double? = nil) -> GoalChoice {
        GoalChoice(flavor: .event, distance: distance, targetSeconds: target, eventDate: weeksLater(weeks))
    }

    /// IN-5: a months answer counts only inside its band. One left over from "Under 3 months" no longer makes a
    /// runner of 1-2 years "0 months" in.
    @Test func monthsAnswerStaysInsideItsBand() {
        var intake = ownerIntake(GoalChoice(flavor: .buildDistance, distance: .marathon))
        intake.history = .oneToTwoYears
        intake.monthsRunning = 0
        #expect(RunnerAssessor.assess(intake, now: now, calendar: calendar).monthsRunning == 12)
        intake.history = .threeToTwelveMonths
        #expect(RunnerAssessor.assess(intake, now: now, calendar: calendar).monthsRunning == 3)
        intake.monthsRunning = 8
        #expect(RunnerAssessor.assess(intake, now: now, calendar: calendar).monthsRunning == 8)
        intake.history = .underThreeMonths
        #expect(RunnerAssessor.assess(intake, now: now, calendar: calendar).monthsRunning == 2)
    }

    // MARK: RC-11

    /// RC-11 step 4: 13 weeks at Steady from 4.5 km. The marathon and half reach about 8.0 km (Red), the 10K
    /// about 8.8 km (Amber), and the 5K is Green.
    @Test func ownerExampleStatusesAtSteady() throws {
        let runner = input(ownerIntake(event(.marathon, weeks: 13)))
        #expect(abs(runner.longest - 4_500) < 1)
        func evaluate(_ distance: RaceDistance) -> Feasibility {
            FeasibilityEngine.evaluate(event(distance, weeks: 13), input: runner, firstTimer: true, weeksAvailable: 13, now: now, calendar: calendar)
        }
        let marathon = evaluate(.marathon)
        #expect(abs(marathon.projectedLongest.meters - 7_972) < 10)
        #expect(marathon.status == .red)
        let half = evaluate(.halfMarathon)
        #expect(abs(half.projectedLongest.meters - 7_972) < 10)
        #expect(half.status == .red)
        let tenK = evaluate(.tenK)
        #expect(abs(tenK.projectedLongest.meters - 8_769) < 10)
        #expect(tenK.status == .amber)
        #expect(evaluate(.fiveK).status == .green)
    }

    /// RC-11: at Gentle the marathon row reaches only about 6.6 km; from a logged 5 km at the week-2 re-run,
    /// about 8.9 km for the marathon and 9.7 km for the 10K.
    @Test func ownerExampleGentleAndReRun() {
        let gentle = input(ownerIntake(event(.marathon, weeks: 13)), level: .gentle)
        let marathon = FeasibilityEngine.evaluate(event(.marathon, weeks: 13), input: gentle, firstTimer: true, weeksAvailable: 13, now: now, calendar: calendar)
        #expect(abs(marathon.projectedLongest.meters - 6_588) < 10)

        var rerun = input(ownerIntake(event(.marathon, weeks: 13)))
        rerun.longest = 5_000
        rerun.calibrationWeeks = 0
        let fromFive = FeasibilityEngine.evaluate(event(.marathon, weeks: 11), input: rerun, firstTimer: true, weeksAvailable: 11, now: now, calendar: calendar)
        #expect(abs(fromFive.projectedLongest.meters - 8_858) < 10)
        let tenK = FeasibilityEngine.evaluate(event(.tenK, weeks: 11), input: rerun, firstTimer: true, weeksAvailable: 11, now: now, calendar: calendar)
        #expect(abs(tenK.projectedLongest.meters - 9_744) < 10)
    }

    /// RC-11 step 5: half 24 weeks (likely 28), marathon long-run path 34 (likely 39), and the saved marathon
    /// about week 40 (likely 46) once HL-26 and RC-3's gate are met around week 22.
    @Test func ownerExampleEarliestDates() {
        let runner = input(ownerIntake(event(.marathon, weeks: 13)))
        let half = FeasibilityEngine.evaluate(GoalChoice(flavor: .event, distance: .halfMarathon), input: runner, firstTimer: true, weeksAvailable: nil, now: now, calendar: calendar)
        #expect(half.earliestWeeks == 24)
        #expect(half.likelyWeeks == 28)
        let path = FeasibilityEngine.evaluate(GoalChoice(flavor: .event, distance: .marathon), input: runner, firstTimer: false, weeksAvailable: nil, now: now, calendar: calendar)
        #expect(path.earliestWeeks == 34)
        #expect(path.likelyWeeks == 39)
        let saved = FeasibilityEngine.evaluate(GoalChoice(flavor: .event, distance: .marathon), input: runner, firstTimer: true, weeksAvailable: nil, now: now, calendar: calendar)
        #expect(saved.gateWeeks == 22)
        #expect(saved.earliestWeeks == 40)
        #expect(saved.likelyWeeks == 46)
    }

    /// RC-11 steps 2, 6 and 7: HL-26 refuses the marathon, saves it for about week 40 and offers the 5K on the
    /// date, the 10K with walk breaks, and the half at its Green date. No insist path.
    @Test func ownerExampleRefusal() throws {
        let check = check(ownerIntake(event(.marathon, weeks: 13)))
        #expect(check.verdict == .refused)
        #expect(check.refusal == .firstMarathon)
        #expect(!check.canInsist)
        #expect(check.savedGoal?.distance == .marathon)
        #expect(check.savedGoalEarliest == calendar.startOfDay(for: weeksLater(40)))
        #expect(check.message.hasPrefix("A first marathon needs a year of running and a half marathon (or a 16 km run) first. You're at 8 months."))
        #expect(check.message.hasSuffix("the earliest I can plan it is \(CoachFormat.date(weeksLater(40), calendar: calendar))."))
        let offers = check.alternatives.map { ($0.goal.distance, $0.status, $0.walkBreaks) }
        try #require(offers.count == 3)
        #expect(offers[0] == (.fiveK, .green, false))
        #expect(offers[1] == (.tenK, .amber, true))
        #expect(offers[2] == (.halfMarathon, .green, false))
        #expect(check.alternatives[2].earliestDate == calendar.startOfDay(for: weeksLater(28)))
    }

    /// RC-11 step 7: a runner who passed HL-26 with the same 5 km longest run is Red at 13 weeks and gets the
    /// insist path, with RC-8d's message.
    @Test func redGoalOffersTheInsistPath() {
        var intake = ownerIntake(event(.marathon, weeks: 13))
        intake.monthsRunning = nil
        intake.history = .oneToTwoYears
        intake.finishedHalf = true
        let check = check(intake)
        #expect(check.verdict == .red)
        #expect(check.canInsist)
        #expect(check.timeGoalDropped == false)
        #expect(check.message.hasPrefix("You can run 4.5 km now. A marathon needs long runs of about 30 km. I add at most 10% to your longest run, one step at a time with easier weeks between, so that takes about "))
        #expect(check.message.contains("weeks at Steady. You have 13 weeks."))
        #expect(check.message.hasSuffix("About 3 in 10 runners get injured building for a 5-10K, and 4-5 in 10 for a half or marathon."))
        #expect(check.alternatives.first?.goal.distance == .fiveK)
        #expect(!check.alternatives.contains { $0.goal.distance == .halfMarathon && $0.walkBreaks })
    }

    // MARK: RC-1 refusals

    @Test func pastRaceDateIsRefused() {
        let goal = GoalChoice(flavor: .event, distance: .tenK, eventDate: CoachFixtures.day(-1))
        let check = check(CoachFixtures.regularIntake(goal))
        #expect(check.verdict == .refused)
        #expect(check.refusal == .pastDate)
        #expect(!check.canInsist)
    }

    @Test func raceDayTodayIsCheckedNotRefused() {
        let goal = GoalChoice(flavor: .event, distance: .tenK, eventDate: CoachFixtures.day(0, hour: 9))
        let check = check(CoachFixtures.regularIntake(goal))
        #expect(check.refusal == nil)
        #expect(check.verdict == .red)
    }

    @Test func oneRunDayRefusesEventsAndSpeedWork() {
        var intake = CoachFixtures.regularIntake(event(.tenK, weeks: 20))
        intake.runDays = [.sunday]
        let check = check(intake)
        #expect(check.refusal == .fewRunDays)
        #expect(check.savedGoal?.distance == .tenK)
        #expect(check.message.hasPrefix("With one run day a week I can't build safely toward a 10K."))
        #expect(check.alternatives.first?.goal.flavor == .buildDistance)
    }

    @Test func pausedSevereInjuryRefuses() {
        let intake = CoachFixtures.regularIntake(event(.tenK, weeks: 20))
        let assessment = RunnerAssessor.assess(intake, now: now, calendar: calendar)
        let paces = PaceCalculator.initialPaces(intake, now: now, calendar: calendar)
        let report = InjuryReport(reportedAt: now, origin: .planScreen, level: .severe, baseline: InjuryBaseline(volumeUnit: .distance, weekVolume: 16_000, longRun: Load(meters: 10_000, seconds: 3_600)))
        let check = GoalChecker.check(intake.goal, intake: intake, assessment: assessment, paces: paces, level: .steady, injuries: [report], now: now, calendar: calendar)
        #expect(check.refusal == .severeInjury)
        #expect(check.message == "Let's get you back running first. Your goal is saved, and I'll check it again when you're ready.")
    }

    /// RC-1: a half inside the early window is refused and the 10K on the same date is offered.
    @Test func earlyWindowRefusesAHalf() {
        var intake = ownerIntake(event(.halfMarathon, weeks: 8))
        intake.monthsRunning = 1
        intake.history = .underThreeMonths
        intake.lastFourWeeks = RecentRunning(runsPerWeek: 3, weeklyLow: .distance(meters: 9_000), longest: .distance(meters: 4_000))
        let check = check(intake)
        #expect(check.refusal == .earlyWindow)
        #expect(check.message.hasPrefix("In your first 12 weeks and 200 km of regular running, I keep events to 10K or shorter, because that's when most new-runner injuries happen. Your window ends around "))
        #expect(check.message.hasSuffix("Shall we aim for the 10K?"))
        #expect(check.alternatives.first?.goal.distance == .tenK)
        #expect(check.alternatives.first?.goal.eventDate == weeksLater(8))
    }

    // MARK: RC-3 and RC-8

    /// A first 10K needs 8 weeks once the gate is met; a race in 6 weeks is Red with the gate's message.
    @Test func gateLimitedFirstTenK() {
        let check = check(CoachFixtures.regularIntake(event(.tenK, weeks: 6)))
        #expect(check.verdict == .red)
        #expect(check.message.hasPrefix("A first 10K needs 8 weeks of training once you run 30 minutes non-stop 3 times a week, so the earliest I can plan it is "))
    }

    /// RC-8a: a Green event names the target, the date and the buffer, with "weeks" spelled for the count.
    @Test func greenEventMessage() {
        let check = check(CoachFixtures.regularIntake(event(.tenK, weeks: 20)))
        #expect(check.verdict == .green)
        #expect(check.message.hasPrefix("This fits. Your long runs reach 10 km by "))
        #expect(check.message.hasSuffix(", with 2 weeks spare for busy or sick weeks."))
    }

    /// The coordinator's week-range fix: equal ends read "about 2 weeks", never "about 2-2 weeks".
    @Test func weekRangeWithEqualEnds() {
        #expect(CoachFormat.weekRange(2, 2) == "about 2 weeks")
        #expect(CoachFormat.weekRange(1, 1) == "about 1 week")
        #expect(CoachFormat.weekRange(15, 17) == "about 15-17 weeks")
        // A runner already past the 5K rung's targets is ready after calibration: earliest 2, likely 2.
        let check = check(CoachFixtures.regularIntake(GoalChoice(flavor: .buildDistance, distance: .fiveK)))
        #expect(check.feasibility?.earliestWeeks == 2)
        #expect(check.feasibility?.likelyWeeks == 2)
        #expect(check.message == "This fits. At Steady you could be ready in about 2 weeks.")
    }

    /// RC-8e: the long run doesn't fit the longest free slot, and the 10K does.
    @Test func longRunTimeDoesNotFit() {
        var intake = CoachFixtures.regularIntake(event(.halfMarathon, weeks: 30))
        intake.weekdayMaxSeconds = 45 * 60
        intake.weekendMaxSeconds = 70 * 60
        let check = check(intake)
        #expect(check.feasibility?.longRunTimeLimited == true)
        #expect(check.message.contains("Your longest free slot is 70 min. A half marathon needs a long run of about 101 min. Can you free up 101 min on Sunday? If not, a 10K fits your week."))
        #expect(check.verdict != .green)
    }

    /// PZ-6c: at a 7:30/km long-run pace a half takes about 2:54, after a 2:30 cut-off.
    @Test func cutoffAtRisk() {
        var intake = CoachFixtures.regularIntake(GoalChoice(flavor: .event, distance: .halfMarathon, eventDate: weeksLater(30), cutoffSeconds: 2.5 * 3_600))
        intake.easyPace = 450
        let check = check(intake)
        #expect(check.cutoffAtRisk)
        #expect(check.plansRunWalk)
        #expect(check.message.contains("after the 2:30 cut-off. I'll plan walk breaks, and a race with a later cut-off would suit you better."))
    }

    /// RC-12: a race more than 52 weeks away starts its plan at most 52 weeks out.
    @Test func raceOverAYearAwayStartsLater() throws {
        let check = check(CoachFixtures.regularIntake(event(.halfMarathon, weeks: 70)))
        let start = try #require(check.planStartsOn)
        let weeksOut = (calendar.dateComponents([.day], from: start, to: weeksLater(70)).day ?? 0) / 7
        #expect(weeksOut <= 52)
        #expect(weeksOut == (check.feasibility?.earliestWeeks ?? 0) + (check.feasibility?.bufferWeeks ?? 0))
    }

    // MARK: RC-6

    func fiveKRunner(_ seconds: Double, goal: GoalChoice) -> CoachIntake {
        var intake = CoachFixtures.regularIntake(goal)
        intake.race = RaceResult(date: CoachFixtures.day(-35), meters: 5_000, seconds: seconds)
        return intake
    }

    /// RC-6's example: a 22:00 5K wanting sub-20 in 12 weeks needs 9.1%; realistic 21:34, stretch 20:41, so
    /// Unlikely with an interim of 20:41, and past the 8% cap: a multi-season goal.
    @Test func subTwentyIsUnlikelyAndMultiSeason() throws {
        let check = check(fiveKRunner(22 * 60, goal: event(.fiveK, weeks: 12, target: 20 * 60)))
        let time = try #require(check.timeGoal)
        #expect(abs(time.improvementNeeded - 0.0909) < 0.0005)
        #expect(abs(time.realisticGain - 0.02) < 1e-9)
        #expect(abs(time.stretchGain - 0.06) < 1e-9)
        #expect(time.verdict == .unlikely)
        #expect(CoachFormat.clock(try #require(time.interimGoal)) == "20:41")
        #expect(time.multiSeason)
        #expect(check.verdict == .amber)
        #expect(check.racePace == nil)
        #expect(check.message.hasPrefix("Sub-20 is 9.1% faster than your current 22:00. In 12 weeks, runners like you usually improve about 2%, and 6% at best. I'll train you toward 20:41 and retest on "))
        #expect(check.message.contains("Keep sub-20 as a stretch goal, or aim for 22:00?"))
        #expect(check.message.contains("That's more than the 8% I'd expect in a year, so sub-20 is a multi-season goal."))
    }

    /// RC-6: for a 28:00 5K one block is Realistic at 27:26 or slower and Stretch from 26:19.
    @Test func twentyEightMinuteFiveK() throws {
        let realistic = check(fiveKRunner(28 * 60, goal: event(.fiveK, weeks: 12, target: 27 * 60 + 30)))
        #expect(realistic.timeGoal?.verdict == .realistic)
        #expect(realistic.verdict == .green)
        #expect(realistic.racePace != nil)
        #expect(realistic.message.contains("Your likely finish is "))
        let stretch = check(fiveKRunner(28 * 60, goal: event(.fiveK, weeks: 12, target: 26 * 60 + 30)))
        #expect(stretch.timeGoal?.verdict == .stretch)
        #expect(stretch.message.hasPrefix("Sub-26:30 is possible with a good block: it needs 5.4%, and 2% is typical."))
        let unlikely = check(fiveKRunner(28 * 60, goal: event(.fiveK, weeks: 12, target: 26 * 60)))
        #expect(unlikely.timeGoal?.verdict == .unlikely)
    }

    @Test func blockCounting() {
        #expect(abs(GoalChecker.blockSum(gain: 0.02, weeks: 12) - 0.02) < 1e-12)
        #expect(abs(GoalChecker.blockSum(gain: 0.02, weeks: 20) - 0.03) < 1e-12)
        #expect(abs(GoalChecker.blockSum(gain: 0.02, weeks: 18) - (0.02 + 0.01 * 2 / 3)) < 1e-12)
        #expect(abs(GoalChecker.blockSum(gain: 0.02, weeks: 14) - (0.02 + 0.01 / 3)) < 1e-12)
        #expect(abs(GoalChecker.blockSum(gain: 0.02, weeks: 8, firstBlock: 1) - 0.01) < 1e-12)
    }

    // MARK: Speed Work

    /// SW's worked example: a 50:00 10K runner wants a strong first half. Readiness lands in week 15 (likely 17)
    /// and the half forecast is 1:53:40 (1:48-1:59).
    @Test func strongFirstHalf() throws {
        var intake = CoachFixtures.regularIntake(GoalChoice(flavor: .speedWork, distance: .halfMarathon, strongFirstTime: true))
        intake.finished = .no
        intake.easyPace = nil
        intake.lastFourWeeks = RecentRunning(runsPerWeek: 3, weeklyLow: .distance(meters: 25_000), longest: .distance(meters: 10_000))
        intake.race = RaceResult(date: CoachFixtures.day(-42), meters: 10_000, seconds: 50 * 60)
        let check = check(intake)
        let forecast = try #require(check.forecast)
        #expect(CoachFormat.clock(forecast.central) == "1:53:40")
        #expect(check.feasibility?.pathWeeks == 15)
        #expect(check.message == "A strong first half needs long runs of about 21 km before speed work pays off. Your longest is 10 km, and I add at most 10% at a time with easier weeks between, so that's about 15-17 weeks at Steady. Then an 8-week speed block ends with your half. From your 50:00 10K, a first half lands around 1:54 (likely 1:48 to 1:59).")
        #expect(check.racePace == forecast.pace)
    }

    /// SW-1a: the sub-20 runner in Speed Work gets the block's Unlikely message and the multi-season line.
    @Test func speedWorkSubTwenty() {
        var intake = fiveKRunner(22 * 60, goal: GoalChoice(flavor: .speedWork, distance: .fiveK, targetSeconds: 20 * 60))
        intake.lastFourWeeks = RecentRunning(runsPerWeek: 3, weeklyLow: .distance(meters: 25_000), longest: .distance(meters: 10_000))
        let check = check(intake)
        #expect(check.timeGoal?.verdict == .unlikely)
        #expect(check.timeGoal?.blocksNeeded == nil)
        #expect(check.message == "Sub-20 is 9.1% faster than your current 22:00. A block usually brings about 2%, up to 6%, so this block aims at 20:41. That's more than the 8% I'd expect in a year, so sub-20 is a multi-season goal. I'll re-check it after every test.")
    }

    // MARK: PZ-4

    /// PZ-4's example, a 25:00 5K from 10 weeks ago: 10K 52:29 (49:52-55:07), first half 2:01:49
    /// (1:55:44-2:07:55), first marathon 4:50:31 at low confidence, ±12%.
    @Test func forecastsFromATwentyFiveMinuteFiveK() throws {
        let paces = TrainingPaces(results: [RaceResult(date: CoachFixtures.day(-70), meters: 5_000, seconds: 25 * 60)])
        let context = ForecastContext(firstTime: true, weeklyMeters: 30_000, age: 35)
        let tenK = try #require(PaceCalculator.forecast(.tenK, paces: paces, context: context, now: now, calendar: calendar))
        #expect(CoachFormat.clock(tenK.central) == "52:29")
        #expect(CoachFormat.clock(tenK.low) == "49:52")
        #expect(CoachFormat.clock(tenK.high) == "55:07")
        let half = try #require(PaceCalculator.forecast(.halfMarathon, paces: paces, context: context, now: now, calendar: calendar))
        #expect(half.k == 1.10)
        #expect(CoachFormat.clock(half.central) == "2:01:49")
        #expect(CoachFormat.clock(half.low) == "1:55:44")
        #expect(CoachFormat.clock(half.high) == "2:07:55")
        let marathon = try #require(PaceCalculator.forecast(.marathon, paces: paces, context: context, now: now, calendar: calendar))
        #expect(marathon.k == 1.15)
        #expect(marathon.confidence == .low)
        #expect(abs(marathon.rangeFraction - 0.12) < 1e-9)
        #expect(abs(marathon.central - (4 * 3_600 + 50 * 60 + 31)) < 1.5)
    }

    /// PZ-2: the slowest result in the forecast set wins, and results over 8 weeks before the anchor don't count.
    @Test func slowestResultInTheSetWins() throws {
        let fast = RaceResult(date: CoachFixtures.day(-7), meters: 5_000, seconds: 22 * 60)
        let slowTenK = RaceResult(date: CoachFixtures.day(-35), meters: 10_000, seconds: 48 * 60)
        let old = RaceResult(date: CoachFixtures.day(-80), meters: 5_000, seconds: 30 * 60)
        let paces = TrainingPaces(results: [old, slowTenK, fast])
        let context = ForecastContext(firstTime: false, weeklyMeters: 40_000, age: 35)
        let forecast = try #require(PaceCalculator.forecast(.tenK, paces: paces, context: context, now: now, calendar: calendar))
        #expect(forecast.anchorID == slowTenK.id)
        #expect(forecast.central == 48 * 60)
    }

    /// A re-run from the logs gives a check without refusing a plannable goal.
    @Test func recheckFromALoggedPlan() {
        let state = CoachFixtures.start(CoachFixtures.regularIntake(event(.halfMarathon, weeks: 30)))
        let simulation = CoachFixtures.follow(state, days: 21)
        let check = GoalChecker.recheck(simulation.state.goal, state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(21, from: simulation.state.startDate), calendar: calendar)
        #expect(check.refusal == nil)
        #expect(check.feasibility != nil)
    }
}
