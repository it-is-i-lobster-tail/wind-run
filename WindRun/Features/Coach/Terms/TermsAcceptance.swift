//
//  TermsAcceptance.swift
//  Wind Run
//

import Foundation

/// The runner's acceptance of Wind Run's terms, which include confirming they're healthy enough
/// to run. Coach mode only starts once it's stored.
///
/// It's kept on this device only: it isn't health data, but it isn't anything to sync either.
/// The app never checks the runner's health; the terms are the runner's own confirmation.
struct TermsAcceptance: Equatable {
    /// The terms the runner is asked to accept now. Bump it when the wording changes, and the
    /// runner is asked again.
    static let currentVersion = "draft-2026-10-19"

    static let versionKey = "termsAcceptedVersion"
    static let dateKey = "termsAcceptedDate"

    let version: String
    let date: Date

    /// The stored acceptance, if there is one.
    static func stored(in defaults: UserDefaults = .standard) -> TermsAcceptance? {
        guard let version = defaults.string(forKey: versionKey),
              let date = defaults.object(forKey: dateKey) as? Date
        else { return nil }
        return TermsAcceptance(version: version, date: date)
    }

    /// Whether the runner has accepted the terms as they are now.
    static func isCurrent(in defaults: UserDefaults = .standard) -> Bool {
        stored(in: defaults)?.version == currentVersion
    }

    /// Records the runner's acceptance of the current terms.
    static func accept(at date: Date = .now, in defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: versionKey)
        defaults.set(date, forKey: dateKey)
    }
}
