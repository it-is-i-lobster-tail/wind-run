//
//  YourDataMessagesTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// What Settings says about iCloud for each state the account can be in.
@MainActor
struct YourDataMessagesTests {
    private let notAvailable: [ICloudAccount] = [.signedOut, .needsPassword, .restricted, .unknown]

    @Test func onlyAnAvailableAccountSyncsWithoutANote() {
        #expect(YourDataSettingsView.notSyncing(.available) == nil)
        for account in notAvailable {
            #expect(YourDataSettingsView.notSyncing(account) != nil)
        }
        #expect(Set(notAvailable.compactMap { YourDataSettingsView.notSyncing($0) }).count == notAvailable.count)
    }

    @Test func everyCantDeleteOffersToLeaveTheCopy() {
        for account in notAvailable + [.available] {
            #expect(YourDataSettingsView.cantDelete(account).message.contains("leave the copy in iCloud"))
        }
    }

    @Test func anAvailableAccountGetsTheSignedOutMessages() {
        let turnOn = (available: YourDataSettingsView.cantTurnOn(.available), signedOut: YourDataSettingsView.cantTurnOn(.signedOut))
        #expect(turnOn.available.title == turnOn.signedOut.title)
        #expect(turnOn.available.message == turnOn.signedOut.message)
        let delete = (available: YourDataSettingsView.cantDelete(.available), signedOut: YourDataSettingsView.cantDelete(.signedOut))
        #expect(delete.available.title == delete.signedOut.title)
        #expect(delete.available.message == delete.signedOut.message)
    }

    @Test func eachStateHasItsOwnTitle() {
        #expect(Set(notAvailable.map { YourDataSettingsView.cantTurnOn($0).title }).count == notAvailable.count)
        #expect(Set(notAvailable.map { YourDataSettingsView.cantDelete($0).title }).count == notAvailable.count)
    }
}
