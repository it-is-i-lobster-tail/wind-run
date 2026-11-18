//
//  SettingsView.swift
//  Wind Run
//
//  The top of Settings: one row per group, each opening its own page, laid out like PowerJack's.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Trace logging's switch, kept by `TraceFiles`, so the row shows it's on.
    @AppStorage(Trace.storageKey) private var traceIsOn = false

    @State private var path: [SettingsPage]

    init() {
        #if DEBUG
        _path = State(initialValue: SettingsDemo.path)
        #else
        _path = State(initialValue: [])
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    NavigationLink(value: SettingsPage.personalization) {
                        SettingsGroupLabel(page: .personalization)
                    }
                    NavigationLink(value: SettingsPage.healthAndMotion) {
                        SettingsGroupLabel(page: .healthAndMotion)
                    }
                    NavigationLink(value: SettingsPage.appearance) {
                        SettingsGroupLabel(page: .appearance)
                    }
                    NavigationLink(value: SettingsPage.yourData) {
                        SettingsGroupLabel(page: .yourData)
                    }
                }

                Section {
                    NavigationLink(value: SettingsPage.legal) {
                        SettingsGroupLabel(page: .legal)
                    }
                }

                Section {
                    NavigationLink(value: SettingsPage.developerTool) {
                        // It stays on across launches, so a runner who turned it on for a report can see it is.
                        LabeledContent {
                            if traceIsOn {
                                Text("Trace On")
                            }
                        } label: {
                            SettingsGroupLabel(page: .developerTool)
                        }
                    }
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
            .navigationDestination(for: SettingsPage.self) { page in
                page.destination
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Trace.tap("Settings", "Done")
                        dismiss()
                    }
                }
            }
        }
        // A sheet doesn't take the app's soft edge, so it sets its own.
        .scrollEdgeEffectStyle(.soft, for: .all)
        .traceScreen("Settings")
    }
}

/// The pages Settings can open. The top page lists the groups; Legal opens its two documents.
enum SettingsPage: String, Hashable, CaseIterable {
    case personalization
    case healthAndMotion = "health"
    case appearance
    case yourData = "data"
    case legal
    case privacyPolicy = "privacy"
    case termsAndConditions = "terms"
    case developerTool = "developer"

    var title: LocalizedStringKey {
        switch self {
        case .personalization: "Personalization"
        case .healthAndMotion: "Health & Motion"
        case .appearance: "Appearance"
        case .yourData: "Your Data"
        case .legal: "Legal"
        case .privacyPolicy: "Privacy Policy"
        case .termsAndConditions: "Terms and Conditions"
        case .developerTool: "Developer Tool"
        }
    }

    var systemImage: String {
        switch self {
        case .personalization: "slider.horizontal.3"
        case .healthAndMotion: "heart"
        case .appearance: "circle.lefthalf.filled"
        case .yourData: "externaldrive"
        case .legal: "doc.text"
        case .privacyPolicy: "hand.raised"
        case .termsAndConditions: "doc.text"
        case .developerTool: "hammer"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .personalization: PersonalizationSettingsView()
        case .healthAndMotion: HealthAndMotionSettingsView()
        case .appearance: AppearanceSettingsView()
        case .yourData: YourDataSettingsView()
        case .legal: LegalSettingsView()
        case .privacyPolicy: LegalDocumentView(document: .privacyPolicy)
        case .termsAndConditions: LegalDocumentView(document: .termsAndConditions)
        case .developerTool: DeveloperToolView()
        }
    }
}

/// A row on the top Settings page: just the group's name, so the list reads at a glance.
struct SettingsGroupLabel: View {
    let page: SettingsPage

    var body: some View {
        Label {
            Text(page.title)
        } icon: {
            Image(systemName: page.systemImage)
                .foregroundStyle(.tint)
        }
    }
}

/// A setting with a short line underneath saying what it does.
struct SettingsRowLabel<Icon: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder let icon: Icon

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            icon
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(WindRunStore(inMemory: true))
}
