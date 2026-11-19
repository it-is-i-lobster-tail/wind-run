//
//  AppearanceTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WindRun

/// Following the iPhone's light or dark setting, or a pick of the runner's own.
@MainActor
final class AppearanceTests {
    private let suiteName = "AppearanceTests-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let cloud = InMemoryKeyValueStore()

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test("Until the runner picks, the app follows the iPhone")
    func followsSystemByDefault() {
        #expect(Appearance.current(in: defaults) == .system)
        #expect(Appearance.system.interfaceStyle == .unspecified)

        defaults.set("sepia", forKey: Appearance.storageKey)
        #expect(Appearance.current(in: defaults) == .system)
    }

    @Test("Light and Dark hold whatever the iPhone is set to")
    func picksOverrideSystem() {
        defaults.set(Appearance.dark.rawValue, forKey: Appearance.storageKey)
        #expect(Appearance.current(in: defaults) == .dark)
        #expect(Appearance.dark.interfaceStyle == .dark)
        #expect(Appearance.light.interfaceStyle == .light)
    }

    @Test("Color Blind swaps every chart color, and syncs and logs like the other appearance settings")
    func colorBlindCharts() {
        #expect(CloudSettings.keys.contains(RunChartColor.colorBlindKey))
        #expect(TraceSettings.shownKeys.contains(RunChartColor.colorBlindKey))

        let standard = RunChartColor.palette(colorBlind: false)
        let safe = RunChartColor.palette(colorBlind: true)
        for style in [UIUserInterfaceStyle.light, .dark] {
            #expect(hex(standard.pace, style) != hex(safe.pace, style))
            #expect(hex(standard.elevation, style) != hex(safe.elevation, style))
            #expect(hex(standard.cadence, style) != hex(safe.cadence, style))
            #expect(hex(standard.heartRate, style) != hex(safe.heartRate, style))
            #expect(hex(standard.workStep, style) != hex(safe.workStep, style))
            #expect(hex(standard.easyStep, style) != hex(safe.easyStep, style))
        }
        #expect(hex(safe.pace, .dark) == "88CCEE")
        #expect(hex(safe.heartRate, .light) == "882255")
    }

    private func hex(_ color: Color, _ style: UIUserInterfaceStyle) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }

    @Test("The pick goes to iCloud with the other settings, and comes back on a new iPhone")
    func syncsThroughICloud() {
        #expect(CloudSettings.keys.contains(Appearance.storageKey))

        defaults.set(Appearance.light.rawValue, forKey: Appearance.storageKey)
        CloudSettings(defaults: defaults, cloud: cloud) { _, _ in }.startSyncing()
        #expect(cloud.object(forKey: CloudSettings.cloudPrefix + Appearance.storageKey) as? String == "light")

        let newPhone = UserDefaults(suiteName: suiteName + "-new")!
        defer { UserDefaults().removePersistentDomain(forName: suiteName + "-new") }
        CloudSettings(defaults: newPhone, cloud: cloud) { _, _ in }.startSyncing()
        #expect(Appearance.current(in: newPhone) == .light)
    }
}
