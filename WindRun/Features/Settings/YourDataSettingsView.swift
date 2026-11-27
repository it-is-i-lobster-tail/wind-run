//
//  YourDataSettingsView.swift
//  Wind Run
//
//  Where your runs are kept: iCloud Sync, exporting them, and what exports hide.
//

import CloudKit
import SwiftUI

struct YourDataSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(WindRunStore.self) private var store

    @State private var account = ICloudAccount.available
    @State private var isSwitchingICloudSync = false
    @State private var isDeletingICloudCopy = false
    @State private var isConfirmingICloudSyncOff = false
    @State private var showsSignInNeeded = false
    @State private var showsSignedOutChoice = false
    @State private var showsICloudOffError = false
    @State private var showsStoreError = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: iCloudSync) {
                    SettingsRowLabel(
                        title: "iCloud Sync",
                        detail: "Keeps your runs, routes, plans and settings in your private iCloud, so a new iPhone picks up right where you left off. Turning it off deletes that copy."
                    ) {
                        if isSwitchingICloudSync {
                            ProgressView()
                        } else {
                            Image(systemName: "icloud")
                        }
                    }
                }
                .disabled(isSwitchingICloudSync)
            } footer: {
                if isDeletingICloudCopy {
                    Text("Deleting your iCloud copy…")
                } else if isSwitchingICloudSync {
                    Text("Turning on iCloud Sync…")
                } else if store.syncsWithICloud, let problem = Self.notSyncing(account) {
                    Text(problem)
                }
            }

            // Its own card, so the iCloud note above stays with iCloud Sync.
            Section {
                ExportRunsRow()
            }

            Section {
                NavigationLink(value: SettingsPage.startingPoint) {
                    SettingsRowLabel(
                        title: SettingsPage.startingPoint.title,
                        detail: "Choose what your exports hide, so they can't lead anyone to your home."
                    ) {
                        Image(systemName: SettingsPage.startingPoint.systemImage)
                    }
                }
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Your Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Turn Off iCloud Sync?", isPresented: $isConfirmingICloudSyncOff) {
            Button("Turn Off and Delete", role: .destructive) {
                Trace.tap("Settings", "Turn Off iCloud Sync: Turn Off and Delete")
                turnOffICloudSync()
            }
            Button("Cancel", role: .cancel) {
                Trace.tap("Settings", "Turn Off iCloud Sync: Cancel")
            }
        } message: {
            Text("Your runs and settings stay on this iPhone, but the copy in iCloud will be deleted. A new iPhone won't get them back.")
        }
        .alert(Self.cantTurnOn(account).title, isPresented: $showsSignInNeeded) {
            Button("OK", role: .cancel) { Trace.tap("Settings", "Can't turn on iCloud Sync: OK", ["account": account.rawValue]) }
        } message: {
            Text(Self.cantTurnOn(account).message)
        }
        .alert(Self.cantDelete(account).title, isPresented: $showsSignedOutChoice) {
            Button("Turn Off and Keep Copy") {
                Trace.tap("Settings", "Can't delete iCloud copy: Turn Off and Keep Copy", ["account": account.rawValue])
                store.turnOffICloudSyncKeepingCopy()
            }
            Button("Cancel", role: .cancel) { Trace.tap("Settings", "Can't delete iCloud copy: Cancel") }
        } message: {
            Text(Self.cantDelete(account).message)
        }
        .alert("Couldn't Turn Off iCloud Sync", isPresented: $showsICloudOffError) {
            Button("OK", role: .cancel) { Trace.tap("Settings", "Couldn't Turn Off iCloud Sync: OK") }
        } message: {
            Text("iCloud couldn't be reached, so nothing was deleted. Check your connection and try again.")
        }
        .alert("Couldn't Change iCloud Sync", isPresented: $showsStoreError) {
            Button("OK", role: .cancel) { Trace.tap("Settings", "Couldn't Change iCloud Sync: OK") }
        } message: {
            Text("Wind Run couldn't reopen your runs that way, so nothing changed. Try again later.")
        }
        .traceScreen("Your Data")
        // Again on coming back, such as from signing in to iCloud in the Settings app.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            account = await store.iCloudAccount()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                account = await store.iCloudAccount()
                Trace.log(.icloud, "Account changed", ["account": account.rawValue])
            }
        }
    }

    /// Why nothing is syncing while iCloud Sync is on, or nil when it can.
    static func notSyncing(_ account: ICloudAccount) -> String? {
        switch account {
        case .available: nil
        case .signedOut: "You're signed out of iCloud, so nothing is syncing. Sign in to iCloud in the Settings app to pick up again."
        case .needsPassword: "iCloud needs your password in the Settings app, so nothing is syncing until it's entered."
        case .restricted: "iCloud is turned off for this iPhone, such as by Screen Time, so nothing is syncing."
        case .unknown: "iCloud can't be reached right now, so nothing is syncing. It picks up again on its own."
        }
    }

    /// What to say when iCloud Sync can't be turned on.
    static func cantTurnOn(_ account: ICloudAccount) -> (title: String, message: String) {
        switch account {
        case .needsPassword:
            ("Enter Your iCloud Password", "iCloud needs your password again. Enter it in the Settings app, then turn iCloud Sync on.")
        case .restricted:
            ("iCloud Is Turned Off", "iCloud is turned off for this iPhone, such as by Screen Time or the iPhone's manager, so Wind Run can't sync.")
        case .unknown:
            ("Couldn't Reach iCloud", "iCloud couldn't be reached. Check your connection and try again.")
        case .signedOut, .available:
            ("Sign In to iCloud First", "iCloud sync needs an iCloud account. Sign in to iCloud in the Settings app, then turn it on.")
        }
    }

    /// What to say when the copy in iCloud can't be reached to delete it. Each offers to leave it there.
    static func cantDelete(_ account: ICloudAccount) -> (title: String, message: String) {
        switch account {
        case .needsPassword:
            ("Enter Your iCloud Password", "iCloud needs your password before Wind Run can delete its copy there. Enter it in the Settings app and try again, or turn sync off now and leave the copy in iCloud.")
        case .restricted:
            ("iCloud Is Turned Off", "iCloud is turned off for this iPhone, so Wind Run can't reach its copy there to delete it. Try again once iCloud is back, or turn sync off now and leave the copy in iCloud.")
        case .unknown:
            ("Couldn't Reach iCloud", "iCloud couldn't be reached, so its copy can't be deleted yet. Try again later, or turn sync off now and leave the copy in iCloud.")
        case .signedOut, .available:
            ("You're Signed Out of iCloud", "Wind Run can't reach its copy in iCloud to delete it. Sign in to iCloud and try again, or turn sync off now and leave the copy in iCloud.")
        }
    }

    // Turning sync off asks first, because it deletes the iCloud copy.
    private var iCloudSync: Binding<Bool> {
        Binding(
            get: { store.syncsWithICloud },
            set: { isOn in
                Trace.tap("Settings", "iCloud Sync", ["on": isOn])
                if isOn {
                    turnOnICloudSync()
                } else {
                    isConfirmingICloudSyncOff = true
                }
            }
        )
    }

    private func turnOnICloudSync() {
        isSwitchingICloudSync = true
        Task {
            do {
                try await store.turnOnICloudSync()
                account = .available
            } catch ICloudSyncError.storeUnavailable {
                Trace.log(.icloud, "Couldn't turn on iCloud sync: store")
                showsStoreError = true
            } catch {
                Trace.error("Couldn't turn on iCloud sync", error)
                account = await store.iCloudAccount()
                showsSignInNeeded = true
            }
            isSwitchingICloudSync = false
        }
    }

    private func turnOffICloudSync() {
        isSwitchingICloudSync = true
        isDeletingICloudCopy = true
        Task {
            do {
                try await store.turnOffICloudSync()
            } catch ICloudSyncError.signedOut {
                Trace.log(.icloud, "Couldn't turn off iCloud sync: signed out")
                account = await store.iCloudAccount()
                showsSignedOutChoice = true
            } catch ICloudSyncError.storeUnavailable {
                Trace.log(.icloud, "Couldn't turn off iCloud sync: store")
                showsStoreError = true
            } catch {
                Trace.error("Couldn't turn off iCloud sync", error)
                showsICloudOffError = true
            }
            isDeletingICloudCopy = false
            isSwitchingICloudSync = false
        }
    }
}

#Preview("Your Data") {
    NavigationStack { YourDataSettingsView() }
        .environment(WindRunStore(inMemory: true))
}
