//
//  AppVersion.swift
//  Wind Run
//

import Foundation

/// The version and build number of this copy of the app, as App Store Connect and TestFlight
/// show them: "0.2.0 (57)". The version comes from Config/Version.xcconfig and the build
/// number from Xcode Cloud, so a tester's report names the exact build.
enum AppVersion {
    static let current = text(for: Bundle.main.infoDictionary ?? [:])

    static func text(for info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
