//
//  AppVersion.swift
//  Wind Run
//

import Foundation

/// The version and build number of this copy of the app, as App Store Connect and TestFlight
/// show them: "1.1.4 (57)". Every build from main has its own version (the patch counts up
/// with each merge, see scripts/release/build-version.sh) and the build number comes from
/// Xcode Cloud, so a tester's report names the exact build.
enum AppVersion {
    static let current = text(for: Bundle.main.infoDictionary ?? [:])

    static func text(for info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
