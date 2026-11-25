import MapKit
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

    @MainActor @Test func waypointRequiresAPinAndReturnIsAFinalLeg() {
        #expect(WorkoutEndFields.goal(ending: .waypoint, minutes: "", seconds: "", amount: "", exactMeters: nil, unit: .kilometers) == .waypoint(.init(name: "Waypoint", point: nil)))
        let container = WindRunSchema.makeContainer(inMemory: true)
        let pin = WaypointEnd(name: "Terrace", point: .poolStart)
        var draft = WorkoutDraft(name: "Out and back", warmup: .waypoint(pin), main: .time(600))
        draft.returnToStart = true
        let plan = draft.save(replacing: nil, in: container.mainContext)
        #expect(plan.timeline.count == 3)
        #expect(WorkoutDraft(plan) == draft)
    }

    @MainActor @Test func mapCentersOnAllPinsIncludingAcrossTheDateLine() throws {
        #expect(WaypointEditor.programRegion([]) == nil)
        let region = try #require(WaypointEditor.programRegion([
            .init(latitude: 10, longitude: 179), .init(latitude: 10, longitude: 179),
            .init(latitude: 13, longitude: -178)
        ]))
        #expect(abs(region.center.latitude - 11) < 0.001)
        #expect(abs(abs(region.center.longitude) - 180) < 0.001)
        #expect(region.span.longitudeDelta < 10)
    }

    @MainActor @Test func savesDistinctWaypointPairsInOrderAndDropsUnusedRepeats() {
        let pins = WaypointWorkout.pool.points.map { WaypointEnd(name: $0.name, point: $0.point) }
        let first = WorkoutMain.WaypointPair(work: pins[0], recovery: pins[1])
        let second = WorkoutMain.WaypointPair(work: pins[2], recovery: pins[3])
        let draft = WorkoutDraft(name: "Trail", main: .waypointIntervals([first, second, .init()]))
        #expect(MissingWorkoutWaypoint.first(in: draft) == nil)
        let container = WindRunSchema.makeContainer(inMemory: true)
        let plan = draft.save(replacing: nil, in: container.mainContext)
        #expect(plan.timeline.map(\.goal) == pins.map(IntervalGoal.waypoint))
        #expect(WorkoutDraft(plan).main == .waypointIntervals([first, second]))
        #expect(WorkoutDraft.fits(plan))
        #expect(WatchSavedWorkout(plan).timeline == plan.timeline)
    }

    @MainActor @Test func saveIdentifiesTheFirstUnfinishedWaypoint() {
        let pin = WaypointEnd(name: "Trail", point: .poolStart)
        let empty = WaypointEnd(name: "Waypoint", point: nil)
        var draft = WorkoutDraft(name: "Trail", main: .waypointIntervals([.init(), .init()]))
        #expect(MissingWorkoutWaypoint.first(in: draft)?.field == "Work - 1")
        let first = WorkoutMain.WaypointPair(work: pin, recovery: pin)
        draft.main = .waypointIntervals([first, .init(work: pin)])
        #expect(MissingWorkoutWaypoint.first(in: draft)?.field == "Recovery - 2")
        draft.main = .waypointIntervals([first, .init(recovery: pin)])
        #expect(MissingWorkoutWaypoint.first(in: draft)?.field == "Work - 2")
        draft.warmup = .waypoint(empty)
        #expect(MissingWorkoutWaypoint.first(in: draft)?.part == .warmup)
        draft.warmup = nil
        draft.main = .waypoint(empty)
        #expect(MissingWorkoutWaypoint.first(in: draft)?.part == .main)
        draft.main = .free
        draft.cooldown = .waypoint(empty)
        #expect(MissingWorkoutWaypoint.first(in: draft)?.part == .cooldown)
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
        for offset in [-19.0, 19.0] {
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
        for offset in [-60.0, -21, 21, 60] {
            var wide = oneLeg()
            wide.receive(point(east: -120, north: offset))
            wide.receive(point(east: 120, north: offset))
            #expect(!wide.finished)
        }

        var noise = oneLeg()
        noise.receive(point(east: -3, north: 5), accuracy: 10)
        noise.receive(point(east: 3, north: 5), accuracy: 10)
        #expect(!noise.finished)
    }

    @Test func aShortFinalStrideUsesTheEstablishedHeading() {
        var progress = oneLeg()
        for east in [-60.0, -4.0] { progress.receive(point(east: east, north: 15), accuracy: 8) }
        #expect(!progress.finished)
        progress.receive(point(east: 2, north: 15), accuracy: 8)
        #expect(progress.finished)
    }

    @Test func doesNotConnectFixesAcrossAnOutage() {
        var progress = oneLeg()
        let start = Date.now
        progress.receive(point(east: -70, north: 10), at: start)
        progress.receive(point(east: 70, north: 10), at: start.addingTimeInterval(90))
        #expect(!progress.finished)
    }
    private func replayRoute(_ gates: [Double], returns: Bool = false) -> WaypointProgress {
        let points = gates.map { WorkoutWaypoint(name: "Gate", point: point(east: $0, north: 0), effort: .work) }
        return WaypointProgress(workout: .init(name: "Replay", points: points, returnsToStart: returns))
    }

    @Test func consecutiveCrossingsInterpolateTimePositionAndDistance() throws {
        var progress = replayRoute([65, 69])
        let date = Date(timeIntervalSince1970: 1000)
        for east in [45.0, 60] {
            progress.receive(point(east: east, north: 5), accuracy: 3,
                             at: date.addingTimeInterval((east - 60) / 5), meters: east)
        }
        let events = progress.receive(point(east: 70, north: 5), accuracy: 3, at: date.addingTimeInterval(2), meters: 70)
        #expect(events.count == 2)
        for (event, gate) in zip(events, [65.0, 69]) {
            #expect(abs(event.meters - gate) < 0.01)
            #expect(event.point.location.distance(from: point(east: gate, north: 5).location) < 0.01)
            let time = try #require(event.date)
            #expect(abs(time.timeIntervalSince(date) - (gate - 60) / 5) < 0.01)
        }
        #expect(progress.finished)
    }

    @Test func skippingAdvancesOneWaypointAndPreservesReturnDestination() {
        var progress = replayRoute([100, 200], returns: true)
        let origin = point(east: 0, north: 0)
        progress.receive(origin)
        progress.skipWaypoint()
        #expect(progress.leg == 1)
        #expect(progress.target == point(east: 200, north: 0))
        for east in [150.0, 210] { progress.receive(point(east: east, north: 0)) }
        #expect(progress.target == origin)
        progress.skipWaypoint()
        progress.skipWaypoint()
        #expect(progress.finished)
        #expect(progress.leg == 3)
    }

    @Test func coincidentGatesRequireANewPass() {
        var progress = replayRoute([20, 20])
        for east in [0.0, 25, 40] { progress.receive(point(east: east, north: 0)) }
        #expect(progress.leg == 1)
        progress.receive(point(east: 0, north: 0))
        #expect(progress.finished)
    }

    @Test func shortTurnDoesNotUseAnEarlierHeading() {
        var progress = oneLeg()
        for (x, y) in [(-24.0, -65.0), (-8, -65), (-1, -65), (1, -60), (2, -50)] {
            progress.receive(point(east: x, north: y), accuracy: 5)
        }
        #expect(progress.leg == 0)
        progress.receive(point(east: 2, north: 5), accuracy: 5)
        #expect(progress.finished)
    }

    @Test func aLateralCrossingOnANewBearingWaitsForConfirmation() {
        var progress = oneLeg()
        for (x, y) in [(-40.0, -10.0), (-18, -10), (-18, 5)] {
            progress.receive(point(east: x, north: y), accuracy: 3)
        }
        #expect(!progress.finished)
        let events = progress.receive(point(east: -18, north: 10), accuracy: 3)
        #expect(events.count == 1)
        #expect(progress.finished)
    }

    @Test func aShortOutAndBackCanFinishBeforeAnInitialHeadingIsAvailable() {
        var progress = replayRoute([4], returns: true)
        for x in [0.0, 3, 6, 3] {
            progress.receive(point(east: x, north: 0), accuracy: 2)
        }
        #expect(progress.leg == 0)
        progress.receive(point(east: 0, north: 0), accuracy: 2)
        #expect(progress.finished)
    }

    @Test func confirmsEarlyTurnOnlyForAReturnLegWithGoodGPS() {
        for (returns, accuracy, expected) in [(true, 3.0, 1), (false, 3.0, 0), (true, 11.0, 0)] {
            var progress = replayRoute([65], returns: returns)
            for x in [0.0, 25, 45, 60, 60, 60, 55] {
                progress.receive(point(east: x, north: 0), accuracy: accuracy)
            }
            #expect(progress.leg == 0)
            progress.receive(point(east: 49, north: 0), accuracy: accuracy)
            #expect(progress.leg == expected)
            if returns && expected == 1 {
                progress.receive(point(east: -5, north: 0), accuracy: accuracy)
                #expect(progress.finished)
            }
        }
    }

    @Test func ignoresJumpPauseAndLateFixAcrossGates() {
        var progress = replayRoute([20, 16])
        let date = Date(timeIntervalSince1970: 400)
        for (t, x) in [(0.0, 0.0), (2, 12), (4, 20), (1, 3), (5, 22), (6, 25)] {
            progress.receive(point(east: x, north: 0), accuracy: 3, at: date.addingTimeInterval(t))
        }
        #expect(progress.leg == 1)
        progress.breakTrack()
        progress.receive(point(east: -1, north: 0), at: date.addingTimeInterval(10))
        #expect(progress.leg == 1)
        progress.receive(point(east: 59, north: 0), accuracy: 3, at: date.addingTimeInterval(11))
        #expect(progress.leg == 1)
    }

    @Test func lateralGPSJitterStillRecordsBothOrderedPasses() {
        var progress = replayRoute([0, 25])
        var crossings: [WaypointFix] = []
        for second in 0...65 {
            let distance = Double(second) * 3
            let fix = point(east: distance - 90, north: 15 + 3 * sin(1.3 * Double(second)))
            crossings += progress.receive(fix, accuracy: 5,
                                          at: Date(timeIntervalSince1970: 1000 + Double(second)), meters: distance)
        }
        #expect(crossings.count == 2)
        for (event, expected) in zip(crossings, [90.0, 115.0]) {
            #expect(abs(event.meters - expected) < 12)
        }
    }

    @Test func stoppingCanConfirmAnEarlierLateralCrossing() {
        for (stop, expectedLeg) in [(38.0, 0), (40.0, 1), (42.0, 1)] {
            var progress = replayRoute([40])
            let approach = (0..<10).map { Double($0) * 4 }
            for (i, x) in (approach + Array(repeating: stop, count: 10)).enumerated() {
                progress.receive(point(east: x, north: -15), accuracy: 3,
                                 at: Date(timeIntervalSince1970: 1000 + Double(i)))
            }
            #expect(progress.leg == expectedLeg)
        }
    }

    @MainActor @Test func waypointBlockStopsBeforeTimedPhase() throws {
        let gate = WaypointEnd(name: "Park", point: .poolStart)
        let draft = WorkoutDraft(name: "Mixed", warmup: .waypoint(gate), main: .time(600), cooldown: .waypoint(gate))
        let tracker = StepTracker(timeline: draft.timeline)
        let block = try #require(RunRecorder.waypointBlock(tracker, start: .poolStart, sport: .running))
        #expect(block.legCount == 1)
        #expect(!block.returnsToStart)
    }

}
