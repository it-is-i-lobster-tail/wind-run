//
//  LegalSettingsView.swift
//  Wind Run
//
//  The privacy policy and the terms.
//

import SwiftUI

struct LegalSettingsView: View {
    var body: some View {
        Form {
            Section {
                SettingsPageLink(page: .privacyPolicy)
                SettingsPageLink(page: .termsAndConditions)
            } footer: {
                Text("Wind Run's source code is public, so anyone can check these against the app.")
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Legal")
    }
}

#Preview("Legal") {
    NavigationStack {
        LegalSettingsView()
            .navigationDestination(for: SettingsPage.self) { $0.destination }
    }
}
