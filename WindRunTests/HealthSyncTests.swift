//
//  HealthSyncTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The parts of Save runs to Health that don't need Health itself: the switch, turning it on, and the runs
/// kept to try again.
@MainActor
final class HealthSyncTests {
    private let suiteName = "HealthSyncTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test("The switch is read from the store it's given")
    func switchReadsItsOwnStore() {
        #expect(!HealthSync.isEnabled(in: defaults))
        defaults.set(true, forKey: HealthSync.enabledKey)
        #expect(HealthSync.isEnabled(in: defaults))
    }

    @Test("Switches go back off only when Health says no")
    func turningOnRollsBackOnlyWhenDenied() async {
        let keys = [HeartRateMonitor.storageKey, HealthSync.enabledKey]

        var sawOn = false
        let denied = await HealthSync.turnOn(keys, defaults: defaults) {
            // On while Health is asked.
            sawOn = keys.allSatisfy { self.defaults.bool(forKey: $0) }
            return .denied
        }
        #expect(denied == .denied)
        #expect(sawOn)
        #expect(keys.allSatisfy { defaults.object(forKey: $0) as? Bool == false })

        // A question not answered yet leaves them on, to be answered later.
        let notAsked = await HealthSync.turnOn(keys, defaults: defaults) { .notDetermined }
        #expect(notAsked == .notDetermined)
        #expect(keys.allSatisfy { defaults.bool(forKey: $0) })

        defaults.set(false, forKey: HealthSync.enabledKey)
        let allowed = await HealthSync.turnOn([HealthSync.enabledKey], defaults: defaults) { .allowed }
        #expect(allowed == .allowed)
        #expect(defaults.bool(forKey: HealthSync.enabledKey))
    }

    @Test("A run is kept to try again only once")
    func pendingRunsAreKeptOnce() {
        let id = UUID()
        HealthSync.addPending(id, in: defaults)
        HealthSync.addPending(id, in: defaults)
        #expect(HealthSync.pending(in: defaults) == [id])
    }

    @Test("The list goes once the last run in it is saved")
    func pendingListGoesWhenEmpty() {
        let a = UUID()
        let b = UUID()
        HealthSync.addPending(a, in: defaults)
        HealthSync.addPending(b, in: defaults)
        #expect(HealthSync.pending(in: defaults) == [a, b])

        HealthSync.removePending(a, in: defaults)
        #expect(HealthSync.pending(in: defaults) == [b])

        HealthSync.removePending(b, in: defaults)
        #expect(defaults.object(forKey: HealthSync.pendingKey) == nil)
        #expect(HealthSync.pending(in: defaults).isEmpty)
    }

    @Test("Anything in the list that isn't a run id is skipped")
    func unreadableIDsAreSkipped() {
        let id = UUID()
        defaults.set(["garbage", id.uuidString], forKey: HealthSync.pendingKey)
        #expect(HealthSync.pending(in: defaults) == [id])
    }

    @Test("With the switch off, runs waiting for Health are forgotten")
    func retryWithTheSwitchOffForgetsThem() {
        let container = WindRunSchema.makeContainer(inMemory: true)
        defaults.set(false, forKey: HealthSync.enabledKey)
        HealthSync.addPending(UUID(), in: defaults)

        HealthSync.shared.retryPending(in: container.mainContext, defaults: defaults)

        #expect(defaults.object(forKey: HealthSync.pendingKey) == nil)
    }
}
