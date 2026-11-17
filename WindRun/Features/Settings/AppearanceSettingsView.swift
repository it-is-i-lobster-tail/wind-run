//
//  AppearanceSettingsView.swift
//  Wind Run
//
//  Light, dark, or following the iPhone. The watch is always dark.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { appearance in
                        Text(appearance.name).tag(appearance)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("System follows your iPhone's Light or Dark setting. Apple Watch is always dark.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Appearance")
    }
}

#Preview("Appearance") {
    NavigationStack { AppearanceSettingsView() }
}
