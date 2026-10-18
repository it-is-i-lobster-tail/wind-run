//
//  RunRow.swift
//  Wind Run
//

import SwiftData
import SwiftUI

struct RunRow: View {
    let run: Run
    let unit: DistanceUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.startDate, format: .dateTime.weekday(.wide).hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(RunFormat.distance(run.distanceMeters, unit: unit))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(RunFormat.duration(run.activeDuration()))
                    .font(.body.monospacedDigit())
                Text(RunFormat.pace(run.pace(), unit: unit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .windRunGlassCard(interactive: true)
        .accessibilityElement(children: .combine)
    }
}
