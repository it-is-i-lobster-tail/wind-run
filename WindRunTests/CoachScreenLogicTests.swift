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

    // MARK: Speed Work names

    @Test func blockWeeksAreNumbered() {
        let building = PlannedWeek(index: 4, start: CoachFixtures.day(28), kind: .loading, phase: .speedBlock, blockWeek: 3, volumeUnit: .time, plannedVolume: 3 * 3_600)
        let lighter = PlannedWeek(index: 5, start: CoachFixtures.day(35), kind: .stepBack, phase: .speedBlock, blockWeek: 4, volumeUnit: .time, plannedVolume: 3 * 3_600)
        let outside = PlannedWeek(index: 1, start: CoachFixtures.day(7), kind: .loading, phase: .base, volumeUnit: .time, plannedVolume: 3 * 3_600)

        #expect(CoachProjection.weekTitle(building, blockLength: 8) == "Block week 3 of 8")
        #expect(CoachProjection.weekTitle(lighter, blockLength: 8) == "Block week 4 of 8, lighter week")
        #expect(CoachProjection.weekTitle(outside, blockLength: 8) == WeekKind.loading.name)
    }

    @Test func testsAndBenchmarksAreNamed() {
        var test = PlannedSession(dayOffset: 2, kind: .test, effort: .race, target: Load(meters: 3_000, seconds: 1_800), appTest: AppTest(goal: .time(seconds: 720), controlled: false))
        #expect(CoachProjection.sessionTitle(test, unit: .kilometers) == "12-minute test")
        test.appTest = AppTest(goal: .distance(meters: 5_000), controlled: true)
        #expect(CoachProjection.sessionTitle(test, unit: .kilometers) == "5 km test")

        let benchmark = PlannedSession(dayOffset: 1, kind: .easy, effort: .easy, target: Load(meters: 5_000, seconds: 1_800), benchmark: true)
        #expect(CoachProjection.sessionTitle(benchmark, unit: .kilometers) == "Benchmark run")
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
