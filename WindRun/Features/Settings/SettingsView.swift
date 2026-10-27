//
//  SettingsView.swift
//  Wind Run
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WindRunStore.self) private var store
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    @State private var iCloudAvailable = true
    @State private var isSwitchingICloudSync = false
    @State private var isDeletingICloudCopy = false
    @State private var isConfirmingICloudSyncOff = false
    @State private var showsSignInNeeded = false
    @State private var showsSignedOutChoice = false
    @State private var showsICloudOffError = false

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
                    Text("Used to work out the calories each run burns. It syncs with your other settings when iCloud Sync is on.")
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
                            Image(systemName: "icloud")
                        }
                    }
                    .disabled(isSwitchingICloudSync)
                } header: {
                    Text("Your Data")
                } footer: {
                    if isDeletingICloudCopy {
                        Text("Deleting your iCloud copy…")
                    } else if store.syncsWithICloud, !iCloudAvailable {
                        Text("You're signed out of iCloud, so nothing is syncing. Sign in to iCloud in the Settings app to pick up again.")
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Turn Off iCloud Sync?", isPresented: $isConfirmingICloudSyncOff) {
            Button("Turn Off and Delete", role: .destructive, action: turnOffICloudSync)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your runs and settings stay on this iPhone, but the copy in iCloud will be deleted. A new iPhone won't get them back.")
        }
        .alert("Sign In to iCloud First", isPresented: $showsSignInNeeded) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("iCloud sync needs an iCloud account. Sign in to iCloud in the Settings app, then turn it on.")
        }
        .alert("You're Signed Out of iCloud", isPresented: $showsSignedOutChoice) {
            Button("Turn Off and Keep Copy", action: store.turnOffICloudSyncKeepingCopy)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wind Run can't reach its copy in iCloud to delete it. Sign in to iCloud and try again, or turn sync off now and leave the copy in iCloud.")
        }
        .alert("Couldn't Turn Off iCloud Sync", isPresented: $showsICloudOffError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("iCloud couldn't be reached, so nothing was deleted and sync is still on. Check your connection and try again.")
        }
        .task {
            iCloudAvailable = await store.iCloudAccountAvailable()
        }
    }

    // Turning sync off asks first, because it deletes the iCloud copy.
    private var iCloudSync: Binding<Bool> {
        Binding(
            get: { store.syncsWithICloud },
            set: { isOn in
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
                iCloudAvailable = true
            } catch {
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
                showsSignedOutChoice = true
            } catch {
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
                if BodyWeight.range.contains(typed) { kilograms = typed }
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
