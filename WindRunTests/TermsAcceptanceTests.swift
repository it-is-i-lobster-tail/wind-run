//
//  TermsAcceptanceTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

@MainActor
struct TermsAcceptanceTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "TermsAcceptanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func coachWaitsForTheTerms() {
        let defaults = makeDefaults()
        #expect(TermsAcceptance.stored(in: defaults) == nil)
        #expect(!TermsAcceptance.isCurrent(in: defaults))
    }

    @Test func acceptanceIsStoredWithItsDate() {
        let defaults = makeDefaults()
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        TermsAcceptance.accept(at: date, in: defaults)

        #expect(TermsAcceptance.stored(in: defaults) == TermsAcceptance(version: TermsAcceptance.currentVersion, date: date))
        #expect(TermsAcceptance.isCurrent(in: defaults))
    }

    @Test func newTermsAreAskedAgain() {
        let defaults = makeDefaults()
        defaults.set("older-terms", forKey: TermsAcceptance.versionKey)
        defaults.set(Date.now, forKey: TermsAcceptance.dateKey)

        #expect(!TermsAcceptance.isCurrent(in: defaults))
    }
}
