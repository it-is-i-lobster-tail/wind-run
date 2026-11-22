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

    /// Finished runs, newest first. A run under way has no end yet, so its changes mid-run don't touch this.
    @Query(filter: #Predicate<Run> { $0.endDateValue != nil }, sort: \Run.startDateValue, order: .reverse)
    private var endedRuns: [Run]
    @Query private var coachPlans: [CoachPlan]
    @State private var recorder: RunRecorder?
    @State private var finishedRun: Run?
    @State private var path = NavigationPath()

    /// Switches to the Coach section, for a rest day or a paused plan.
    private let showCoach: () -> Void

    init(showCoach: @escaping () -> Void = {}) {
        self.showCoach = showCoach
    }

    private var coachPlan: CoachPlan? {
        guard TermsAcceptance.isCurrent() else { return nil }
        return coachPlans.active
    }

    var body: some View {
        // Each worked out once a redraw: the coach's day reads the plan, and the history filters every run.
        let today = coachDay
        let finishedRuns = endedRuns.filter { $0.status == .complete }
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: LayoutMetrics.sectionSpacing * 2) {
                    StartButtons(today: today.today, unit: unit, freeRun: { startRun() }, workout: { startRun($0) }, showCoach: showCoach)
                        .padding(.top, LayoutMetrics.sectionSpacing * 2)

                    history(finishedRuns)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Run")
            .traceScreen("Run")
            .navigationDestination(for: Run.self) { run in
                RunDetailView(run: run)
            }
        }
        #if DEBUG
        .onAppear {
            // `-activeRunDemo` starts a free run, for simulator screenshots of the run screen.
            // `-activeRunPaused` pauses it and `-voiceMuted` mutes its voice.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-activeRunDemo"), recorder == nil {
                startRun()
                if arguments.contains("-activeRunPaused") { recorder?.pause() }
                if arguments.contains("-voiceMuted") { recorder?.setVoiceMuted(true) }
            }
            // The interval run, which has every chart.
            if RunDetailDemo.isRequested, path.isEmpty,
               let run = finishedRuns.first(where: { $0.kind == .intervals }) ?? finishedRuns.first {
                path.append(run)
            }
        }
        #endif
        .fullScreenCover(isPresented: isRecording, onDismiss: runFinished) {
            if let recorder {
                ActiveRunView(recorder: recorder)
            }
        }
        // The watch shows the same sessions, so they can be run from the wrist.
        .task(id: watchSessions) { SettingsSync.shared.sendCoachToday(watchSessions) }
        // What the start bubble shows, so "it says Rest Day but I have a workout" can be followed.
        .onChange(of: today.traceName, initial: true) { _, shown in
            Trace.log(.coach, "Run home coach day", ["shown": shown, "watchSessions": watchSessions.count])
        }
    }

    /// Today's coach sessions as the watch gets them.
    private var watchSessions: [WatchCoachSession] {
        todaysSessions.compactMap { WatchCoachSession($0) }
    }

    /// Every finished run, in months, newest first. Rows are only built as they scroll in.
    @ViewBuilder
    private func history(_ finishedRuns: [Run]) -> some View {
        if finishedRuns.isEmpty {
            EmptyStateView(
                title: "No runs yet",
                systemImage: "figure.run",
                description: "Tap Free Run to record your first run. Only you can see your runs."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                Text("Your runs")
                    .font(.title3.weight(.semibold))
                ForEach(RunMonth.months(of: finishedRuns)) { month in
                    Section {
                        ForEach(month.runs) { run in
                            NavigationLink(value: run) {
                                RunRow(run: run, unit: unit)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                Trace.tap("Run", "Recent run", ["kind": run.kind.rawValue])
                            })
                        }
                    } header: {
                        Text(month.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, LayoutMetrics.compactSpacing)
                            .accessibilityAddTraits(.isHeader)
                    }
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
        Trace.log(.screen, "Run screen closed", ["status": finishedRun?.status.rawValue ?? "none"])
        defer { finishedRun = nil }
        guard coachPlan != nil, let run = finishedRun, run.status == .complete else { return }
        BuildRunStart.runFinished(in: modelContext)
    }

    /// Today's runs from the coach that are still to do.
    private var todaysSessions: [CoachWorkout] {
        guard let coachPlan, let state = BuildService(context: modelContext).state(of: coachPlan) else { return [] }
        return CoachToday.workouts(coachPlan, build: state, now: .now, calendar: .current)
    }

    /// What the coach has for today, or nil without a plan, and how the trace names it.
    private var coachDay: (today: CoachToday?, traceName: String) {
        guard let coachPlan else { return (nil, "noPlan") }
        // A plan whose state can't be read shows no bubble; the trace says why.
        guard let state = BuildService(context: modelContext).state(of: coachPlan) else { return (nil, "unreadable") }
        guard let today = CoachToday.of(coachPlan, build: state, now: .now, calendar: .current) else { return (nil, "none") }
        return (today, today.traceName)
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
                // Not the checkered flag: that's Finish on the run screen.
                systemImage: "figure.run.square.stack",
                caption: session.title,
                detail: CoachFormat.targetSummary(session.target, unit: unit),
                isProminent: true
            ) { workout(session) }
        case .done(let next):
            StartBubble(title: "Done Today", systemImage: "checkmark", caption: nextCaption(next), hint: "Opens Coach", action: showCoach)
        case .rest(let next):
            StartBubble(title: "Rest Day", systemImage: "moon.zzz", caption: nextCaption(next), hint: "Opens Coach", action: showCoach)
        case .startsLater(let start, let next):
            StartBubble(title: "Plan Starts Soon", systemImage: "calendar", caption: next == nil ? startCaption(start) : nextCaption(next), hint: "Opens Coach", action: showCoach)
        case .paused:
            StartBubble(title: "Plan Paused", systemImage: "pause", caption: "Resume it in Coach", hint: "Opens Coach", action: showCoach)
        }
    }

    /// "Starts tomorrow", "Starts Monday" or "Starts Nov 9".
    private func startCaption(_ start: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(start) { return "Starts tomorrow" }
        let days = calendar.wholeDays(from: .now, to: start)
        return "Starts \(days < 7 ? start.formatted(.dateTime.weekday(.wide)) : start.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// "Next: Tomorrow, Long run", "Next: Monday, Easy run", or past a week "Next: Nov 24, Easy run". Or a
    /// note that next week is still to be planned.
    private func nextCaption(_ next: CoachWorkout?) -> String {
        guard let next, let date = next.scheduledDate else { return "Next week's runs come soon" }
        let calendar = Calendar.current
        let days = calendar.wholeDays(from: .now, to: date)
        let day = if calendar.isDateInTomorrow(date) {
            "Tomorrow"
        } else if days < 7 {
            date.formatted(.dateTime.weekday(.wide))
        } else {
            date.formatted(.dateTime.month(.abbreviated).day())
        }
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
            Button {
                Trace.tap("Start button", title)
                action()
            } label: {
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

/// The runs of one calendar month, for the history's headers.
struct RunMonth: Identifiable {
    let id: DateComponents
    let title: String
    let runs: [Run]

    /// Months newest first, each run in the order given. "November", or "November 2025" for another year.
    static func months(of runs: [Run], now: Date = .now, calendar: Calendar = .current) -> [RunMonth] {
        var months: [RunMonth] = []
        var current: (key: DateComponents, runs: [Run])?
        for run in runs {
            let key = calendar.dateComponents([.year, .month], from: run.startDate)
            if current?.key == key {
                current?.runs.append(run)
            } else {
                if let current { months.append(month(current.key, current.runs, now: now, calendar: calendar)) }
                current = (key, [run])
            }
        }
        if let current { months.append(month(current.key, current.runs, now: now, calendar: calendar)) }
        return months
    }

    private static func month(_ key: DateComponents, _ runs: [Run], now: Date, calendar: Calendar) -> RunMonth {
        let date = calendar.date(from: key) ?? now
        let sameYear = calendar.component(.year, from: now) == key.year
        let title = sameYear ? date.formatted(.dateTime.month(.wide)) : date.formatted(.dateTime.month(.wide).year())
        return RunMonth(id: key, title: title, runs: runs)
    }
}

extension CoachToday {
    /// The case alone, for the trace: no dates or names.
    var traceName: String {
        switch self {
        case .workout: "workout"
        case .done: "done"
        case .rest: "rest"
        case .startsLater: "startsLater"
        case .paused: "paused"
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
