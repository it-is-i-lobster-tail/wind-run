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
            Text(CoachSafety.stopLine)
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

/// Safety text the coach shows. The engine owns the wording; these match it until it's wired in.
enum CoachSafety {
    /// Shown on every planned run.
    static let stopLine = "Stop if you feel chest pain or pressure, faint, dizzy or very short of breath. If pain builds or makes you limp, stop and walk home, then tap Report injury."
}
