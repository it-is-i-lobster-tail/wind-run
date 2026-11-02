//
//  HeartRateLiveActivity.swift
//  Wind Run Live Activity
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// A run on the Lock Screen and in the Dynamic Island: its heart rate, the current reading and the last
/// five minutes, when it measures it, and the step under way in a structured run, with a Next button on a
/// step that ends on a tap. Nothing else, so it stays out of the way.
struct HeartRateLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeartRateActivityAttributes.self) { context in
            LockScreenView(state: context.state, attributes: context.attributes)
                .opacity(context.isStale ? 0.6 : 1)
        } dynamicIsland: { context in
            let showsHeartRate = context.attributes.showsHeartRate
            let step = context.state.step
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if let step {
                            StepLabel(step: step)
                        } else {
                            HeartLabel()
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if let step {
                            StepClock(step: step)
                                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                                .multilineTextAlignment(.trailing)
                        } else {
                            BeatsPerMinuteText(context.state.beatsPerMinute, size: 28)
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if showsHeartRate {
                            HStack(spacing: 8) {
                                if step != nil {
                                    BeatsPerMinuteText(context.state.beatsPerMinute, size: 20)
                                }
                                HeartRateChart(window: context.state.window, runStart: context.attributes.startDate)
                                    .frame(height: step == nil ? 44 : 32)
                            }
                        }
                        if let step, let title = step.nextTitle {
                            NextStepButton(title: title, accent: StepAccent.island)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                if showsHeartRate {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text(HeartRateText.value(context.state.beatsPerMinute))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(HeartRateText.spoken(context.state.beatsPerMinute))
                } else if let step {
                    Text(step.name)
                        .foregroundStyle(StepAccent.island)
                        .lineLimit(1)
                }
            } compactTrailing: {
                if let step {
                    StepClock(step: step)
                        .monospacedDigit()
                        .frame(maxWidth: 56)
                } else {
                    HeartRateChart(window: context.state.window, runStart: context.attributes.startDate, lineWidth: 1.5)
                        .frame(width: 36, height: 16)
                }
            } minimal: {
                if let step, !showsHeartRate {
                    Image(systemName: step.nextTitle == nil ? "repeat" : "hand.tap")
                        .foregroundStyle(StepAccent.island)
                        .accessibilityLabel(step.name)
                } else {
                    Text(HeartRateText.value(context.state.beatsPerMinute))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                        .accessibilityLabel(HeartRateText.spoken(context.state.beatsPerMinute))
                }
            }
            .keylineTint(showsHeartRate ? .red : StepAccent.island)
        }
    }
}

private struct LockScreenView: View {
    @Environment(\.colorScheme) private var colorScheme

    let state: HeartRateActivityAttributes.ContentState
    let attributes: HeartRateActivityAttributes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let step = state.step {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        StepLabel(step: step)
                        StepClock(step: step)
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                    Spacer(minLength: 0)
                    if let title = step.nextTitle {
                        NextStepButton(title: title, accent: StepAccent.color(for: colorScheme))
                            .fixedSize()
                    }
                }
            }
            if attributes.showsHeartRate {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HeartLabel()
                        BeatsPerMinuteText(state.beatsPerMinute, size: state.step == nil ? 40 : 28)
                    }
                    HeartRateChart(window: state.window, runStart: attributes.startDate)
                        .frame(height: state.step == nil ? 64 : 40)
                }
            }
        }
        .padding()
    }
}

/// The app's teal: deep on light backgrounds, bright on dark ones and in the Dynamic Island, with black or
/// white text to match, as in the app.
private enum StepAccent {
    static let deep = Color(red: 0 / 255, green: 109 / 255, blue: 128 / 255)
    static let bright = Color(red: 46 / 255, green: 176 / 255, blue: 199 / 255)
    static let island = bright

    static func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? bright : deep
    }

    static func text(on accent: Color) -> Color {
        accent == bright ? .black : .white
    }
}

/// "Work", with where it is in the workout: "Step 3 of 12".
private struct StepLabel: View {
    let step: RunStepState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(step.name)
                .font(.headline)
                .lineLimit(1)
            if !step.isFinished {
                Text("Step \(step.number) of \(step.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The step's clock: down to the end of a timed step, up from the start of an open one, or what the app
/// last wrote, such as the distance left.
private struct StepClock: View {
    let step: RunStepState

    var body: some View {
        if let start = step.startDate, let end = step.endDate, start <= end {
            Text(timerInterval: start...end, countsDown: true)
        } else if let detail = step.detail {
            Text(detail)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if let start = step.startDate {
            Text(start, style: .timer)
        }
    }
}

/// Ends the step under way in the app, for a step that ends on a tap.
private struct NextStepButton: View {
    let title: String
    let accent: Color

    var body: some View {
        Button(intent: NextStepIntent()) {
            Label(title, systemImage: "forward.end.fill")
                .font(.headline)
                .foregroundStyle(StepAccent.text(on: accent))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
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
    fileprivate static let preview = HeartRateActivityAttributes(startDate: .now, showsHeartRate: true)
    fileprivate static let stepsOnly = HeartRateActivityAttributes(startDate: .now, showsHeartRate: false)
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

    fileprivate static let openStep = Self(
        beatsPerMinute: nil,
        window: HeartRateWindow(end: .now),
        step: RunStepState(name: "Warm up", number: 1, count: 8, startDate: .now.addingTimeInterval(-95), nextTitle: "Next step", isFinished: false)
    )

    fileprivate static let timedStep: Self = {
        var state = running
        state.step = RunStepState(name: "Work", number: 4, count: 8, startDate: .now.addingTimeInterval(-40), endDate: .now.addingTimeInterval(140), isFinished: false)
        return state
    }()
}

#Preview("Lock Screen", as: .content, using: HeartRateActivityAttributes.preview) {
    HeartRateLiveActivity()
} contentStates: {
    HeartRateActivityAttributes.ContentState.running
    HeartRateActivityAttributes.ContentState.waiting
    HeartRateActivityAttributes.ContentState.timedStep
}

#Preview("Lock Screen - Steps only", as: .content, using: HeartRateActivityAttributes.stepsOnly) {
    HeartRateLiveActivity()
} contentStates: {
    HeartRateActivityAttributes.ContentState.openStep
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
