//
//  LegalDocumentView.swift
//  Wind Run
//

import SwiftUI

/// One legal page, such as the privacy policy, as headed sections of plain text.
struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Last updated \(document.lastUpdated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(document.sections, id: \.self) { section in
                    VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                        Text(section.heading)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen(document.title)
    }
}

#Preview("Privacy Policy") {
    NavigationStack {
        LegalDocumentView(document: .privacyPolicy)
    }
}

#Preview("Terms") {
    NavigationStack {
        LegalDocumentView(document: .termsAndConditions)
    }
}
