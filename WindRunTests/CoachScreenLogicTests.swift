//
//  CoachScreenLogicTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The logic behind the coach screens: the inbox, recovery outlines and plan actions.
@MainActor
struct CoachScreenLogicTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private func startPlan() -> CoachPlan {
        let intake = CoachFixtures.regularIntake()
        let service = CoachService(context: container.mainContext, calendar: CoachFixtures.calendar, unit: .kilometers)
        return service.startPlan(intake: intake, goal: intake.goal, level: .steady, insisted: false, now: CoachFixtures.day(0)).0
    }

    // MARK: Inbox

    @Test func theInboxKeepsQuestionsACallAskedAheadOfTheRest() {
        let inbox = CoachInbox()
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let asked = CoachQuestion.weeklyCheckIn(weekIndex: 0)
        let pending = CoachQuestion.missedRuns

        inbox.receive(CoachUpdate(state: state, notes: [CoachNote(.plan, "Hello")], questions: [pending, asked]), after: [asked])

        #expect(inbox.questions == [asked, pending])
        #expect(inbox.notes.map(\.text) == ["Hello"])
    }

    @Test func anUpdateWithoutNotesKeepsTheLastOnes() {
        let inbox = CoachInbox()
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        inbox.receive(CoachUpdate(state: state, notes: [CoachNote(.plan, "Hello")]))
        inbox.receive(CoachUpdate(state: state))

        #expect(inbox.notes.map(\.text) == ["Hello"])
        inbox.dismissNotes()
        #expect(inbox.notes.isEmpty)
    }

    // MARK: Recovery outline

    @Test func theDefaultRecoveryOutlineMatchesTheStandardPlan() {
        let standard = RecoveryPlanSettings.standard
        let weeks = RecoveryOutline.weeks(rest: standard.restWeeks, reduced: standard.reducedWeeks, share: standard.reducedShare, step: standard.rampStep)

        #expect(weeks == [
            "Week 1: no running",
            "Week 2: 50%",
            "Week 3: 50%",
            "Week 4: 75%",
            "Week 5: back to your usual week",
        ])
    }

    @Test func noRampGoesStraightBackToTheUsualWeek() {
        let weeks = RecoveryOutline.weeks(rest: 0, reduced: 1, share: 0.3, step: nil)
        #expect(weeks == ["Week 1: 30%", "Week 2: back to your usual week"])
    }

    // MARK: Severe return

    @Test func aShortPauseReturnsAtHalfTheUsualWeek() {
        let now = CoachFixtures.day(20)
        var report = Self.severeReport(on: CoachFixtures.day(0))
        report.lastRunBeforePause = CoachFixtures.day(0)

        let settings = ReturnSettings.suggested(for: report, now: now, calendar: CoachFixtures.calendar)

        #expect(settings.weeks == 2)
        #expect(settings.share == 0.5)
        #expect(settings.form == .jogging)
    }

    @Test func aLongPauseReturnsAtLessWithJogWalkForNewerRunners() {
        let now = CoachFixtures.day(40)
        var report = Self.severeReport(on: CoachFixtures.day(0), ranThirtyMinutes: false)
        report.lastRunBeforePause = CoachFixtures.day(0)

        let settings = ReturnSettings.suggested(for: report, now: now, calendar: CoachFixtures.calendar)

        #expect(settings.share == 0.3)
        #expect(settings.form == .jogWalk)
    }

    private static func severeReport(on date: Date, ranThirtyMinutes: Bool = true) -> InjuryReport {
        InjuryReport(
            reportedAt: date,
            origin: .planScreen,
            level: .severe,
            baseline: InjuryBaseline(volumeUnit: .time, weekVolume: 3 * 3_600, longRun: Load(meters: 12_000, seconds: 75 * 60), ranThirtyMinutesNonStop: ranThirtyMinutes)
        )
    }

    // MARK: Actions

    @Test func stoppingThePlanStopsTheStoredPlan() {
        let plan = startPlan()
        let actions = CoachActions(context: container.mainContext, plan: plan, inbox: CoachInbox())

        actions.perform { state, _, now, _ in CoachEngine.stopPlan(state: state, now: now) }

        #expect(plan.status == .stopped)
        #expect(CoachService(context: container.mainContext).currentPlan() == nil)
    }

    @Test func aLifeEventIsKeptInTheState() throws {
        let plan = startPlan()
        let actions = CoachActions(context: container.mainContext, plan: plan, inbox: CoachInbox())
        let event = LifeEvent(kind: .busy, start: .now, length: .oneWeek)

        actions.perform { state, runs, now, calendar in
            CoachEngine.addLifeEvent(event, state: state, runs: runs, now: now, calendar: calendar)
        }

        let state = try #require(actions.state())
        #expect(state.lifeEvents.map(\.id) == [event.id])
    }

    @Test func theRunWithACoachIDIsFound() throws {
        let plan = startPlan()
        let actions = CoachActions(context: container.mainContext, plan: plan, inbox: CoachInbox())
        let run = Run(kind: .free, startDate: CoachFixtures.day(1))
        container.mainContext.insert(run)

        #expect(actions.run(withID: run.runID) === run)
        #expect(actions.run(withID: UUID()) == nil)
    }
}
