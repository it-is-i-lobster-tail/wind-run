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
                NavigationLink("Offline Map Data") { OfflineMapDataView() }
            } footer: {
                Text("Wind Run's source code is public, so anyone can check these against the app.")
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Legal")
    }
}

/// Credits for the offline area data history search uses, which its licenses require.
struct OfflineMapDataView: View {
    private var credits: String? {
        Bundle.main.url(forResource: "OfflineAreasNotices", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let credits { Text(credits).textSelection(.enabled) }
                Link("OpenStreetMap Copyright and License", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Offline Map Data")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Offline Map Data")
    }
}

#Preview("Legal") {
    NavigationStack {
        LegalSettingsView()
            .navigationDestination(for: SettingsPage.self) { $0.destination }
    }
}
