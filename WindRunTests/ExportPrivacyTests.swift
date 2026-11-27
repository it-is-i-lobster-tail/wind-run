//
//  ExportPrivacyTests.swift
//  Wind Run Tests
//

import CoreLocation
import Foundation
import Testing
@testable import WindRun

/// Settings → Your Data → Starting Point: what exports hide, as it's kept.
@MainActor
final class ExportPrivacyTests {
    private let suiteName = "ExportPrivacyTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func nothingSavedHidesTheStartAndFinish() {
        let privacy = ExportPrivacy.load(from: defaults)
        #expect(privacy == .standard)
        #expect(privacy.mode == .startAndFinish)
        #expect(privacy.meters == 250)
        #expect(privacy.pins.isEmpty)
    }

    @Test func savedChoicesComeBack() {
        let home = ExportPrivacy.Pin(CLLocationCoordinate2D(latitude: 39.74, longitude: -104.99))
        let work = ExportPrivacy.Pin(CLLocationCoordinate2D(latitude: 39.75, longitude: -105.0))
        let privacy = ExportPrivacy(mode: .pins, meters: 400, pins: [home, work])
        privacy.save(to: defaults)
        #expect(ExportPrivacy.load(from: defaults) == privacy)

        // Deleting the last pin clears the setting.
        ExportPrivacy(mode: .pins, meters: 400).save(to: defaults)
        #expect(defaults.object(forKey: ExportPrivacy.pinsKey) == nil)
    }

    @Test func theDistanceStaysOnTheSlider() {
        #expect(ExportPrivacy.clamped(0) == 100)
        #expect(ExportPrivacy.clamped(-50) == 100)
        #expect(ExportPrivacy.clamped(5_000) == 1_000)
        #expect(ExportPrivacy.clamped(262) == 250)
        #expect(ExportPrivacy.clamped(280) == 300)
        // A value from iCloud below the slider can't shrink what's hidden.
        defaults.set(10.0, forKey: ExportPrivacy.metersKey)
        #expect(ExportPrivacy.load(from: defaults).meters == 100)
    }

    @Test func oddStoredValuesFallBack() {
        defaults.set("everywhere", forKey: ExportPrivacy.modeKey)
        defaults.set(Data("not pins".utf8), forKey: ExportPrivacy.pinsKey)
        #expect(ExportPrivacy.load(from: defaults) == .standard)
    }

    @Test func pinsOnlyCountOnceThereIsOne() {
        let first = CLLocation(latitude: 1, longitude: 1)
        let last = CLLocation(latitude: 2, longitude: 2)
        var privacy = ExportPrivacy(mode: .pins)
        #expect(privacy.centers(first: first, last: last) == [first, last])
        let pin = ExportPrivacy.Pin(CLLocationCoordinate2D(latitude: 3, longitude: 3))
        privacy.pins = [pin]
        #expect(privacy.centers(first: first, last: last).map(\.coordinate.latitude) == [3])
    }

    @Test func distancesReadInTheRunnersUnit() {
        #expect(ExportPrivacy.text(250, unit: .kilometers) == "250 m")
        #expect(ExportPrivacy.text(250, unit: .miles) == "820 ft")
        #expect(ExportPrivacy.text(1_000, unit: .miles) == "\(3_280.formatted()) ft")
    }

    @Test func theChoicesSyncWithTheOtherSettings() {
        for key in ExportPrivacy.syncedKeys {
            #expect(CloudSettings.keys.contains(key))
        }
    }
}
