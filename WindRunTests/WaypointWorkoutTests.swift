import Foundation
import SwiftData
import Testing
@testable import WindRun

struct WaypointWorkoutTests {
    @MainActor @Test func normalWorkoutSaveAndEditPreserveWaypointLegs() {
        let container = WindRunSchema.makeContainer(inMemory: true)
        var draft = WorkoutDraft.starter()
        draft.waypointRoute = .outAndBack
        draft.sport = .cycling
        let plan = draft.save(replacing: nil, in: container.mainContext)
        #expect(plan.timeline.map(\.kind) == [.work, .recovery])
        #expect(plan.waypointRoute?.activity == .ride)
        #expect(WorkoutDraft(plan).waypointRoute == plan.waypointRoute)
        #expect(WatchSavedWorkout(plan).makePlan(in: container.mainContext).waypointRoute == plan.waypointRoute)
    }

    @MainActor @Test func individualWaypointEndingsMixWithTimedStepsAndSyncToWatch() {
        let container = WindRunSchema.makeContainer(inMemory: true)
        let gate = WaypointEnd(name: "Park gate", point: .poolStart)
        let draft = WorkoutDraft(name: "Park run", warmup: .waypoint(gate), main: .time(600),
                                 cooldown: .waypoint(.startingPoint))
        let plan = draft.save(replacing: nil, in: container.mainContext)
        #expect(WorkoutDraft(plan) == draft)
        #expect(plan.timeline.map(\.goal) == [.waypoint(gate), .time(600), .waypoint(.startingPoint)])
        #expect(WatchSavedWorkout(plan).timeline == plan.timeline)
    }

    @Test func outAndBackReturnsToTheActualStart() {
        var progress = WaypointProgress(workout: .outAndBack)
        let actualStart = RoutePoint(latitude: 38.8886, longitude: -77.045)
        progress.receive(actualStart)
        #expect(progress.effort == .work)
        progress.receive(WaypointWorkout.outAndBack.points[0].point)
        #expect(progress.target == actualStart)
        #expect(progress.effort == .recovery)
        progress.receive(WaypointWorkout.outAndBack.points[0].point)
        #expect(!progress.finished)
        progress.receive(actualStart)
        #expect(progress.finished)
    }

    @Test func onlyTheNextWaypointCanChangeEffort() {
        var workout = WaypointWorkout.pool
        workout.returnsToStart = false
        var progress = WaypointProgress(workout: workout)
        progress.receive(.poolStart)
        progress.receive(.init(latitude: 38.88991, longitude: -77.0500))
        #expect(progress.leg == 0)
        for point in workout.points {
            #expect(progress.effort == point.effort)
            progress.receive(point.point)
        }
        #expect(progress.finished)
        #expect(progress.target == nil)
    }

    // Equator fixtures keep a degree of longitude and latitude about the same length.
    private func point(east: Double, north: Double) -> RoutePoint {
        .init(latitude: north / 111_320, longitude: east / 111_320)
    }

    private func oneLeg() -> WaypointProgress {
        let waypoint = WorkoutWaypoint(name: "Intersection", point: point(east: 0, north: 0), effort: .work)
        return WaypointProgress(workout: .init(name: "Test", points: [waypoint], returnsToStart: false))
    }

    @Test func passesOnEitherSideFromDifferentDirections() {
        for offset in [-70.0, 70.0] {
            var eastbound = oneLeg()
            eastbound.receive(point(east: -130, north: offset))
            eastbound.receive(point(east: -15, north: offset))
            #expect(!eastbound.finished)
            eastbound.receive(point(east: 35, north: offset))
            #expect(eastbound.finished)

            var southbound = oneLeg()
            southbound.receive(point(east: offset, north: 120))
            southbound.receive(point(east: offset, north: -120))
            #expect(southbound.finished)
        }
    }

    @Test func wideMissAndStationaryNoiseDoNotAdvance() {
        var wide = oneLeg()
        wide.receive(point(east: -120, north: 100))
        wide.receive(point(east: 120, north: 100))
        #expect(!wide.finished)

        var noise = oneLeg()
        noise.receive(point(east: -3, north: 5), accuracy: 10)
        noise.receive(point(east: 3, north: 5), accuracy: 10)
        #expect(!noise.finished)
    }

    @Test func aShortFinalStrideUsesTheEstablishedHeading() {
        var progress = oneLeg()
        for east in [-60.0, -4.0] { progress.receive(point(east: east, north: 55), accuracy: 8) }
        #expect(!progress.finished)
        progress.receive(point(east: 2, north: 55), accuracy: 8)
        #expect(progress.finished)
    }

    @Test func doesNotConnectFixesAcrossAnOutage() {
        var progress = oneLeg()
        let start = Date.now
        progress.receive(point(east: -70, north: 10), at: start)
        progress.receive(point(east: 70, north: 10), at: start.addingTimeInterval(90))
        #expect(!progress.finished)
    }
}
