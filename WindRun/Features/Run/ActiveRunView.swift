//
//  ActiveRunView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The screen you look at mid-run: big numbers and very little else.
struct ActiveRunView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let recorder: RunRecorder

    /// The question on screen: discard, finish, or finish a run that looks started by mistake.
    @State private var confirmation = Confirmation.discard
    @State private var isConfirming = false
    /// Set on Finish: the run's summary takes over this screen until Done.
    @State private var isShowingSummary = false

    var body: some View {
        if isShowingSummary, let run = recorder.run, run.status == .complete {
            NavigationStack {
                RunDetailView(run: run, done: { dismiss() })
            }
            .transition(reduceMotion ? .opacity : .move(edge: .bottom))
        } else if let run = recorder.run {
            NavigationStack {
                runScreen(for: run)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar(for: run) }
            }
        }
    }

    private func runScreen(for run: Run) -> some View {
        // Ticks as each second of running time turns over, so the clock keeps step with the Lock Screen
        // and the Watch, which count from the same start.
        TimelineView(.periodic(from: run.clockStart(), by: 1)) { context in
            let notices = notices(for: run, at: context.date)
            // Fits the screen when it can, with the numbers in the middle. A coach session with steps
            // on a small phone or at a large text size scrolls instead, so nothing is squeezed.
            ViewThatFits(in: .vertical) {
                content(for: run, notices: notices, at: context.date, fills: true)
                ScrollView {
                    content(for: run, notices: notices, at: context.date, fills: false)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .animation(.snappy, value: notices)
            .sensoryFeedback(.warning, trigger: notices.contains(where: \.meansNoDistance)) { _, now in now }
            .onChange(of: notices, initial: true) { _, now in
                Trace.changed("Active run", "Notices", to: now.isEmpty ? "none" : now.map(\.rawValue).joined(separator: ","))
            }
        }
        // The controls stay put at the bottom, whatever the rest of the screen holds.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls(for: run)
        }
        .traceScreen("Active run")
        .confirmationDialog(confirmation.title, isPresented: $isConfirming, titleVisibility: .visible) {
            confirmationActions(for: run)
        } message: {
            if let message = confirmation.message(for: run, unit: unit) {
                Text(message)
            }
        }
    }

    /// The mute button on the left and a "…" menu on the right, as ordinary navigation bar buttons, so they
    /// get the system's glass. Discard and Finish live in the menu, out of the way of Pause and Resume.
    @ToolbarContentBuilder
    private func toolbar(for run: Run) -> some ToolbarContent {
        if recorder.speaksAloud {
            ToolbarItem(placement: .topBarLeading) {
                Button(
                    recorder.isVoiceMuted ? "Unmute voice" : "Mute voice",
                    systemImage: recorder.isVoiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                ) {
                    Trace.tap("Active run", recorder.isVoiceMuted ? "Unmute voice" : "Mute voice")
                    recorder.setVoiceMuted(!recorder.isVoiceMuted)
                }
                .labelStyle(.iconOnly)
                .accessibilityHint(recorder.isVoiceMuted ? "Call-outs are muted for this run." : "Mutes call-outs for this run.")
                .sensoryFeedback(.selection, trigger: recorder.isVoiceMuted)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("More", systemImage: "ellipsis") {
                // Finishing can't be undone, so it asks first.
                Button("Finish run", systemImage: "flag.checkered") {
                    Trace.tap("Active run", "Menu: Finish")
                    ask(Self.looksStartedByMistake(run) ? .finishShort : .finish)
                }
                Button("Discard run", systemImage: "trash", role: .destructive) {
                    Trace.tap("Active run", "Menu: Discard")
                    ask(.discard)
                }
            }
            .accessibilityLabel("More")
        }
    }

    private func content(for run: Run, notices: [RunNotice], at date: Date, fills: Bool) -> some View {
        VStack(spacing: LayoutMetrics.sectionSpacing) {
            if run.status == .paused {
                PausedBadge(isAutoPaused: recorder.isAutoPaused)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
            }
            ForEach(notices) { notice in
                NoticeRow(notice: notice)
            }
            if let workout = run.coachWorkout {
                CoachSessionBanner(target: workout.target, unit: unit, compact: true)
            }

            if fills { Spacer(minLength: 0) }

            VStack(spacing: LayoutMetrics.sectionSpacing * 1.5) {
                // The runner's display screen, the same six readings as the Watch and the Lock Screen.
                if let snapshot = recorder.snapshot(at: date, unit: unit) {
                    RunDisplayScreenView(readings: recorder.displayScreen.readings(snapshot))
                }
                if let steps = recorder.steps {
                    StepPanel(steps: steps, elapsed: run.activeDuration(at: date), meters: run.distanceMeters, unit: unit) {
                        Trace.tap("Active run", "Step button", ["step": steps.index + 1])
                        recorder.nextStep()
                    }
                }
            }

            if fills { Spacer(minLength: 0) }
        }
        .padding([.horizontal, .top])
        .animation(.snappy, value: run.status)
    }

    /// What the screen has to say beside the numbers, most important first.
    private func notices(for run: Run, at date: Date) -> [RunNotice] {
        Self.notices(
            locationDenied: recorder.locationDenied,
            locationApproximate: recorder.locationApproximate,
            status: run.status,
            gps: recorder.gpsSignal(at: date),
            heartRateStopped: recorder.heartRateStopped,
            goalReached: recorder.goalReached
        )
    }

    /// The notices, most important first: location off, then Precise Location off, then GPS while running,
    /// with a heart rate that stopped and a goal reached after any of them. `gps` is only read while running
    /// with location on.
    static func notices(
        locationDenied: Bool,
        locationApproximate: Bool,
        status: RunStatus,
        gps: @autoclosure () -> GPSSignal,
        heartRateStopped: Bool,
        goalReached: Bool
    ) -> [RunNotice] {
        var notices: [RunNotice] = []
        if locationDenied {
            notices.append(.locationOff)
        } else if locationApproximate {
            notices.append(.preciseLocationOff)
        } else if status == .active {
            switch gps() {
            case .searching: notices.append(.findingGPS)
            case .weak: notices.append(.weakGPS)
            case .good: break
            }
        }
        if heartRateStopped {
            notices.append(.heartRateStopped)
        }
        if goalReached {
            notices.append(.goalReached)
        }
        return notices
    }

    private func controls(for run: Run) -> some View {
        GlassEffectContainer(spacing: LayoutMetrics.sectionSpacing) {
            if run.status == .paused {
                RoundControl(title: "Resume", systemImage: "play.fill", prominent: true) {
                    recorder.resume()
                }
            } else {
                RoundControl(title: "Pause", systemImage: "pause.fill", prominent: true) {
                    recorder.pause()
                }
            }
        }
        .animation(.snappy, value: run.status)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, LayoutMetrics.compactSpacing)
        .padding(.bottom)
    }

    private func ask(_ question: Confirmation) {
        confirmation = question
        isConfirming = true
    }

    @ViewBuilder
    private func confirmationActions(for run: Run) -> some View {
        switch confirmation {
        case .discard:
            Button("Discard run", role: .destructive) {
                Trace.tap("Active run", "Discard this run?: Discard run")
                discard()
            }
        case .finish:
            Button("Finish run") {
                Trace.tap("Active run", "Finish this run?: Finish run")
                finish()
            }
            Button("Not yet", role: .cancel) {
                Trace.tap("Active run", "Finish this run?: Not yet")
            }
        case .finishShort:
            Button("Discard run", role: .destructive) {
                Trace.tap("Active run", "Save this short run?: Discard run", Self.shortRunDetails(run))
                discard()
            }
            Button("Save run") {
                Trace.tap("Active run", "Save this short run?: Save run", Self.shortRunDetails(run))
                finish()
            }
            Button("Not yet", role: .cancel) {
                Trace.tap("Active run", "Save this short run?: Not yet")
            }
        }
    }

    private func discard() {
        recorder.discard()
        dismiss()
    }

    private func finish() {
        recorder.finish()
        withAnimation(.snappy) { isShowingSummary = true }
    }

    /// Under 30 seconds of running, or a few minutes that barely moved: most likely a tap by mistake, which
    /// would otherwise land in history, Health and the coach's week.
    static func looksStartedByMistake(_ run: Run, at date: Date = .now) -> Bool {
        let active = run.activeDuration(at: date)
        return active < 30 || (run.distanceMeters < 50 && active < 5 * 60)
    }

    private static func shortRunDetails(_ run: Run) -> KeyValuePairs<String, Any> {
        ["seconds": Int(run.activeDuration()), "meters": Int(run.distanceMeters)]
    }

    /// The questions the run screen asks.
    enum Confirmation {
        case discard
        case finish
        case finishShort

        var title: String {
            switch self {
            case .discard: "Discard this run?"
            case .finish: "Finish this run?"
            case .finishShort: "Save this short run?"
            }
        }

        func message(for run: Run, unit: DistanceUnit) -> String? {
            switch self {
            case .discard: nil
            case .finish: "A finished run can't be carried on."
            case .finishShort:
                "It's \(RunFormat.distance(run.distanceMeters, unit: unit)) in \(RunFormat.duration(run.activeDuration())), so it may have started by mistake."
            }
        }
    }
}

/// Something the run screen says beside the numbers.
enum RunNotice: String, Identifiable, Equatable {
    case locationOff
    case preciseLocationOff
    case findingGPS
    case weakGPS
    case heartRateStopped
    case goalReached

    var id: Self { self }

    var text: String {
        switch self {
        case .locationOff: "Location is off, so this run can't measure distance."
        case .preciseLocationOff: "Precise Location is off, so this run can't measure distance."
        case .findingGPS: "Finding GPS…"
        case .weakGPS: "GPS is weak here, so distance may come up short."
        case .heartRateStopped: "Heart rate stopped. Another workout app may have taken over."
        case .goalReached: "Goal reached. Finish when you're ready."
        }
    }

    var symbol: String {
        switch self {
        case .locationOff, .preciseLocationOff: "location.slash.fill"
        case .findingGPS, .weakGPS: "location"
        case .heartRateStopped: "heart.slash"
        case .goalReached: "checkmark.circle.fill"
        }
    }

    /// Distance can't be measured at all this run until it's fixed in Settings.
    var meansNoDistance: Bool {
        self == .locationOff || self == .preciseLocationOff
    }
}

/// A notice as a glass capsule: a warning tint for what needs fixing, with a way to fix it.
private struct NoticeRow: View {
    let notice: RunNotice

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: notice == .findingGPS)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(notice.meansNoDistance ? .subheadline.weight(.semibold) : .subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if notice.meansNoDistance, let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Turn On") {
                    Trace.tap("Active run", "Turn On location", ["notice": notice.rawValue])
                    openURL(settings)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .foregroundStyle(.black)
                .accessibilityHint("Opens Wind Run's settings, where Location can be turned on")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(background), in: .rect(cornerRadius: LayoutMetrics.curvedCornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch notice {
        case .locationOff, .preciseLocationOff, .weakGPS, .heartRateStopped: .orange
        case .findingGPS: .secondary
        case .goalReached: .accentColor
        }
    }

    private var background: Color {
        notice.meansNoDistance ? .orange.opacity(0.25) : .clear
    }
}

/// "Paused" or "Auto-paused", big and plain enough to read at a glance from arm's length.
private struct PausedBadge: View {
    let isAutoPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            Label(isAutoPaused ? "Auto-paused" : "Paused", systemImage: isAutoPaused ? "figure.stand" : "pause.fill")
                .font(.title2.weight(.bold))
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            if isAutoPaused {
                Text("Starts again when you run.")
                    .font(.subheadline.weight(.medium))
            }
        }
        .foregroundStyle(.onAccent)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: LayoutMetrics.curvedCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

/// The runner's display screen on the iPhone: the two headlines, then the 2×2 grid. The Watch and the Lock
/// Screen show the same six readings, laid out to fit.
struct RunDisplayScreenView: View {
    let readings: DisplayScreenReadings

    static let style = DisplaySizes.iPhone

    var body: some View {
        let style = Self.style
        VStack(spacing: LayoutMetrics.sectionSpacing) {
            DisplayHeadline(reading: readings.primary, size: style.primarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
            DisplayHeadline(reading: readings.secondary, size: style.secondarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
            DisplayTileGrid(tiles: readings.tiles, style: style)
                .padding(.top, LayoutMetrics.compactSpacing)
        }
    }
}

/// Where the runner is in a structured run: the step, what's left of it, and a button to move on.
/// Walk breaks end on this button, so the coach gets the real break times. An open last step, such as a
/// cool down, has no button: it runs until the run is finished.
private struct StepPanel: View {
    let steps: StepTracker
    let elapsed: TimeInterval
    let meters: Double
    let unit: DistanceUnit
    let next: () -> Void

    var body: some View {
        if let step = steps.current {
            VStack(spacing: LayoutMetrics.compactSpacing) {
                Text("Step \(steps.index + 1) of \(steps.timeline.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(step.name)
                    .font(.title2.weight(.semibold))
                if let remaining = remainingText {
                    Text(remaining)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(countsDown: true))
                }
                if steps.runsUntilFinish {
                    Text("Finish the run when you're done.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button(buttonTitle(for: step), action: next)
                        .prominentAccentButton()
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            Text("All steps done")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var remainingText: String? {
        switch steps.remaining(elapsed: elapsed, meters: meters) {
        // Rounded up, as the 3-2-1 taps are, so it reads 0:00 as the step ends rather than a moment before.
        case .time(let seconds): "\(RunFormat.duration(seconds.rounded(.up))) left"
        case .distance(let left): "\(RunFormat.distance(left, unit: unit, rounding: .up)) left"
        // An open step counts up, so it says so.
        case .open: "\(RunFormat.duration(steps.elapsedInStep(elapsed))) so far"
        case nil: nil
        }
    }

    private func buttonTitle(for step: PlannedIntervalStep) -> String {
        if case .open = step.goal { return step.openStepButtonTitle }
        return "End step"
    }
}

/// A round run control with its name under it, so the symbol isn't left to explain itself.
private struct RoundControl: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    private var size: CGFloat { prominent ? 96 : 72 }

    var body: some View {
        VStack(spacing: 6) {
            Button {
                Trace.tap("Active run", title)
                action()
            } label: {
                Image(systemName: systemImage)
                    .font(prominent ? .largeTitle : .title2)
                    .foregroundStyle(prominent ? .onAccent : .primary)
                    .frame(width: size, height: size)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(
                prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: .circle
            )
            .accessibilityLabel(title)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Active run") {
    let container = WindRunSchema.makeContainer(inMemory: true)
    let recorder = RunRecorder(modelContext: container.mainContext)
    recorder.start()
    return ActiveRunView(recorder: recorder)
        .modelContainer(container)
}
