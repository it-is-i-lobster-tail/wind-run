//
//  RunNoticeTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// What the run screen says beside the numbers, and what it asks before finishing.
@MainActor
struct RunNoticeTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    // Each test gets its own store. It has to outlive the models in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private func notices(
        denied: Bool = false,
        approximate: Bool = false,
        status: RunStatus = .active,
        gps: GPSSignal = .good,
        heartRateStopped: Bool = false,
        heartRateBlocked: HeartRateBlock? = nil,
        heartRateSilent: Bool = false,
        goalReached: Bool = false
    ) -> [RunNotice] {
        ActiveRunView.notices(
            locationDenied: denied,
            locationApproximate: approximate,
            status: status,
            gps: gps,
            heartRateStopped: heartRateStopped,
            heartRateBlocked: heartRateBlocked,
            heartRateSilent: heartRateSilent,
            goalReached: goalReached
        )
    }

    private func makeRun(meters: Double) -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        run.distanceMetersValue = meters
        return run
    }

    // MARK: Notices

    @Test func locationOffComesBeforeGPS() {
        #expect(notices(denied: true, approximate: true, gps: .weak) == [.locationOff])
    }

    @Test func preciseLocationOffComesBeforeGPS() {
        #expect(notices(approximate: true, gps: .searching) == [.preciseLocationOff])
    }

    @Test func gpsOnlyShowsWhileRunning() {
        #expect(notices(status: .paused, gps: .searching) == [])
        #expect(notices(status: .active, gps: .searching) == [.findingGPS])
        #expect(notices(status: .active, gps: .good) == [])
    }

    @Test func gpsIsNotReadWhenLocationIsOff() {
        var reads = 0
        func signal() -> GPSSignal {
            reads += 1
            return .weak
        }

        _ = ActiveRunView.notices(locationDenied: true, locationApproximate: false, status: .active, gps: signal(), heartRateStopped: false, goalReached: false)
        _ = ActiveRunView.notices(locationDenied: false, locationApproximate: false, status: .paused, gps: signal(), heartRateStopped: false, goalReached: false)
        #expect(reads == 0)

        _ = ActiveRunView.notices(locationDenied: false, locationApproximate: false, status: .active, gps: signal(), heartRateStopped: false, goalReached: false)
        #expect(reads == 1)
    }

    @Test func heartRateAndGoalComeAfterTheRest() {
        #expect(notices(gps: .weak, heartRateStopped: true, goalReached: true) == [.weakGPS, .heartRateStopped, .goalReached])
        #expect(notices(denied: true, heartRateStopped: true) == [.locationOff, .heartRateStopped])
        #expect(notices(status: .paused, goalReached: true) == [.goalReached])
    }

    @Test func missingHeartRateSaysWhy() {
        #expect(notices(heartRateBlocked: .healthNotAllowed) == [.heartRateHealthOff])
        #expect(notices(heartRateBlocked: .couldNotStart) == [.heartRateCouldNotStart])
        #expect(notices(heartRateSilent: true) == [.noHeartRate])
        // One heart rate notice at a time: stopped says the most.
        #expect(notices(heartRateStopped: true, heartRateSilent: true) == [.heartRateStopped])
        #expect(notices(gps: .weak, heartRateSilent: true, goalReached: true) == [.weakGPS, .noHeartRate, .goalReached])
    }

    @Test func onlyTheLocationNoticesMeanNoDistance() {
        let noDistance: [RunNotice] = [.locationOff, .preciseLocationOff]
        let others: [RunNotice] = [.findingGPS, .weakGPS, .heartRateStopped, .heartRateHealthOff, .heartRateCouldNotStart, .noHeartRate, .goalReached]

        #expect(noDistance.allSatisfy { $0.meansNoDistance })
        #expect(!others.contains { $0.meansNoDistance })
    }

    // MARK: Finishing

    @Test func thirtySecondsWithSomeDistanceIsARun() {
        let run = makeRun(meters: 60)

        #expect(ActiveRunView.looksStartedByMistake(run, at: start.addingTimeInterval(29)))
        #expect(!ActiveRunView.looksStartedByMistake(run, at: start.addingTimeInterval(30)))
    }

    @Test func underFiftyMetersLooksStartedByMistakeUntilFiveMinutes() {
        let run = makeRun(meters: 49)

        #expect(ActiveRunView.looksStartedByMistake(run, at: start.addingTimeInterval(30)))
        #expect(ActiveRunView.looksStartedByMistake(run, at: start.addingTimeInterval(299)))
        #expect(!ActiveRunView.looksStartedByMistake(run, at: start.addingTimeInterval(300)))
    }

    @Test func fiftyMetersIsARunAfterThirtySeconds() {
        let run = makeRun(meters: 50)

        #expect(!ActiveRunView.looksStartedByMistake(run, at: start.addingTimeInterval(30)))
    }

    @Test func discardAsksWithNoMessageAndFinishSaysItCantBeCarriedOn() {
        let run = makeRun(meters: 0)

        #expect(ActiveRunView.Confirmation.discard.message(for: run, unit: .kilometers) == nil)
        #expect(ActiveRunView.Confirmation.finish.message(for: run, unit: .kilometers) == "A finished run can't be carried on.")
        #expect(ActiveRunView.Confirmation.discard.title(for: .running) == "Discard this run?")
        #expect(ActiveRunView.Confirmation.finish.title(for: .running) == "Finish this run?")
        #expect(ActiveRunView.Confirmation.finishShort.title(for: .running) == "Save this short run?")
    }
}
