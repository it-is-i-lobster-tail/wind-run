//
//  HeartRateLiveActivity.swift
//  Wind Run Live Activity
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// A run on the Lock Screen and in the Dynamic Island: the runner's display screen, the same six readings as
/// the run screen in the app and on the Watch, and the step under way in a structured run, with a Next button
/// on a step that ends on a tap, and Pause or Resume. The compact Dynamic Island keeps to heart rate and the
/// run's time, or the step. A finished run stays a while with its final numbers.
struct HeartRateLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeartRateActivityAttributes.self) { context in
            LockScreenView(state: context.state, attributes: context.attributes)
                .opacity(context.isStale ? 0.6 : 1)
        } dynamicIsland: { context in
            let state = context.state
            let attributes = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: state, attributes: attributes)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(state: state, attributes: attributes)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: state, attributes: attributes)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                IslandCompactLeading(state: state, attributes: attributes)
            } compactTrailing: {
                IslandCompactTrailing(state: state, attributes: attributes)
            } minimal: {
                IslandMinimal(state: state, attributes: attributes)
            }
            .keylineTint(attributes.showsHeartRate ? .red : StepAccent.island)
        }
    }
}

// MARK: - Dynamic Island

/// The expanded island's leading side: the display screen's first headline, or the step, or heart rate.
private struct IslandExpandedLeading: View {
    let state: HeartRateActivityAttributes.ContentState
    let attributes: HeartRateActivityAttributes

    var body: some View {
        if let display = state.display {
            // Captions a size up from the island's tiles, which use DisplaySizes.island's 8.
            DisplayHeadline(reading: display.primary, size: DisplaySizes.island.primarySize, labelSize: 9)
        } else if let step = state.step {
            StepLabel(step: step)
        } else {
            HeartLabel()
        }
    }
}

/// The expanded island's trailing side: the display screen's second headline, or the step's clock, or heart rate.
private struct IslandExpandedTrailing: View {
    let state: HeartRateActivityAttributes.ContentState
    let attributes: HeartRateActivityAttributes

    var body: some View {
        if let display = state.display {
            // Captions a size up from the island's tiles, which use DisplaySizes.island's 8.
            DisplayHeadline(reading: display.secondary, size: DisplaySizes.island.secondarySize, labelSize: 9)
        } else if let step = state.step, !step.isFinished {
            StepClock(step: step)
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.trailing)
        } else {
            BeatsPerMinuteText(state.beatsPerMinute, size: 28)
        }
    }
}

/// The expanded island's bottom: the step and the display screen's tiles, or the heart rate graph, then the
/// buttons, or that the run was saved.
private struct IslandExpandedBottom: View {
    let state: HeartRateActivityAttributes.ContentState
    let attributes: HeartRateActivityAttributes

    var body: some View {
        let step = state.step
        VStack(spacing: 8) {
            if let display = state.display {
                if let step {
                    HStack {
                        StepLabel(step: step)
                        Spacer(minLength: 8)
                        StepClock(step: step)
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                }
                DisplayTileRow(tiles: display.tiles, style: DisplaySizes.island)
                    .tint(StepAccent.island)
            } else if attributes.showsHeartRate {
                HStack(spacing: 8) {
                    if step != nil {
                        BeatsPerMinuteText(state.beatsPerMinute, size: 20)
                    }
                    HeartRateChart(window: state.window, runStart: attributes.startDate)
                        .frame(height: step == nil ? 44 : 32)
                }
            }
            if state.runIsFinished {
                FinishedLabel()
            } else {
                HStack(spacing: 8) {
                    if let step, let title = step.nextTitle {
                        NextStepButton(title: title, accent: StepAccent.island)
                    }
                    PauseResumeButton(isPaused: state.runIsPaused, accent: StepAccent.island, showsTitle: step?.nextTitle == nil)
                }
            }
        }
    }
}

/// The compact island's leading side: heart rate, or the step's name, or a runner.
private struct IslandCompactLeading: View {
    let state: HeartRateActivityAttributes.ContentState
    let attributes: HeartRateActivityAttributes

    var body: some View {
        if attributes.showsHeartRate {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(HeartRateText.value(state.beatsPerMinute))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HeartRateText.spoken(state.beatsPerMinute))
        } else if let step = state.step {
            Text(step.name)
                .foregroundStyle(StepAccent.island)
                .lineLimit(1)
        } else {
            Image(systemName: "figure.run")
                .foregroundStyle(StepAccent.island)
                .accessibilityLabel("Run")
        }
    }
}

/// The compact island's trailing side: the step's clock while a step is under way, else the run's time,
/// which runners check most; heart rate is already on the leading side. Once every step is done there's no
/// step clock left, so the run's time comes back rather than an empty slot.
private struct IslandCompactTrailing: View {
    let state: HeartRateActivityAttributes.ContentState
    let attributes: HeartRateActivityAttributes

    var body: some View {
        if let step = state.step, !step.isFinished, !state.runIsFinished {
            StepClock(step: step)
                .monospacedDigit()
                .frame(maxWidth: 56)
        } else if let clock = state.display?.compactClock {
            Group {
                switch clock {
                case .counting(let start): Text(start, style: .timer)
                case .fixed(let value): Text(value)
                }
            }
            .monospacedDigit()
            .frame(maxWidth: 56)
        } else if attributes.showsHeartRate {
            HeartRateChart(window: state.window, runStart: attributes.startDate, lineWidth: 1.5)
                .frame(width: 36, height: 16)
        }
    }
}

/// The minimal island: heart rate, or what kind of step it is, or a runner.
private struct IslandMinimal: View {
    let state: HeartRateActivityAttributes.ContentState
    let attributes: HeartRateActivityAttributes

    var body: some View {
        if let step = state.step, !attributes.showsHeartRate {
            Image(systemName: step.nextTitle == nil ? "repeat" : "hand.tap")
                .foregroundStyle(StepAccent.island)
                .accessibilityLabel(step.name)
        } else if !attributes.showsHeartRate {
            Image(systemName: "figure.run")
                .foregroundStyle(StepAccent.island)
                .accessibilityLabel("Run")
        } else {
            Text(HeartRateText.value(state.beatsPerMinute))
                .monospacedDigit()
                .foregroundStyle(.red)
                .accessibilityLabel(HeartRateText.spoken(state.beatsPerMinute))
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    @Environment(\.colorScheme) private var colorScheme

    let state: HeartRateActivityAttributes.ContentState
    let attributes: HeartRateActivityAttributes

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let step = state.step {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        StepLabel(step: step)
                        StepClock(step: step)
                            .font(.system(size: state.display == nil ? 34 : 22, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                    Spacer(minLength: 0)
                    if let title = step.nextTitle {
                        NextStepButton(title: title, accent: StepAccent.color(for: colorScheme))
                            .fixedSize()
                    }
                }
            }
            if let display = state.display {
                // The runner's display screen: the two headlines side by side, the grid in one row under them,
                // with Pause or Resume beside the headlines, or that the run was saved.
                let style = state.step == nil ? DisplaySizes.lockScreen : DisplaySizes.lockScreenWithStep
                HStack(alignment: .center, spacing: 12) {
                    DisplayHeadline(reading: display.primary, size: style.primarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
                        .frame(maxWidth: .infinity)
                    DisplayHeadline(reading: display.secondary, size: style.secondarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
                        .frame(maxWidth: .infinity)
                    if state.runIsFinished {
                        FinishedLabel()
                    } else {
                        VStack(spacing: 4) {
                            if state.runIsPaused {
                                Text("PAUSED")
                                    .font(.caption2.weight(.bold))
                                    .tracking(0.8)
                                    .foregroundStyle(StepAccent.color(for: colorScheme))
                            }
                            PauseResumeButton(isPaused: state.runIsPaused, accent: StepAccent.color(for: colorScheme), showsTitle: false)
                        }
                    }
                }
                DisplayTileRow(tiles: display.tiles, style: style)
            } else if attributes.showsHeartRate {
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
        .tint(StepAccent.color(for: colorScheme))
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
        switch step.clock {
        case .countdown(let interval):
            Text(timerInterval: interval, countsDown: true)
        case .text(let detail):
            Text(detail)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .countUp(let start):
            Text(start, style: .timer)
        case .none:
            EmptyView()
        }
    }
}

/// Pauses the run, or starts it again, in the app.
private struct PauseResumeButton: View {
    let isPaused: Bool
    let accent: Color
    /// With room, "Pause" or "Resume" beside the symbol; otherwise the symbol alone.
    let showsTitle: Bool

    var body: some View {
        Group {
            if isPaused {
                Button(intent: ResumeRunIntent()) { label("Resume", symbol: "play.fill") }
            } else {
                Button(intent: PauseRunIntent()) { label("Pause", symbol: "pause.fill") }
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(isPaused ? accent : .gray)
    }

    @ViewBuilder private func label(_ title: String, symbol: String) -> some View {
        if showsTitle {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(isPaused ? StepAccent.text(on: accent) : .white)
                .frame(maxWidth: .infinity)
        } else {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(isPaused ? StepAccent.text(on: accent) : .white)
                .accessibilityLabel(title)
        }
    }
}

/// A finished run, kept on the Lock Screen for a while: it was saved.
private struct FinishedLabel: View {
    var body: some View {
        Label("Saved", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
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

    /// The standard display screen mid-run.
    fileprivate static let displayed: Self = {
        var state = running
        state.display = DisplayScreenReadings(
            primary: DisplayReading(metric: .elapsed, value: "32:48", label: "ELAPSED", clockStart: .now.addingTimeInterval(-1_968), spoken: "Elapsed time, 32:48"),
            secondary: DisplayReading(metric: .distance, value: "6.40", unit: "km", label: "DISTANCE", spoken: "Distance, 6.40 km"),
            tiles: [
                DisplayReading(metric: .currentPace, value: "5:12", unit: "/km", label: "CURRENT PACE", spoken: "Current pace, 5:12 per km"),
                DisplayReading(metric: .heartRate, value: "148", unit: "bpm", label: "HEART RATE", symbol: "heart.fill", tint: .heartRate, spoken: "Heart rate, 148 beats per minute"),
                DisplayReading(metric: .heightFromStart, value: "43", unit: "m", label: "BELOW START", symbol: "arrow.down", tint: .accent, spoken: "43 m below the start"),
                DisplayReading(metric: .cadence, value: "172", unit: "spm", label: "CADENCE", spoken: "Cadence, 172 steps a minute"),
            ]
        )
        return state
    }()

    fileprivate static let displayedOpenStep: Self = {
        var state = displayed
        state.step = RunStepState(name: "Recover", number: 3, count: 12, startDate: .now.addingTimeInterval(-40), nextTitle: "Next step", isFinished: false)
        return state
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
    HeartRateActivityAttributes.ContentState.displayed
    HeartRateActivityAttributes.ContentState.displayedOpenStep
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
    HeartRateActivityAttributes.ContentState.displayed
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
