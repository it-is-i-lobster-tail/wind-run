//
//  TermsView.swift
//  Wind Run
//

import SwiftUI

/// Wind Run's terms, shown before coach mode starts when they haven't been accepted.
///
/// Placeholder wording: the final text is waiting for legal review.
struct TermsView: View {
    let onAccept: () -> Void

    @State private var confirmsHealthy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Before the coach plans your weeks")
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                    Text("Wind Run is a running app, not a medical device. The coach builds training plans from what you tell it and from your runs. It doesn't diagnose, treat or check anything about your health.")
                    Text("You decide how hard to go. If something hurts, you feel unwell, or a run doesn't feel right, stop and get advice from a professional.")
                    Text("By using coach mode you confirm you're healthy enough to run and that you take part at your own risk.")
                }
                .foregroundStyle(.secondary)

                Toggle(isOn: $confirmsHealthy) {
                    Text("I'm healthy enough to run, and I accept Wind Run's terms.")
                }
                .padding()
                .windRunGlassCard()

                Button {
                    onAccept()
                } label: {
                    Text("Accept and continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LayoutMetrics.compactSpacing)
                }
                .buttonStyle(.glassProminent)
                .disabled(!confirmsHealthy)

                Text("Draft terms, pending legal review.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
}

#Preview("Terms") {
    TermsView(onAccept: {})
}
