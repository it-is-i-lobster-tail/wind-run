//
//  RunHomeView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Two ways to start: a free run, or today's workout from the coach. Then the runs you've done.
struct RunHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false

    @Query(sort: \Run.startDateValue, order: .reverse) private var allRuns: [Run]
    @Query private var coachPlans: [CoachPlan]
    @State private var recorder: RunRecorder?
    @State private var finishedRun: Run?

    /// Switches to the Coach section, for a rest day or a paused plan.
    private let showCoach: () -> Void

    init(showCoach: @escaping () -> Void = {}) {
        self.showCoach = showCoach
    }

    private var coachPlan: CoachPlan? {
        guard TermsAcceptance.isCurrent() else { return nil }
        return coachPlans.active
    }

    private var finishedRuns: [Run] {
        allRuns.filter { $0.status == .complete }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LayoutMetrics.sectionSpacing * 2) {
                    StartButtons(today: coachToday, unit: unit, freeRun: { startRun() }, workout: { startRun($0) }, showCoach: showCoach)
                        .padding(.top, LayoutMetrics.sectionSpacing * 2)

                    history
                }
                .padding(.horizontal)
            }
            .clearsFloatingBar()
            .navigationTitle("Run")
            .navigationDestination(for: Run.self) { run in
                RunDetailView(run: run)
            }
        }
        .fullScreenCover(isPresented: isRecording, onDismiss: runFinished) {
            if let recorder {
                ActiveRunView(recorder: recorder)
            }
        }
        // The watch shows the same sessions, so they can be run from the wrist.
        .task(id: watchSessions) { SettingsSync.shared.sendCoachToday(watchSessions) }
    }

    /// Today's coach sessions as the watch gets them.
    private var watchSessions: [WatchCoachSession] {
        todaysSessions.compactMap { WatchCoachSession($0) }
    }

    @ViewBuilder
    private var history: some View {
        if finishedRuns.isEmpty {
            EmptyStateView(
                title: "No runs yet",
                systemImage: "figure.run",
                description: "Only you can see your runs."
            )
        } else {
            VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                Text("Recent")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ForEach(finishedRuns) { run in
                    NavigationLink(value: run) {
                        RunRow(run: run, unit: unit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var isRecording: Binding<Bool> {
        Binding(
            get: { recorder?.run != nil },
            set: { isPresented in
                // Dismissing can set this more than once, so keep the run from the first time.
                if !isPresented {
                    if let run = recorder?.run { finishedRun = run }
                    recorder = nil
                }
            }
        )
    }

    /// With a coach plan, a finished run counts toward the week straight away.
    private func runFinished() {
        defer { finishedRun = nil }
        guard coachPlan != nil, let run = finishedRun, run.status == .complete else { return }
        BuildRunStart.runFinished(in: modelContext)
    }

    /// Today's runs from the coach that are still to do.
    private var todaysSessions: [CoachWorkout] {
        guard let coachPlan, let state = BuildService(context: modelContext).state(of: coachPlan) else { return [] }
        return CoachToday.workouts(coachPlan, build: state, now: .now, calendar: .current)
    }

    /// What the coach has for today, or nil without a plan.
    private var coachToday: CoachToday? {
        guard let coachPlan, let state = BuildService(context: modelContext).state(of: coachPlan) else { return nil }
        return CoachToday.of(coachPlan, build: state, now: .now, calendar: .current)
    }

    /// A plain run, or the coach's session when one is given.
    private func startRun(_ workout: CoachWorkout? = nil) {
        let recorder = RunRecorder(modelContext: modelContext)
        if let workout {
            BuildRunStart.attachCues(to: recorder, for: workout)
            recorder.start(coachWorkout: workout, measuresHeartRate: measuresHeartRate)
        } else {
            recorder.start(measuresHeartRate: measuresHeartRate)
        }
        self.recorder = recorder
    }
}

/// "Free Run", and beside it today's workout from the coach when there's a plan.
private struct StartButtons: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let today: CoachToday?
    let unit: DistanceUnit
    let freeRun: () -> Void
    let workout: (CoachWorkout) -> Void
    let showCoach: () -> Void

    var body: some View {
        if let today {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: LayoutMetrics.sectionSpacing))
                : AnyLayout(HStackLayout(alignment: .top, spacing: LayoutMetrics.sectionSpacing))
            layout {
                StartBubble(
                    title: "Free Run",
                    systemImage: "figure.run",
                    caption: "Just run",
                    isProminent: true,
                    action: freeRun
                )
                coachBubble(today)
            }
            .frame(maxWidth: .infinity)
        } else {
            StartBubble(title: "Free Run", systemImage: "figure.run", size: StartBubble.soloSize, isProminent: true, action: freeRun)
        }
    }

    @ViewBuilder
    private func coachBubble(_ today: CoachToday) -> some View {
        switch today {
        case .workout(let session):
            StartBubble(
                title: "Today's Workout",
                systemImage: "flag.checkered",
                caption: session.title,
                detail: CoachFormat.targetSummary(session.target, unit: unit),
                isProminent: true
            ) { workout(session) }
        case .done(let next):
            StartBubble(title: "Done Today", systemImage: "checkmark", caption: nextCaption(next), hint: "Opens Coach", action: showCoach)
        case .rest(let next):
            StartBubble(title: "Rest Day", systemImage: "moon.zzz", caption: nextCaption(next), hint: "Opens Coach", action: showCoach)
        case .startsLater(let next):
            StartBubble(title: "Plan Starts Soon", systemImage: "calendar", caption: nextCaption(next), hint: "Opens Coach", action: showCoach)
        case .paused:
            StartBubble(title: "Plan Paused", systemImage: "pause", caption: "Restart it in Coach", hint: "Opens Coach", action: showCoach)
        }
    }

    /// "Next: Tomorrow, Long run", or a note that next week is still to be planned.
    private func nextCaption(_ next: CoachWorkout?) -> String {
        guard let next, let date = next.scheduledDate else { return "Next week's runs come soon" }
        let day = Calendar.current.isDateInTomorrow(date) ? "Tomorrow" : date.formatted(.dateTime.weekday(.wide))
        return "Next: \(day), \(next.title)"
    }
}

/// A big round start button with a short line or two under it, here and on a saved interval workout.
struct StartBubble: View {
    static let pairSize: CGFloat = 150
    static let soloSize: CGFloat = 180

    let title: String
    let systemImage: String
    var caption: String?
    var detail: String?
    var size: CGFloat = StartBubble.pairSize
    /// Teal for a run to start, plain glass for a day with nothing to start.
    var isProminent = false
    var hint: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.24, weight: .semibold))
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(isProminent ? Color.onAccent : Color.primary)
                .padding(LayoutMetrics.sectionSpacing)
                .frame(width: size, height: size)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular
                    .tint(isProminent ? Color.accentColor : Color.glassSurface.opacity(VisualOpacity.heavy))
                    .interactive(),
                in: .circle
            )
            .accessibilityLabel([title, caption, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityHint(hint ?? "")

            if caption != nil || detail != nil {
                VStack(spacing: 2) {
                    if let caption {
                        Text(caption)
                            .font(.subheadline.weight(.semibold))
                    }
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: size)
                .accessibilityHidden(true)
            }
        }
    }
}

#Preview("Run home - With runs") {
    RunHomeView()
        .modelContainer(WindRunSeed.containerWithRuns())
}

#Preview("Run home - Empty") {
    RunHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
