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
                NavigationLink("Offline area data") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let url = Bundle.main.url(forResource: "OfflineAreasNotices", withExtension: "txt"),
                               let credits = try? String(contentsOf: url, encoding: .utf8) {
                                Text(credits).textSelection(.enabled)
                            }
                            Link("OpenStreetMap copyright and license", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                        }.padding()
                    }.navigationTitle("Offline area data")
                }
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
