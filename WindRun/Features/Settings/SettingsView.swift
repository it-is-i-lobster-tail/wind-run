//
//  SettingsView.swift
//  Wind Run
//

import CloudKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(WindRunStore.self) private var store
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    /// Trace logging's switch, kept by `TraceFiles`, so the row shows it's on.
    @AppStorage(Trace.storageKey) private var traceIsOn = false

    @State private var account = ICloudAccount.available
    @State private var isSwitchingICloudSync = false
    @State private var isDeletingICloudCopy = false
    @State private var isConfirmingICloudSyncOff = false
    @State private var showsSignInNeeded = false
    @State private var showsSignedOutChoice = false
    @State private var showsICloudOffError = false
    @State private var showsStoreError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: $unit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text("\(unit.systemName) (\(unit.symbol))").tag(unit)
                        }
                    }
                } header: {
                    Text("Units")
                } footer: {
                    Text("Distance, pace, height and weight all follow this.")
                }

                Section {
                    BodyWeightRow(unit: unit)
                } header: {
                    Text("Body")
                } footer: {
                    Text("Used to work out the calories each run burns. A newer weight in Apple Health replaces it. It syncs with your other settings when iCloud Sync is on.")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { appearance in
                            Text(appearance.name).tag(appearance)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your iPhone's Light or Dark setting.")
                }

                PaceCalloutSection()
                HapticsSection()

                HealthSyncSection()
                HeartRateSection()
                MotionSection()

                Section {
                    Toggle(isOn: iCloudSync) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iCloud Sync")
                                Text("Keeps your runs, routes, plans and settings in your private iCloud, so a new iPhone picks up right where you left off. Turning it off deletes that copy.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            if isSwitchingICloudSync {
                                ProgressView()
                            } else {
                                Image(systemName: "icloud")
                            }
                        }
                    }
                    .disabled(isSwitchingICloudSync)

                    ExportRunsRow()
                } header: {
                    Text("Your Data")
                } footer: {
                    if isDeletingICloudCopy {
                        Text("Deleting your iCloud copy…")
                    } else if isSwitchingICloudSync {
                        Text("Turning on iCloud Sync…")
                    } else if store.syncsWithICloud, let problem = Self.notSyncing(account) {
                        Text(problem)
                    }
                }

                Section {
                    if store.syncsWithICloud {
                        Label("Runs, routes and settings sync to your private iCloud. Only you can see them.", systemImage: "icloud")
                    } else {
                        Label("Runs, routes and settings stay on this iPhone.", systemImage: "lock")
                    }
                    Label("No account, no tracking, no analytics.", systemImage: "eye.slash")
                } header: {
                    Text("Privacy")
                }

                Section {
                    NavigationLink {
                        DeveloperToolView()
                    } label: {
                        // It stays on across launches, so a runner who turned it on for a report can see it is.
                        LabeledContent {
                            if traceIsOn {
                                Text("Trace On")
                            }
                        } label: {
                            Label("Developer Tool", systemImage: "hammer")
                        }
                    }
                } header: {
                    Text("Developer")
                }

                Section {
                    LabeledContent("Version", value: AppVersion.current)
                        .textSelection(.enabled)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Trace.tap("Settings", "Done")
                        dismiss()
                    }
                }
            }
        }
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
        .traceScreen("Settings")
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

/// The runner's weight in their units, for calories. Clearing it turns calories off.
private struct BodyWeightRow: View {
    let unit: DistanceUnit
    @AppStorage(BodyWeight.storageKey) private var kilograms: Double = 0

    var body: some View {
        OptionalNumberField(title: unit == .miles ? "Weight (lb)" : "Weight (kg)", value: Binding(
            get: {
                guard BodyWeight.range.contains(kilograms) else { return nil }
                return unit == .miles ? kilograms / BodyWeight.kilogramsPerPound : kilograms
            },
            set: { value in
                guard let value else {
                    kilograms = 0
                    return
                }
                let typed = unit == .miles ? value * BodyWeight.kilogramsPerPound : value
                // Part way through typing, such as the 7 of 72, isn't a weight yet.
                if BodyWeight.range.contains(typed) { BodyWeight.save(typed) }
            }
        ))
        // The field reads its value when it appears, so it starts again when the units change.
        .id(unit)
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(WindRunStore(inMemory: true))
}
