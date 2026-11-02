//
//  AppVersionTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The version row in Settings, which testers quote in their reports.
struct AppVersionTests {
    @Test func showsVersionThenBuild() {
        let info = ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "57"]
        #expect(AppVersion.text(for: info) == "0.2.0 (57)")
    }

    @Test func marksWhatIsMissing() {
        #expect(AppVersion.text(for: [:]) == "? (?)")
    }

    /// The app reads both numbers from Config/Version.xcconfig, so a build always has them.
    @Test func appCarriesBothNumbers() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let version = try #require(info["CFBundleShortVersionString"] as? String)
        let build = try #require(info["CFBundleVersion"] as? String)
        #expect(version.wholeMatch(of: #/\d+\.\d+\.\d+/#) != nil)
        #expect(build.wholeMatch(of: #/\d+/#) != nil)
    }
}
