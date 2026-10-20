//
//  CoachSessionBanner.swift
//  Wind Run
//

import SwiftUI

/// What a planned run asks for, shown at the top of the run screen, with the stop line every
/// planned run carries.
struct CoachSessionBanner: View {
    let target: CoachWorkoutTarget
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(target.title)
                .font(.headline)
            let summary = CoachFormat.targetSummary(target, unit: unit)
            if !summary.isEmpty {
                Text(summary)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(SafetyText.stopLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
        .accessibilityElement(children: .combine)
    }
}
