//
//  CoachPlanView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The current plan: this week's sessions by day, then the weeks ahead.
struct CoachPlanView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @Environment(\.modelContext) private var modelContext
    @Environment(CoachInbox.self) private var inbox

    let plan: CoachPlan

    @State private var router = CoachRouter()
    @State private var confirmsHeatIllness = false
    /// The next few weeks as the coach would plan them if this week goes as planned.
    @State private var outlook: [PlannedWeek] = []
    /// The race time the runner's current fitness points to, for time and event goals.
    @State private var forecast: RaceForecast?
    /// Today's resting heart-rate note, worked out on the device and never stored (PZ-13).
    @State private var restingCheck: RestingHeartRateCheck?
    /// The day the resting heart-rate note was last shown, so it shows at most once a day.
    static let restingCheckDayKey = "coachRestingCheckDay"
    @AppStorage(CoachPlanView.restingCheckDayKey) private var restingCheckDay = ""

    private var actions: CoachActions { CoachActions(context: modelContext, plan: plan, inbox: inbox) }

    private var currentWeekIndex: Int {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: plan.startDate),
            to: Calendar.current.startOfDay(for: .now)
        ).day ?? 0
        return max(0, days / 7)
    }

    private var thisWeek: CoachWeek? { plan.week(at: currentWeekIndex) }

    private var comingWeeks: [CoachWeek] {
        plan.weeks.filter { $0.order > currentWeekIndex }
    }

    /// The coach's notes, less any that repeat a week's own explanation.
    private var notes: [CoachNote] {
        let explained = Set(plan.weeks.map(\.because))
        return inbox.notes.filter { !explained.contains($0.text) }
    }

    var body: some View {
        let state = actions.state()
        // While the medical question is open, its card explains the pause instead.
        let asksClearance = inbox.questions.contains { if case .medicalClearance = $0 { true } else { false } }
        let resumeQuestion = asksClearance ? nil : state.flatMap { CoachEngine.resumeQuestion($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                if !notes.isEmpty {
                    CoachNotesCard(notes: notes) { inbox.dismissNotes() }
                }

                if let resumeQuestion {
                    PausedCard(question: resumeQuestion, resume: resume)
                }

                if let restingCheck {
                    RestingHeartRateCard(check: restingCheck) { easy in
                        answerRestingCheck(restingCheck, makeEasy: easy)
                    }
                }

                if let state, InjuryCoach.crossTrainingSwaps(state) != .none {
                    CrossTrainingCard(swaps: InjuryCoach.crossTrainingSwaps(state))
                }

                ForEach(cards(showingResume: resumeQuestion != nil), id: \.self) { question in
                    CoachQuestionCard(question: question, actions: actions, open: router.open)
                }

                if let eventDate = plan.eventDate {
                    EventCountdown(eventDate: eventDate)
                }

                if let forecast {
                    ForecastCard(forecast: forecast)
                }

                if plan.startDate > .now {
                    Label("Your plan starts on \(plan.startDate.formatted(.dateTime.weekday(.wide).month().day())).", systemImage: "calendar")
                        .font(.headline)
                } else if let thisWeek {
                    CoachWeekCard(week: thisWeek, unit: unit, isCurrent: true)
                } else {
                    EmptyStateView(
                        title: "No sessions this week",
                        systemImage: "calendar",
                        description: "The coach plans each week as the one before it ends."
                    )
                }

                if !comingWeeks.isEmpty || !outlook.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coming up")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        if !outlook.isEmpty {
                            Text("If this week goes as planned. The coach plans each week as it comes.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(comingWeeks) { week in
                        CoachWeekCard(week: week, unit: unit, isCurrent: false)
                    }
                    ForEach(outlook) { week in
                        CoachOutlookWeekCard(week: week, blockLength: state?.quality.blockLength ?? 8, unit: unit)
                    }
                }
            }
            .padding()
        }
        .navigationDestination(for: CoachWorkout.self) { workout in
            CoachWorkoutDetailView(workout: workout, openCoach: router.open)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Report injury", systemImage: "bandage") {
                    router.open(.reportInjury(origin: .planScreen, runID: nil))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Life happens", systemImage: "calendar.badge.exclamationmark") { router.open(.lifeHappens(nil)) }
                    Button("Felt unwell in the heat", systemImage: "thermometer.sun") { confirmsHeatIllness = true }
                    if let illness = actions.state()?.activeIllness {
                        Button("Feeling ill again", systemImage: "facemask") { feelIllAgain(illness) }
                    }
                    Divider()
                    Button("Plan settings", systemImage: "slider.horizontal.3") { router.open(.settings) }
                }
            }
        }
        .confirmationDialog("Felt unwell in the heat?", isPresented: $confirmsHeatIllness, titleVisibility: .visible) {
            Button("Yes, tell the coach") {
                actions.perform { state, runs, now, calendar in
                    CoachEngine.reportHeatIllness(state: state, runs: runs, now: now, calendar: calendar)
                }
            }
        } message: {
            Text(SafetyText.heatLines)
        }
        .coachSheets(router, plan: plan)
        // The outlook simulates the weeks day by day, so it's worked out once per change, not per redraw.
        .task(id: plan.updatedDate) {
            await Task.yield()
            updatePreviews()
        }
        .task { await checkRestingHeartRate() }
    }

    /// Once a day, when heart rate is set to coach, a raised resting heart rate offers an easier day.
    private func checkRestingHeartRate() async {
        let today = Date.now.formatted(.iso8601.year().month().day())
        let settings = CoachHeartRateStore.load()
        guard restingCheckDay != today, settings.canCoach, let state = actions.state() else { return }
        let readings = await RestingHeartRateReader.readings()
        guard let check = RestingHeartRate.check(readings, settings: settings, state: state, now: .now, calendar: .current) else { return }
        restingCheckDay = today
        restingCheck = check
    }

    /// A yes is the readiness answer "Legs or energy below normal" for today's hard session (RB-8).
    private func answerRestingCheck(_ check: RestingHeartRateCheck, makeEasy: Bool) {
        if makeEasy, let sessionID = check.easySessionID {
            actions.perform { state, runs, now, calendar in
                CoachEngine.submitReadiness(.belowNormal, heat: nil, sessionID: sessionID, state: state, runs: runs, now: now, calendar: calendar)
            }
        }
        restingCheck = nil
    }

    private func updatePreviews() {
        guard let state = actions.state() else {
            outlook = []
            forecast = nil
            return
        }
        let runs = actions.service.loggedRuns()
        let stored = Set(plan.weeks.filter { !$0.workouts.isEmpty }.map(\.order))
        outlook = CoachEngine.outlook(weeks: 3, state: state, runs: runs, now: .now, calendar: .current)
            .filter { $0.kind != .paused && !stored.contains($0.index) }
        // Distance plans are about finishing, so only time and event goals show a race time.
        forecast = state.goal.flavor == .buildDistance
            ? nil
            : CoachEngine.forecast(state.goal.distance, state: state, runs: runs, now: .now, calendar: .current)
    }

    /// The questions to show. Only the newest run asks for a check-in; older ones can still be
    /// rated from their run. "Ready to run again?" is on the paused card when that shows.
    private func cards(showingResume: Bool) -> [CoachQuestion] {
        let newestCheckIn = inbox.questions.last { $0.isRunCheckIn }
        return inbox.questions.filter { question in
            if question.isNotAskedYet { return false }
            if showingResume, question.isReadyToRun { return false }
            if question.isRunCheckIn { return question == newestCheckIn }
            return true
        }
    }

    /// "Ready": restarts a paused plan. After a Severe injury the return comes next.
    private func resume() {
        let severe = actions.state()?.openInjuries.first { $0.level == .severe && $0.returnPlan == nil }
        // After a pause of more than 8 weeks the questions are asked again before the return (AD-14c).
        if let severe, InjuryCoach.needsNewIntake(severe, now: .now, calendar: .current) {
            router.open(.setUpAgain(CoachGoal(rawValue: plan.flavor) ?? .buildDistance))
            return
        }
        actions.perform { state, runs, now, calendar in
            CoachEngine.resume(state: state, runs: runs, now: now, calendar: calendar)
        }
        if let severe {
            router.open(.returnPlan(reportID: severe.id))
        }
    }

    private func feelIllAgain(_ episode: IllnessEpisode) {
        actions.perform { state, runs, now, calendar in
            CoachEngine.answerIllness(.feelIllAgain, episodeID: episode.id, state: state, runs: runs, now: now, calendar: calendar)
        }
    }
}

/// A raised resting heart rate this morning, with the offer to make today's hard session easy.
private struct RestingHeartRateCard: View {
    let check: RestingHeartRateCheck
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Label("This morning", systemImage: "heart")
                .font(.headline)
            Text(check.note.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if check.easySessionID != nil {
                HStack {
                    Button("Make today easy") { answer(true) }
                        .prominentAccentButton()
                    Button("Keep it") { answer(false) }
                        .buttonStyle(.glass)
                }
            } else {
                Button("OK") { answer(false) }
                    .buttonStyle(.glass)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }
}

/// While an injury report is open, a pain-free bike or pool session can stand in for a run (AD-14e).
private struct CrossTrainingCard: View {
    let swaps: CrossTrainingSwaps

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Cross-training counts", systemImage: "figure.pool.swim")
                .font(.headline)
            Text(InjuryCoach.crossTrainingOffer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if swaps == .oneRunAWeek {
                Text("Up to one run a week while it settles.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
        .accessibilityElement(children: .combine)
    }
}

/// The plan is on hold: the question to ask before it restarts, and "Ready".
private struct PausedCard: View {
    let question: String
    let resume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Label("Your plan is paused", systemImage: "pause.circle")
                .font(.headline)
            Text(question)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Ready", action: resume)
                .prominentAccentButton()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }
}

private extension CoachQuestion {
    var isReadyToRun: Bool {
        if case .readyToRun = self { return true }
        return false
    }

    var isRunCheckIn: Bool {
        if case .runCheckIn = self { return true }
        return false
    }

    /// Questions the engine lists but doesn't ask yet, so they get no card.
    var isNotAskedYet: Bool {
        switch self {
        case .raceIllness, .raceHeat, .eventDetails, .reask, .redoIntake, .goalAlternatives: true
        default: false
        }
    }
}

private struct EventCountdown: View {
    let eventDate: Date

    private var days: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: eventDate)
        ).day ?? 0
    }

    var body: some View {
        Label {
            Text(days > 0 ? "\(days) days to race day" : days == 0 ? "Race day" : "Race day has passed")
        } icon: {
            Image(systemName: "flag.checkered")
        }
        .font(.headline)
    }
}

/// One week: its name, why it looks the way it does, and its sessions.
struct CoachWeekCard: View {
    let week: CoachWeek
    let unit: DistanceUnit
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            AdaptiveRow {
                Text(isCurrent ? "This week" : "Week \(week.order + 1)")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(week.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !week.because.isEmpty {
                Text(week.because)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if week.kind != WeekKind.paused.rawValue, week.workouts.isEmpty || (isCurrent && !week.workouts.contains(where: { !$0.isDone && ($0.scheduledDate ?? .distantPast) >= Calendar.current.startOfDay(for: .now) })) {
                if let start = week.startDate, let next = Calendar.current.date(byAdding: .day, value: 7, to: start), isCurrent {
                    Text("No runs left this week. Next week is planned on \(next.formatted(.dateTime.weekday(.wide).month().day())).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(week.workouts) { workout in
                NavigationLink(value: workout) {
                    CoachWorkoutRow(workout: workout, unit: unit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }
}

/// The race time the runner's fitness points to today.
private struct ForecastCard: View {
    let forecast: RaceForecast

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Your \(forecast.distance.name) today", systemImage: "stopwatch")
                .font(.headline)
            Text("About \(CoachFormat.clock(forecast.central)), likely between \(CoachFormat.clock(forecast.low)) and \(CoachFormat.clock(forecast.high)).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if forecast.confidence == .low {
                Text("A rough guide for now: it firms up as you log more runs and tests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
        .accessibilityElement(children: .combine)
    }
}

/// A week the coach hasn't planned yet, as it would look if this week goes as planned.
/// Its sessions can't be opened, since the real week is planned when it comes.
struct CoachOutlookWeekCard: View {
    @ScaledMetric(relativeTo: .subheadline) private var dayWidth: CGFloat = 40
    let week: PlannedWeek
    let blockLength: Int
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            AdaptiveRow {
                Text("Week \(week.index + 1)")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(CoachProjection.weekTitle(week, blockLength: blockLength))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(week.sessions) { session in
                HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.compactSpacing) {
                    Text(dayName(session))
                        .font(.subheadline.weight(.semibold))
                        .frame(width: dayWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CoachProjection.sessionTitle(session, unit: unit))
                        Text(CoachFormat.targetSummary(CoachProjection.target(for: session, unit: unit, weekStart: week.start), unit: unit))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }

    private func dayName(_ session: PlannedSession) -> String {
        guard let date = Calendar.current.date(byAdding: .day, value: session.dayOffset, to: week.start) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

/// One session: the day, what it is, and what it asks for.
struct CoachWorkoutRow: View {
    @ScaledMetric(relativeTo: .subheadline) private var dayWidth: CGFloat = 40
    let workout: CoachWorkout
    let unit: DistanceUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.compactSpacing) {
            Text(dayName)
                .font(.subheadline.weight(.semibold))
                .frame(width: dayWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.body)
                Text(CoachFormat.targetSummary(workout.target, unit: unit))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if workout.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenDay), \(workout.title), \(CoachFormat.targetSummary(workout.target, unit: unit))")
        .accessibilityValue(workout.isDone ? "Done" : "")
    }

    private var spokenDay: String {
        workout.scheduledDate?.formatted(.dateTime.weekday(.wide)) ?? ""
    }

    private var dayName: String {
        guard let date = workout.scheduledDate else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
}

#Preview("Coach plan") {
    let container = WindRunSchema.makeContainer(inMemory: true)
    let plan = CoachPlan(flavor: "event", startDate: .now, eventDate: .now.addingTimeInterval(70 * 86_400), goalDistanceMeters: 21_097.5)
    container.mainContext.insert(plan)
    let week = plan.addWeek(order: 0)
    week.update(kind: "build", title: "Build", because: "Last week went well, so this week adds a little.", startDate: .now, plannedMeters: nil, plannedSeconds: 150 * 60, longRunMeters: nil, longRunSeconds: 60 * 60, outcome: nil)
    week.addWorkout(kind: "easy", dayOffset: 1).update(kind: "easy", dayOffset: 1, date: nil, order: 0, status: "planned", target: CoachWorkoutTarget(title: "Easy run", detail: "", notes: "", meters: nil, seconds: 30 * 60, pace: 390...420, effort: 2...3, runWalk: nil, isKeySession: false, isQuality: false))
    week.addWorkout(kind: "long", dayOffset: 5).update(kind: "long", dayOffset: 5, date: nil, order: 1, status: "planned", target: CoachWorkoutTarget(title: "Long run", detail: "", notes: "", meters: nil, seconds: 60 * 60, pace: 400...440, effort: 2...3, runWalk: nil, isKeySession: true, isQuality: false))
    return NavigationStack { CoachPlanView(plan: plan) }
        .modelContainer(container)
        .environment(CoachInbox())
}

/// What the coach just said: the safety line at plan start, why a week changed, milestones.
struct CoachNotesCard: View {
    let notes: [CoachNote]
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack {
                Label("From your coach", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            ForEach(notes, id: \.self) { note in
                Text(note.text)
                    .font(note.topic == .safety ? .footnote : .body)
                    .foregroundStyle(note.topic == .safety ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }
}
