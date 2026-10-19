//
//  RunRecoveryTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct RunRecoveryTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    // Each test gets its own instance, so its own store. It has to outlive the models in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private var context: ModelContext { container.mainContext }

    private func makeRun() -> Run {
        let run = Run(startDate: start)
        context.insert(run)
        return run
    }

    private func fix(at seconds: TimeInterval, kilometersNorth: Double) -> RouteSample {
        RouteSample(
            timestamp: start.addingTimeInterval(seconds),
            latitude: kilometersNorth / 111.0,
            longitude: 0,
            horizontalAccuracy: 5
        )
    }

    private func recover() {
        RunRecovery.finishLeftoverRuns(in: context, savingTo: nil)
    }

    private func allRuns() throws -> [Run] {
        try context.fetch(FetchDescriptor<Run>())
    }

    @Test func aCutOffRunFinishesAtItsLastFix() throws {
        let run = makeRun()
        run.record(fix(at: 10, kilometersNorth: 0))
        run.record(fix(at: 70, kilometersNorth: 0.2))

        recover()

        #expect(run.status == .complete)
        #expect(run.endDate == start.addingTimeInterval(70))
        #expect(run.activeDuration() == 70)
        #expect(try allRuns().count == 1)
    }

    @Test func aRunCutOffWhilePausedFinishesWithThePauseClosed() {
        let run = makeRun()
        run.record(fix(at: 10, kilometersNorth: 0))
        run.record(fix(at: 60, kilometersNorth: 0.2))
        run.pause(at: start.addingTimeInterval(65))

        recover()

        #expect(run.status == .complete)
        #expect(run.endDate == start.addingTimeInterval(60))
        #expect(run.pauses.allSatisfy { $0.endDate != nil })
        #expect(run.activeDuration() == 60)
    }

    @Test func aLaterHeartRateReadingSetsTheEnd() {
        let run = makeRun()
        run.record(fix(at: 10, kilometersNorth: 0))
        run.record(HeartRateSample(timestamp: start.addingTimeInterval(40), beatsPerMinute: 150))

        recover()

        #expect(run.endDate == start.addingTimeInterval(40))
    }

    @Test func aRunThatRecordedNothingIsDeleted() throws {
        _ = makeRun()

        recover()

        #expect(try allRuns().isEmpty)
    }

    @Test func finishedRunsAreLeftAlone() throws {
        let run = makeRun()
        run.record(fix(at: 10, kilometersNorth: 0))
        run.record(fix(at: 70, kilometersNorth: 0.2))
        run.finish(at: start.addingTimeInterval(90))

        recover()

        #expect(run.endDate == start.addingTimeInterval(90))
        #expect(try allRuns().count == 1)
    }
}
