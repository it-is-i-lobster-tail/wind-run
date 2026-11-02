//
//  HeartRateLiveActivity.swift
//  Wind Run Live Activity
//

import ActivityKit
import SwiftUI
import WidgetKit

/// A run's heart rate on the Lock Screen and in the Dynamic Island: the current reading and
/// the last five minutes. Nothing else, so it stays out of the way.
struct HeartRateLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeartRateActivityAttributes.self) { context in
            LockScreenView(state: context.state, runStart: context.attributes.startDate)
                .opacity(context.isStale ? 0.6 : 1)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HeartLabel()
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BeatsPerMinuteText(context.state.beatsPerMinute, size: 28)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HeartRateChart(window: context.state.window, runStart: context.attributes.startDate)
                        .frame(height: 44)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text(HeartRateText.value(context.state.beatsPerMinute))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HeartRateText.spoken(context.state.beatsPerMinute))
            } compactTrailing: {
                HeartRateChart(window: context.state.window, runStart: context.attributes.startDate, lineWidth: 1.5)
                    .frame(width: 36, height: 16)
            } minimal: {
                Text(HeartRateText.value(context.state.beatsPerMinute))
                    .monospacedDigit()
                    .foregroundStyle(.red)
                    .accessibilityLabel(HeartRateText.spoken(context.state.beatsPerMinute))
            }
            .keylineTint(.red)
        }
    }
}

private struct LockScreenView: View {
    let state: HeartRateActivityAttributes.ContentState
    let runStart: Date

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HeartLabel()
                BeatsPerMinuteText(state.beatsPerMinute, size: 40)
            }
            HeartRateChart(window: state.window, runStart: runStart)
                .frame(height: 64)
        }
        .padding()
    }
}

private struct HeartLabel: View {
    var body: some View {
        Label {
            Text("Heart rate")
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
        }
        .font(.subheadline)
    }
}

/// "142 bpm", with the number large and the unit small.
private struct BeatsPerMinuteText: View {
    let beatsPerMinute: Int?
    let size: CGFloat

    init(_ beatsPerMinute: Int?, size: CGFloat) {
        self.beatsPerMinute = beatsPerMinute
        self.size = size
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(HeartRateText.value(beatsPerMinute))
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text("bpm")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HeartRateText.spoken(beatsPerMinute))
    }
}

private enum HeartRateText {
    /// The reading, or a dash until there is one.
    static func value(_ beatsPerMinute: Int?) -> String {
        beatsPerMinute.map(String.init) ?? "––"
    }

    static func spoken(_ beatsPerMinute: Int?) -> String {
        guard let beatsPerMinute else { return String(localized: "Heart rate, no reading yet") }
        return String(localized: "Heart rate \(beatsPerMinute) beats per minute")
    }
}

// MARK: - Previews

extension HeartRateActivityAttributes {
    fileprivate static let preview = HeartRateActivityAttributes(startDate: .now)
}

extension HeartRateActivityAttributes.ContentState {
    fileprivate static let running: Self = {
        let end = Date.now
        let readings = (0..<60).map { step in
            let seconds = Double(step) * 5
            return HeartRateReading(
                date: end.addingTimeInterval(-HeartRateWindow.duration + seconds + 5),
                beatsPerMinute: 140 + 12 * sin(seconds / 40) + seconds / 30
            )
        }
        return Self(beatsPerMinute: 152, window: HeartRateWindow(readings: readings, end: end))
    }()

    fileprivate static let waiting = Self(beatsPerMinute: nil, window: HeartRateWindow(end: .now))
}

#Preview("Lock Screen", as: .content, using: HeartRateActivityAttributes.preview) {
    HeartRateLiveActivity()
} contentStates: {
    HeartRateActivityAttributes.ContentState.running
    HeartRateActivityAttributes.ContentState.waiting
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: HeartRateActivityAttributes.preview) {
    HeartRateLiveActivity()
} contentStates: {
    HeartRateActivityAttributes.ContentState.running
}

#Preview("Compact", as: .dynamicIsland(.compact), using: HeartRateActivityAttributes.preview) {
    HeartRateLiveActivity()
} contentStates: {
    HeartRateActivityAttributes.ContentState.running
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: HeartRateActivityAttributes.preview) {
    HeartRateLiveActivity()
} contentStates: {
    HeartRateActivityAttributes.ContentState.running
}
