//
//  EventReviewTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Race day and after (EV-9): the result, "Did you race?", recovery by the distance run, the plan's end and
/// "What next?" (RC-12a).
@MainActor
struct EventReviewTests {
    let calendar = CoachFixtures.calendar
    /// Sunday 1 March 2026, the end of plan week 7.
    let raceDay = 55

    func tenK(target: Double? = nil) -> CoachState {
        CoachFixtures.start(CoachFixtures.regularIntake(GoalChoice(flavor: .event, distance: .tenK, targetSeconds: target, eventDate: CoachFixtures.day(raceDay))))
    }

    func date(_ offset: Int) -> String {
        CoachFormat.date(CoachFixtures.day(offset), calendar: calendar)
    }

    func severeReport() -> InjuryReport {
        InjuryReport(
            reportedAt: CoachFixtures.day(raceDay),
            origin: .planScreen,
            level: .severe,
            baseline: InjuryBaseline(volumeUnit: .distance, weekVolume: 16_000, longRun: Load(meters: 10_000, seconds: 3_600))
        )
    }

    // MARK: The race

    /// EV-9: a race-day run of 90% of the distance or more is a finish, and its result becomes the anchor.
    @Test func finishedRaceBecomesTheAnchor() throws {
        let state = tenK()
        let run = LoggedRun(start: CoachFixtures.day(raceDay, hour: 9), movingSeconds: 48 * 60, meters: 10_050)
        let update = EventReviewer.raceLogged(run, state: state, now: run.end.addingTimeInterval(600), calendar: calendar)
        #expect(update.state.eventReview.outcome == .finished)
        #expect(update.state.eventReview.raceRunID == run.id)
        let anchor = try #require(update.state.paces.anchor)
        #expect(anchor.meters == 10_000)
        #expect(anchor.seconds == 2_880)
        #expect(anchor.source == .race)
        #expect(update.state.eventReview.raceResultID == anchor.id)
        #expect(update.notes == [CoachNote(.event, "Congratulations on finishing your 10K! Easy running only until \(date(raceDay + 3)), then we build again. Your result has updated your paces.")])
        #expect(EventReviewer.recoveryDistance(update.state) == .tenK)
        let again = EventReviewer.raceLogged(run, state: update.state, now: run.end.addingTimeInterval(900), calendar: calendar)
        #expect(again.state == update.state)
        #expect(again.notes.isEmpty)
    }

    /// EV-9: under 90% of the distance is a DNF: FB-3's question first, no anchor, recovery by the distance run.
    @Test func shortRaceRunIsADNF() {
        let state = tenK()
        let run = LoggedRun(start: CoachFixtures.day(raceDay, hour: 9), movingSeconds: 30 * 60, meters: 6_000)
        let update = EventReviewer.raceLogged(run, state: state, now: run.end.addingTimeInterval(600), calendar: calendar)
        #expect(update.state.eventReview.outcome == .didNotFinish)
        #expect(update.questions == [.whatHappened(runID: run.id)])
        #expect(update.state.paces == state.paces)
        #expect(update.notes == [CoachNote(.event, "Not every race goes to plan. Easy running only until \(date(raceDay + 3)), then we build again.")])
    }

    /// EV-9: a DNF's recovery uses the row for the distance run; a race not started has none.
    @Test func recoveryRows() {
        var state = tenK()
        state.goal.distance = .marathon
        func row(_ meters: Double) -> RaceDistance? {
            var dnf = state
            dnf.eventReview.outcome = .didNotFinish
            dnf.eventReview.distanceRun = meters
            return EventReviewer.recoveryDistance(dnf)
        }
        #expect(row(8_000) == .tenK)
        #expect(row(12_000) == .halfMarathon)
        #expect(row(31_000) == .marathon)
        #expect(EventReviewer.recoveryDistance(state) == .marathon)
        state.eventReview.outcome = .didNotStart
        #expect(EventReviewer.recoveryDistance(state) == nil)
    }

    // MARK: "Did you race?"

    /// EV-9: asked from the day after race day while no run is matched to the race.
    @Test func didYouRaceIsAskedAfterRaceDay() {
        let state = tenK()
        #expect(!EventReviewer.questions(state, runs: [], now: CoachFixtures.day(raceDay, hour: 20), calendar: calendar).contains(.didYouRace))
        #expect(EventReviewer.questions(state, runs: [], now: CoachFixtures.day(raceDay + 1), calendar: calendar) == [.didYouRace])
        let answered = EventReviewer.answerDidYouRace(.recordedElsewhere(meters: 10_000, seconds: 50 * 60), state: state, runs: [], now: CoachFixtures.day(raceDay + 1), calendar: calendar)
        #expect(EventReviewer.questions(answered.state, runs: [], now: CoachFixtures.day(raceDay + 2), calendar: calendar).isEmpty)
    }

    /// "Yes, recorded elsewhere": a finish with its result, a DNF, or a finish with no numbers.
    @Test func recordedElsewhere() {
        let state = tenK()
        let now = CoachFixtures.day(raceDay + 1)
        let finished = EventReviewer.answerDidYouRace(.recordedElsewhere(meters: 10_000, seconds: 50 * 60), state: state, runs: [], now: now, calendar: calendar)
        #expect(finished.state.eventReview.outcome == .finished)
        #expect(finished.state.eventReview.askedDidYouRace)
        #expect(finished.state.paces.anchor?.official == true)
        #expect(finished.state.paces.anchor?.seconds == Double(50 * 60))

        let short = EventReviewer.answerDidYouRace(.recordedElsewhere(meters: 7_000, seconds: 40 * 60), state: state, runs: [], now: now, calendar: calendar)
        #expect(short.state.eventReview.outcome == .didNotFinish)
        #expect(short.questions.isEmpty)

        let bare = EventReviewer.answerDidYouRace(.recordedElsewhere(meters: nil, seconds: nil), state: state, runs: [], now: now, calendar: calendar)
        #expect(bare.state.eventReview.outcome == .finished)
        #expect(bare.state.paces == state.paces)
        #expect(bare.notes == [CoachNote(.event, "Congratulations on finishing your 10K! Easy running only until \(date(raceDay + 3)), then we build again.")])
    }

    /// "Didn't start": no recovery, the plan stops with the reason and asks what next; a Severe report keeps the
    /// goal (RC-1).
    @Test func didNotStart() {
        let state = tenK()
        let now = CoachFixtures.day(raceDay + 1)
        let update = EventReviewer.answerDidYouRace(.didNotStart, state: state, runs: [], now: now, calendar: calendar)
        #expect(update.state.status == .stopped(reason: .didNotStart, on: now))
        #expect(update.questions == [.nextGoal])
        #expect(EventReviewer.recoveryDistance(update.state) == nil)
        #expect(EventReviewer.questions(update.state, runs: [], now: CoachFixtures.day(raceDay + 2), calendar: calendar) == [.nextGoal])
        #expect(update.state.savedGoal == nil)

        var injured = state
        injured.injuries = [severeReport()]
        #expect(EventReviewer.answerDidYouRace(.didNotStart, state: injured, runs: [], now: now, calendar: calendar).state.savedGoal == state.goal)
    }

    /// "Race moved" (RC-10): the check runs for the new date and the phases move; a past date changes nothing.
    @Test func raceMoved() throws {
        let state = tenK()
        let now = CoachFixtures.day(raceDay + 1)
        let past = EventReviewer.answerDidYouRace(.raceMoved(to: CoachFixtures.day(raceDay - 7)), state: state, runs: [], now: now, calendar: calendar)
        #expect(past.state.event == state.event)
        #expect(past.notes == [CoachNote(.event, "That race date has already passed. Pick a date from today on, and I'll check your goal again.")])

        let later = EventReviewer.answerDidYouRace(.raceMoved(to: CoachFixtures.day(raceDay + 21)), state: state, runs: [], now: now, calendar: calendar)
        let event = try #require(later.state.event)
        #expect(event.raceDate == calendar.startOfDay(for: CoachFixtures.day(raceDay + 21)))
        #expect(event.taperStart == calendar.startOfDay(for: CoachFixtures.day(raceDay + 15)))
        #expect(later.state.goal.eventDate == CoachFixtures.day(raceDay + 21))
        #expect(later.notes.first?.text.hasPrefix("Your race is now on \(date(raceDay + 21)). ") == true)
        #expect(EventReviewer.questions(later.state, runs: [], now: CoachFixtures.day(raceDay + 2), calendar: calendar).isEmpty)
    }

    // MARK: After the race

    /// EV-9: the plan is complete once the recovery is over: a week after a 10K, four after a marathon.
    @Test func planCompletesWhenRecoveryEnds() {
        var state = tenK()
        let week = state.weekIndex(on: CoachFixtures.day(raceDay), calendar: calendar)
        func ended(_ index: Int, _ state: CoachState) -> CoachUpdate {
            EventReviewer.weekEnded(index, state: state, runs: [], now: CoachFixtures.day(7 * index + 6, hour: 23, from: state.startDate), calendar: calendar)
        }
        #expect(ended(week - 1, state).state.status == .active)
        #expect(ended(week, state).state.status == .active)
        let done = ended(week + 1, state)
        #expect(done.state.status == .complete(on: CoachFixtures.day(7 * (week + 1) + 6, hour: 23, from: state.startDate)))
        #expect(done.questions == [.nextGoal])
        #expect(ended(week + 1, done.state).questions.isEmpty)

        state.goal.distance = .marathon
        #expect(ended(week + 3, state).state.status == .active)
        #expect(ended(week + 4, state).state.status.isActive == false)
    }

    /// Following the plan through race day records the race from its run and completes the plan after recovery.
    @Test func followingThePlanThroughRaceDay() {
        let state = tenK()
        let days = CoachFixtures.calendar.dateComponents([.day], from: state.startDate, to: CoachFixtures.day(raceDay + 9)).day ?? 0
        let simulation = CoachFixtures.follow(state, days: days)
        #expect(simulation.state.eventReview.outcome == .finished)
        #expect(simulation.state.paces.anchor?.source == .race)
        #expect(simulation.state.status.isActive == false)
    }

    // MARK: The buffer

    /// EV-1: a build week under half done, or planned as a pause, uses a buffer week. The count comes from the
    /// week records, so a second review of the same week never counts it twice, and it stops at the buffer.
    @Test func lostBuildWeeksUseTheBuffer() throws {
        var state = CoachFixtures.start(CoachFixtures.regularIntake(GoalChoice(flavor: .event, distance: .halfMarathon, eventDate: CoachFixtures.day(139))))
        state.event?.bufferWeeks = 4
        let simulation = CoachFixtures.follow(state, days: 35, skip: { _, offset in (14 ..< 28).contains(offset) })
        let event = try #require(simulation.state.event)
        #expect(event.bufferUsed == 2)
        let evening = CoachFixtures.day(34, hour: 21)
        let again = EventReviewer.weekEnded(4, state: simulation.state, runs: simulation.runs, now: evening, calendar: calendar)
        #expect(again.state.event?.bufferUsed == 2)

        var paused = simulation.state
        paused.weeks[0].plan.kind = .paused
        #expect(EventReviewer.weekEnded(4, state: paused, runs: simulation.runs, now: evening, calendar: calendar).state.event?.bufferUsed == 3)
        paused.event?.bufferWeeks = 1
        #expect(EventReviewer.weekEnded(4, state: paused, runs: simulation.runs, now: evening, calendar: calendar).state.event?.bufferUsed == 1)
        #expect(EventReviewer.lostBuildWeeks(paused, through: 1, runs: simulation.runs, calendar: calendar) == 1)
    }

    // MARK: "What next?"

    func finished(_ state: CoachState) -> CoachState {
        var state = EventReviewer.answerDidYouRace(.recordedElsewhere(meters: 10_000, seconds: 50 * 60), state: state, runs: [], now: CoachFixtures.day(raceDay + 1), calendar: calendar).state
        state.status = .complete(on: CoachFixtures.day(raceDay + 7))
        return state
    }

    /// "Keep my fitness": Build Distance maintenance at the race distance, or Speed Work maintenance after a time
    /// goal. The event ends and the plan carries on.
    @Test func maintainAfterTheRace() {
        let now = CoachFixtures.day(raceDay + 8)
        let update = EventReviewer.answerNextGoal(.maintain, state: finished(tenK()), runs: [], now: now, calendar: calendar)
        #expect(update.state.goal == GoalChoice(flavor: .buildDistance, distance: .tenK, maintain: true))
        #expect(update.state.event == nil)
        #expect(update.state.status == .active)
        #expect(update.notes == [CoachNote(.plan, "Done: no more distance added. Your weeks stay about where they are, with lighter weeks as before.")])
        #expect(EventReviewer.questions(update.state, runs: [], now: now, calendar: calendar).isEmpty)

        let timed = EventReviewer.answerNextGoal(.maintain, state: finished(tenK(target: 55 * 60)), runs: [], now: now, calendar: calendar)
        #expect(timed.state.goal == GoalChoice(flavor: .speedWork, distance: .tenK, maintain: true))
        #expect(timed.notes == [CoachNote(.plan, "Done: one quality session a week at your current level, and your weekly distance stays where it is.")])
    }

    /// "Another event": the check runs again and the plan hands off to it, with the new race's phases (RC-12a).
    @Test func anotherEventHandsOffInThePlan() throws {
        let state = finished(tenK())
        let now = CoachFixtures.day(raceDay + 8)
        let next = GoalChoice(flavor: .event, distance: .tenK, eventDate: CoachFixtures.day(raceDay + 7 * 12))
        let update = EventReviewer.answerNextGoal(.newGoal(next), state: state, runs: [], now: now, calendar: calendar)
        #expect(update.state.goal == next)
        let event = try #require(update.state.event)
        #expect(event.raceDate == calendar.startOfDay(for: CoachFixtures.day(raceDay + 7 * 12)))
        #expect(update.state.status == .active)
        #expect(update.state.eventReview.outcome == nil)
        #expect(update.state.paces.anchor == state.paces.anchor)
        let check = GoalChecker.recheck(next, state: state, runs: [], now: now, calendar: calendar)
        #expect(update.notes == [CoachNote(.plan, check.message)])
    }

    /// "Next rung" and "Speed Work": the check runs for the next goal and the plan hands off to it; past the
    /// marathon, the fitness is kept.
    @Test func nextRungAndSpeedWorkAnswers() {
        let state = finished(tenK())
        let now = CoachFixtures.day(raceDay + 8)
        let rung = EventReviewer.answerNextGoal(.nextRung, state: state, runs: [], now: now, calendar: calendar)
        let half = GoalChoice(flavor: .buildDistance, distance: .halfMarathon)
        #expect(rung.state.goal == half)
        #expect(rung.state.event == nil)
        #expect(rung.state.status == .active)
        #expect(rung.notes == [CoachNote(.plan, GoalChecker.recheck(half, state: state, runs: [], now: now, calendar: calendar).message)])

        let speed = EventReviewer.answerNextGoal(.speedWork, state: state, runs: [], now: now, calendar: calendar)
        #expect(speed.state.goal == GoalChoice(flavor: .speedWork, distance: .tenK))
        #expect(speed.state.event == nil)
        #expect(speed.state.status == .active)

        var marathon = state
        marathon.goal.distance = .marathon
        let top = EventReviewer.answerNextGoal(.nextRung, state: marathon, runs: [], now: now, calendar: calendar)
        #expect(top.state.goal == GoalChoice(flavor: .buildDistance, distance: .marathon, maintain: true))
        #expect(top.notes == [CoachNote(.plan, "The marathon is the top rung. To run one, pick it as an event, and until then I'll keep your fitness where it is.")])
    }

    /// A refused next goal is kept with its earliest date, and the current fitness is kept meanwhile (RC-1).
    @Test func refusedNextGoalIsSaved() {
        let state = finished(tenK())
        let now = CoachFixtures.day(raceDay + 8)
        var injured = state
        injured.injuries = [severeReport()]
        let next = GoalChoice(flavor: .event, distance: .tenK, eventDate: CoachFixtures.day(raceDay + 7 * 12))
        let update = EventReviewer.answerNextGoal(.newGoal(next), state: injured, runs: [], now: now, calendar: calendar)
        #expect(update.state.savedGoal == next)
        #expect(update.state.goal.maintain)
        #expect(update.state.event == nil)
        #expect(update.notes == [CoachNote(.plan, "Let's get you back running first. Your goal is saved, and I'll check it again when you're ready.")])
    }

    /// BD-1g's next rung: a run-walk rung's non-stop version, else the next distance; the marathon is the top.
    @Test func nextRungs() {
        #expect(EventReviewer.nextRung(after: GoalChoice(flavor: .buildDistance, distance: .fiveK, runWalk: true)) == GoalChoice(flavor: .buildDistance, distance: .fiveK))
        #expect(EventReviewer.nextRung(after: GoalChoice(flavor: .buildDistance, distance: .tenK)) == GoalChoice(flavor: .buildDistance, distance: .halfMarathon))
        #expect(EventReviewer.nextRung(after: GoalChoice(flavor: .buildDistance, distance: .marathon)) == nil)
    }
}
