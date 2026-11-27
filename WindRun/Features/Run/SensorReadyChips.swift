//
//  SensorReadyChips.swift
//  Wind Run
//

import SwiftUI

/// Small chips under the start buttons saying GPS, heart rate and steps are ready, and one line under them
/// when something needs fixing before the run.
///
/// They come from a light live check while the Run tab is on screen, which stops after two minutes to save
/// battery; tapping a chip checks again. With everything fine they stay small and quiet.
struct SensorReadyChips: View {
    let check: SensorCheck
    /// Opens Check Sensors.
    let openCheck: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let chips = check.chips(at: context.date)
            let problem = check.readyProblem(at: context.date)
            VStack(spacing: LayoutMetrics.compactSpacing) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button {
                            Trace.tap("Run", "Sensor chip", ["chip": chip.id.rawValue, "state": chip.state.rawValue])
                            check.start(.ready)
                        } label: {
                            ChipLabel(chip: chip)
                        }
                        .buttonStyle(.plain)
                        .opacity(check.isRunning ? 1 : 0.6)
                        .accessibilityHint(check.isRunning ? "Checking now" : "Checks again")
                    }
                }
                if let problem {
                    ProblemLine(row: problem, openCheck: openCheck)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: problem?.id)
        }
    }
}

private struct ChipLabel: View {
    let chip: SensorChip

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(SensorStatusDot(state: chip.state).color)
                .frame(width: 8, height: 8)
            if chip.showsHeart {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Heart rate")
            }
            Text(chip.text)
                .contentTransition(.numericText())
        }
        .font(.caption.weight(.medium).monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// "No heart rate yet. Put both AirPods in… Check Sensors"
private struct ProblemLine: View {
    let row: SensorRow
    let openCheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Text(row.title + ".").fontWeight(.semibold)) \(row.detail)")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Button("Check Sensors") {
                Trace.tap("Run", "Check Sensors", ["row": row.id.rawValue])
                openCheck()
            }
            .font(.footnote.weight(.semibold))
            .tint(.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: LayoutMetrics.curvedCornerRadius))
    }
}

/// Opens Check Sensors from the Run tab or a run's page.
struct SensorCheckRoute: Hashable {}
