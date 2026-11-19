//
//  BuildServiceTests.swift
//  WindRunTests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The stored plan: why one can't be shown, the copy of its weeks and runs the screens show and runs link to, what
/// the Run screen offers today, and saving only when something changed.
@MainActor
struct BuildServiceTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)

    static var calendar: Calendar { BuildPlannerTests.calendar }

    static func day(_ offset: Int) -> Date { BuildPlannerTests.day(offset) }

    private var context: ModelContext { container.mainContext }

    private var service: BuildService { BuildService(context: context, calendar: Self.calendar) }

    /// A plan whose state is `json`, saved by rules `rulesVersion`.
    private func storedPlan(_ json: String?, rulesVersion: String) -> CoachPlan {
        let plan = CoachPlan(flavor: BuildService.flavor)
        context.insert(plan)
        if let json {
            plan.saveState(Data(json.utf8), rulesVersion: rulesVersion, at: Self.day(0))
        }
        return plan
    }

    /// The 50K plan started on Monday 2 November.
    private func startedPlan() throws -> (plan: CoachPlan, state: BuildPlanState) {
        let plan = service.start(BuildPlannerTests.fiftyK(), now: Self.day(5))
        return (plan, try #require(service.state(of: plan)))
    }

    // MARK: Rules versions

    @Test func rulesVersionsAreBuildAndANumber() {
        #expect(BuildService.rulesVersion == "build-\(BuildPlanState.currentVersion)")
        #expect(BuildService.rulesNumber("build-12") == 12)
        #expect(BuildService.rulesNumber(BuildService.rulesVersion) == BuildPlanState.currentVersion)
        #expect(BuildService.rulesNumber("plan-3") == nil)
        #expect(BuildService.rulesNumber("build-x") == nil)
        #expect(BuildService.rulesNumber("") == nil)
    }

    // MARK: Problems

    @Test func aPlanWithNoStateYetIsLoading() {
        let plan = storedPlan(nil, rulesVersion: "")
        #expect(service.problem(with: plan) == .loading)
        #expect(service.state(of: plan) == nil)
    }

    /// Rules from a newer Wind Run, read from the version: the state isn't decoded as this one's.
    @Test func newerRulesAreNewer() {
        let plan = storedPlan(#"{"version":1}"#, rulesVersion: "build-99")
        #expect(service.state(of: plan) == nil)
        #expect(service.problem(with: plan) == .newer)
    }

    @Test func aNewerStateIsNewer() {
        let plan = storedPlan(#"{"version":99}"#, rulesVersion: "build-1")
        #expect(service.problem(with: plan) == .newer)
    }

    @Test func anUnreadableStateCanBeRetired() {
        let plan = storedPlan("not a plan", rulesVersion: "build-1")
        #expect(service.problem(with: plan) == .unreadable)
        #expect(plan.status == .active)
        service.retireUnreadable(plan)
        #expect(plan.status == .stopped)
    }

    /// Another coach's rules are never read as Build Distance's, whatever version the state says.
    @Test func anotherCoachsStateIsUnreadable() {
        let plan = storedPlan(#"{"version":99}"#, rulesVersion: "plan-3")
        #expect(service.problem(with: plan) == .unreadable)
    }

    @Test func aNewerPlanIsntRetired() {
        let plan = storedPlan(#"{"version":99}"#, rulesVersion: "build-1")
        service.retireUnreadable(plan)
        #expect(plan.status == .active)
    }

    // MARK: Starting and saving

    @Test func aStartedPlanCanBeShown() throws {
        let (plan, state) = try startedPlan()
        #expect(service.problem(with: plan) == nil)
        #expect(plan.rulesVersion == BuildService.rulesVersion)
        #expect(plan.flavor == BuildService.flavor)
        #expect(plan.status == .active)
        #expect(plan.startDate == state.planCalendar.firstStart)
        #expect(plan.eventDate == state.goalDate)
        #expect(plan.updatedDate == Self.day(5))
        #expect(service.currentPlan()?.persistentModelID == plan.persistentModelID)
    }

    @Test func startingAnotherPlanStopsTheFirst() throws {
        let (first, _) = try startedPlan()
        let second = service.start(BuildPlannerTests.fiftyK(), now: Self.day(6))
        #expect(first.status == .stopped)
        #expect(second.status == .active)
        #expect(service.currentPlan()?.persistentModelID == second.persistentModelID)
    }

    /// Nothing changed, so nothing is saved: the plan isn't sent to iCloud again.
    @Test func aCallThatChangesNothingDoesntSave() throws {
        let (plan, state) = try startedPlan()
        let returned = service.perform(on: plan, now: Self.day(6)) { state, _, _, _ in state }
        #expect(returned == state)
        #expect(plan.updatedDate == Self.day(5))
    }

    @Test func aRefreshThatChangesThePlanSavesIt() throws {
        let (plan, _) = try startedPlan()
        // Thursday with nothing run: Tuesday's and Wednesday's runs are missed.
        let refreshed = try #require(service.refresh(plan, now: Self.day(8)))
        #expect(plan.updatedDate == Self.day(8))
        #expect(service.state(of: plan) == refreshed)
        let week = try #require(plan.storedWeek(1))
        #expect(week.workouts.filter(\.isMissed).count == 2)
    }

    // MARK: The copy of the weeks

    @Test func weeksAreStoredByTheirNumber() throws {
        let (plan, state) = try startedPlan()
        #expect(BuildProjection.order(ofWeek: 1) == 0)
        #expect(plan.weeks.count == state.weeks.count)
        for planned in state.weeks {
            let stored = try #require(plan.storedWeek(planned.number))
            #expect(stored.order == planned.number - 1)
            #expect(stored.kind == planned.kind.rawValue)
            #expect(stored.title == planned.kind.name)
            #expect(stored.plannedMeters == planned.target.meters)
            #expect(stored.outcome == nil)
            #expect(stored.workouts.compactMap(\.sessionID) == planned.sessions.filter(\.isToDo).map(\.id))
            #expect(stored.workouts.allSatisfy { $0.status == "planned" && !$0.isDone && !$0.isMissed })
        }
    }

    @Test func workoutsKeepTheSessionStatus() throws {
        let (plan, stored) = try startedPlan()
        var state = stored
        let sessions = try #require(state.week(1)).sessions
        state.weeks[0].sessions[0].status = .done(runID: UUID())
        state.weeks[0].sessions[1].status = .missed
        BuildProjection.apply(state, to: plan, in: context, calendar: Self.calendar)
        let week = try #require(plan.storedWeek(1))
        let done = try #require(week.workout(withSessionID: sessions[0].id))
        #expect(done.status == "done")
        #expect(done.isDone)
        #expect(!done.isMissed)
        let missed = try #require(week.workout(withSessionID: sessions[1].id))
        #expect(missed.status == "missed")
        #expect(missed.isMissed)
        #expect(!missed.isDone)
        let planned = try #require(week.workout(withSessionID: sessions[2].id))
        #expect(planned.status == "planned")
        #expect(!planned.isDone)
        #expect(!planned.isMissed)
    }

    @Test func aClosedWeekStoresHowItWent() throws {
        let (plan, stored) = try startedPlan()
        var state = stored
        state.weeks[0].closed = true
        state.weeks[0].done = state.weeks[0].target
        BuildProjection.apply(state, to: plan, in: context, calendar: Self.calendar)
        #expect(plan.storedWeek(1)?.outcome == "done")
        state.weeks[0].done = .zero
        BuildProjection.apply(state, to: plan, in: context, calendar: Self.calendar)
        #expect(plan.storedWeek(1)?.outcome == "short")
    }

    @Test func thePlansStatusFollowsTheState() throws {
        let (plan, stored) = try startedPlan()
        let paused = BuildEngine.reportInjury(level: .severe, area: nil, runID: nil, state: stored, runs: [], now: Self.day(5), calendar: Self.calendar)
        BuildProjection.apply(paused, to: plan, in: context, calendar: Self.calendar)
        #expect(plan.status == .paused)
        #expect(plan.isActive)
        var complete = stored
        complete.status = .complete(on: Self.day(6))
        BuildProjection.apply(complete, to: plan, in: context, calendar: Self.calendar)
        #expect(plan.status == .complete)
        BuildProjection.apply(BuildEngine.stop(stored, now: Self.day(6)), to: plan, in: context, calendar: Self.calendar)
        #expect(plan.status == .stopped)
        #expect(!plan.isActive)
    }

    /// A week or run the plan no longer has goes, unless a run is done in it, so a linked run keeps its workout.
    @Test func whatThePlanDroppedGoesUnlessItsDone() throws {
        let (plan, stored) = try startedPlan()
        var state = stored
        let sessions = try #require(state.week(1)).sessions
        state.weeks[0].sessions[0].status = .done(runID: UUID())
        BuildProjection.apply(state, to: plan, in: context, calendar: Self.calendar)
        state.weeks[0].sessions.remove(at: 1)
        BuildProjection.apply(state, to: plan, in: context, calendar: Self.calendar)
        #expect(plan.storedWeek(1)?.workout(withSessionID: sessions[1].id) == nil)
        state.weeks = []
        BuildProjection.apply(state, to: plan, in: context, calendar: Self.calendar)
        let kept = try #require(plan.storedWeek(1))
        #expect(kept.workout(withSessionID: sessions[0].id)?.isDone == true)
        #expect(plan.weeks.count == 1)
    }

    // MARK: Today

    @Test func aPausedPlanSaysSo() throws {
        let (plan, state) = try startedPlan()
        let paused = BuildEngine.reportInjury(level: .severe, area: nil, runID: nil, state: state, runs: [], now: Self.day(5), calendar: Self.calendar)
        #expect(CoachToday.of(plan, build: paused, now: Self.day(5), calendar: Self.calendar) == .paused)
    }

    @Test func aPlanThatsOverHasNothingToday() throws {
        let (plan, state) = try startedPlan()
        #expect(CoachToday.of(plan, build: BuildEngine.stop(state, now: Self.day(6)), now: Self.day(6), calendar: Self.calendar) == nil)
    }

    @Test func aPlanStartingNextWeekSaysWhen() throws {
        let settings = BuildSettings(currentWeeklyMeters: 30_000, goal: BuildGoal(event: .marathon, date: Self.day(141)), runDays: [.tuesday, .thursday, .saturday])
        let plan = service.start(settings, now: BuildPlannerTests.now)
        let state = try #require(service.state(of: plan))
        #expect(state.planCalendar.firstStart == Self.day(2))
        #expect(CoachToday.of(plan, build: state, now: BuildPlannerTests.now, calendar: Self.calendar) == .startsLater(on: Self.day(2), next: nil))
    }

    @Test func aDayWithNoRunIsRest() throws {
        let (plan, state) = try startedPlan()
        let tuesday = try #require(state.week(1)?.sessions.first)
        let today = CoachToday.of(plan, build: state, now: Self.day(5).addingTimeInterval(10 * 3_600), calendar: Self.calendar)
        guard case .rest(let next)? = today else {
            Issue.record("Expected a rest day, got \(String(describing: today))")
            return
        }
        #expect(next?.sessionID == tuesday.id)
    }

    @Test func aRunDayHasItsRun() throws {
        let (plan, state) = try startedPlan()
        let tuesday = try #require(state.week(1)?.sessions.first)
        let today = CoachToday.of(plan, build: state, now: tuesday.date.addingTimeInterval(8 * 3_600), calendar: Self.calendar)
        guard case .workout(let workout)? = today else {
            Issue.record("Expected today's run, got \(String(describing: today))")
            return
        }
        #expect(workout.sessionID == tuesday.id)
    }

    @Test func aRunDayRunIsDone() throws {
        let (plan, stored) = try startedPlan()
        let tuesday = try #require(stored.week(1)?.sessions.first)
        let wednesday = try #require(stored.week(1)?.sessions.dropFirst().first)
        let run = CoachRun(start: tuesday.date.addingTimeInterval(7 * 3_600), meters: tuesday.target.meters, plannedSessionID: tuesday.id)
        let later = tuesday.date.addingTimeInterval(10 * 3_600)
        let state = BuildEngine.refresh(stored, runs: [run], now: later, calendar: Self.calendar)
        BuildProjection.apply(state, to: plan, in: context, calendar: Self.calendar)
        let today = CoachToday.of(plan, build: state, now: later, calendar: Self.calendar)
        guard case .done(let next)? = today else {
            Issue.record("Expected today's run done, got \(String(describing: today))")
            return
        }
        #expect(next?.sessionID == wednesday.id)
    }

    // MARK: Heart rate

    /// The cue reads the run's heart-rate source as the coach's device by raw value.
    @Test func everySourceMapsToACoachDevice() {
        for source in HeartRateSource.allCases {
            #expect(HeartRateDevice(rawValue: source.rawValue) != nil, "\(source)")
        }
        #expect(HeartRateDevice(rawValue: HeartRateSource.strapOrSensor.rawValue) == .chestStrap)
        #expect(HeartRateDevice(rawValue: HeartRateSource.appleWatch.rawValue) == .appleWatch)
        #expect(HeartRateDevice(rawValue: HeartRateSource.earbuds.rawValue) == .earbuds)
    }
}
