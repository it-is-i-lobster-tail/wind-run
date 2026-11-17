//
//  CoachSessionBanner.swift
//  Wind Run
//

import SwiftUI

/// The coach's planned run: its name, what it asks for, and the stop line. Every planned run screen shows
/// the stop line (AD-19b).
struct CoachSessionBanner: View {
    let target: CoachWorkoutTarget
    let unit: DistanceUnit
    /// The coach's stop line for this run, with its heat part when it applies.
    var stopLine: String = SafetyText.stopLine
    /// The name and what it asks for on one line, for the run screen, where the numbers need the room.
    var compact = false

    var body: some View {
        let summary = CoachFormat.targetSummary(target, unit: unit)
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            if compact {
                Text(summary.isEmpty ? target.title : "\(target.title) · \(summary)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(2)
            } else {
                Text(target.title)
                    .font(.headline)
                if !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(stopLine)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
        .accessibilityElement(children: .combine)
    }
}
