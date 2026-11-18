//
//  BuildPlanView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The current plan: days to the event, this week's runs and total, and the timeline with what's been run.
struct BuildPlanView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @Environment(\.modelContext) private var modelContext

    let plan: CoachPlan

    @State private var sheet: BuildSheet?

    private var service: BuildService { BuildService(context: modelContext) }

    var body: some View {
        let state = service.state(of: plan)
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                if let state {
                    ForEach(state.openInjuries) { report in
                        InjuryCard(report: report, currentWeek: state.planCalendar.number(on: .now, calendar: .current), perform: perform, editRecovery: {
                            Trace.tap("Injury card", "Faster or slower")
                            sheet = .recovery(report.id)
                        })
                    }
                    countdown(state)
                    thisWeek(state)
                    timeline(state)
                }
            }
            .padding()
        }
        .navigationDestination(for: CoachWorkout.self) { workout in
            BuildWorkoutDetailView(workout: workout)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Report injury", systemImage: "bandage") {
                    Trace.tap("Coach plan", "Report injury")
                    sheet = .reportInjury
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Plan settings", systemImage: "slider.horizontal.3") {
                    Trace.tap("Coach plan", "Plan settings")
                    sheet = .settings
                }
            }
        }
        .traceScreen("Coach plan")
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .reportInjury:
                BuildReportInjuryView(perform: perform)
            case .settings:
                BuildPlanSettingsView(plan: plan, state: state)
            case .recovery(let id):
                if let report = state?.injuries.first(where: { $0.id == id }) {
                    RecoveryEditor(report: report, perform: perform)
                }
            }
        }
    }

    private func perform(_ call: @escaping BuildCall) {
        service.perform(on: plan, call)
    }

    // MARK: Sections

    private func countdown(_ state: BuildPlanState) -> some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: state.goalDate)).day ?? 0
        let name = state.settings.goal.event.yourName
        let headline = switch days {
        case 2...: "\(days) days to \(name)"
        case 1: "\(name.capitalizedFirst) is tomorrow"
        case 0: "\(name.capitalizedFirst) is today"
        default: "\(name.capitalizedFirst) is done"
        }
        return VStack(alignment: .leading, spacing: 4) {
            Label(headline, systemImage: "flag.checkered")
                .font(.headline)
            Text(state.goalDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func thisWeek(_ state: BuildPlanState) -> some View {
        let number = state.planCalendar.number(on: .now, calendar: .current)
        if number < 1 {
            Label("Your plan starts on \(state.planCalendar.firstStart.formatted(.dateTime.weekday(.wide).month().day())).", systemImage: "calendar")
                .font(.headline)
        } else if let week = state.week(number), let stored = plan.storedWeek(number) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Week \(number) of \(state.planCalendar.count)")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Text(week.kind.name)
                        .foregroundStyle(.secondary)
                }
                if week.target.meters > 0 {
                    ProgressView(value: min(week.done.meters, week.target.meters), total: week.target.meters) {
                        Text("\(unit.weekly(week.done.meters)) of \(unit.weekly(week.target.meters))")
                            .font(.subheadline)
                    }
                    if week.target.climb >= 1 {
                        Text("Climb: \(unit.climb(week.done.climb)) of \(unit.climb(week.target.climb))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    // Runs from other apps in Health fill setup's numbers in, but the week counts Wind Run's.
                    Text("Runs you record with Wind Run count toward the week.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(stored.workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutRow(workout: workout, unit: unit, climb: state.climb(ofSession: workout.sessionID))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { Trace.tap("Coach plan", "This week's run") })
                }
                if stored.workouts.isEmpty {
                    Text(emptyWeekNote(week))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .windRunGlassCard()
        }
    }

    /// What the week's card says when it has no runs left to show.
    private func emptyWeekNote(_ week: BuildWeek) -> String {
        if week.kind == .paused { return "No running while your plan is paused." }
        if week.target.meters <= 0 {
            return week.kind == .recovery ? "Rest week: no running planned while you recover." : "No runs planned this week."
        }
        return week.done.meters >= week.target.meters ? "You've run this week's distance." : "No runs left this week."
    }

    private func timeline(_ state: BuildPlanState) -> some View {
        let outlook = BuildEngine.outlook(state, now: .now, calendar: .current)
        let current = state.planCalendar.number(on: .now, calendar: .current)
        // Weeks so far show what was run; the current one shows its plan.
        let done = state.weeks.map { week in
            TimelineWeek(number: week.number, kind: week.kind, volume: week.closed ? week.done : week.target)
        }.filter { $0.number <= max(current, 0) }
        let summary = BuildTimelineSummary(timeline: outlook, unit: unit, event: state.settings.goal.event)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Your timeline")
                .font(.headline)
            BuildTimelineChart(timeline: outlook, unit: unit, done: done, runThrough: state.weeks.filter(\.closed).map(\.number).max())
            if state.isPaused {
                Text("While your plan is paused, the weeks ahead wait. They come back, starting gently, once you're cleared or ready.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let note = summary.planAmbitiousNote {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let peak = outlook.planPeakWeek {
                Text("Peak week \(outlook.calendar.end(of: peak, calendar: .current).formatted(.dateTime.month(.abbreviated).day())), then the plan holds it until your event week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .windRunGlassCard()
    }
}

enum BuildSheet: Identifiable, Hashable {
    case reportInjury
    case settings
    case recovery(UUID)

    var id: String {
        switch self {
        case .reportInjury: "reportInjury"
        case .settings: "settings"
        case .recovery(let id): "recovery-\(id)"
        }
    }
}

/// One run of the week: its day, distance and kind, done or missed.
private struct WorkoutRow: View {
    let workout: CoachWorkout
    let unit: DistanceUnit
    /// The run's planned climb, from the plan, so it shows in the unit picked now.
    let climb: Double

    @ScaledMetric(relativeTo: .headline) private var dayWidth = 44.0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text((workout.scheduledDate ?? .now).formatted(.dateTime.weekday(.abbreviated)))
                .font(.headline)
                .fixedSize()
                .frame(minWidth: dayWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                // The distance is what to run, so it leads.
                if let meters = workout.targetMeters {
                    Text(unit.weekly(meters))
                        .font(.body.weight(.semibold).monospacedDigit())
                }
                Text(climb >= 1 ? "\(workout.title) · \(unit.climb(climb)) climb" : workout.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if workout.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Done")
            } else if workout.isMissed {
                Text("Missed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// An open injury report and what the runner can do about it.
private struct InjuryCard: View {
    let report: BuildInjury
    /// The plan week now, for where the recovery weeks are up to.
    let currentWeek: Int
    let perform: BuildPerform
    let editRecovery: () -> Void

    private var area: String { report.area?.name ?? "injury" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "bandage")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
            actions
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }

    private var title: String {
        switch report.level {
        case .mild: "Mild: your mileage holds"
        case .intense: report.recoveryStartWeek == nil ? "\(InjuryLevel.intense.name): plan paused" : "Recovery weeks"
        case .severe: report.recoveryStartWeek == nil ? "Severe: plan paused" : "Return weeks"
        }
    }

    private var message: String {
        switch report.level {
        case .mild:
            return "Your weeks stay the same size until your \(area) is better. Tell the coach when it is."
        case .intense where report.recoveryStartWeek == nil:
            if let answer = report.clearance, answer != .yes {
                return "Plan paused until you're cleared. Tap Yes when a doctor or physio says you can train."
            }
            return "Are you medically cleared to keep training? If you're not sure, the plan waits until a doctor or physio says you can train."
        case .severe where report.recoveryStartWeek == nil:
            return "No running until you're ready. Then 2 weeks at half your mileage, and the plan builds again from there."
        default:
            let recovery = report.recovery ?? .intense
            let share = CoachFormat.percent(recovery.reducedShare)
            let reduced = "\(CoachFormat.weeks(recovery.reducedWeeks)) at \(share)% of your week before, and back up from there."
            let plan = recovery.restWeeks > 0 ? "\(CoachFormat.weeks(recovery.restWeeks)) off, then \(reduced)" : reduced.capitalizedFirst
            guard let start = report.recoveryStartWeek, (start ..< start + recovery.weeks).contains(currentWeek) else { return plan }
            return "Week \(currentWeek - start + 1) of \(recovery.weeks) back. \(plan)"
        }
    }

    @ViewBuilder
    private var actions: some View {
        let id = report.id
        switch report.level {
        case .mild:
            Button("It's better") {
                Trace.tap("Injury card", "It's better")
                perform { state, _, now, _ in BuildEngine.injuryBetter(reportID: id, state: state, now: now) }
            }
            .prominentAccentButton()
        case .intense where report.recoveryStartWeek == nil:
            HStack {
                ForEach(ClearanceAnswer.allCases, id: \.self) { answer in
                    Button {
                        // Which answer is a medical detail, so only that one was given.
                        Trace.tap("Injury card", "Cleared to train answer")
                        perform { state, runs, now, calendar in
                            BuildEngine.answerClearance(answer, reportID: id, state: state, runs: runs, now: now, calendar: calendar)
                        }
                    } label: {
                        // The answer given stays marked, so tapping it again isn't needed.
                        if report.clearance == answer {
                            Label(answer.name, systemImage: "checkmark")
                        } else {
                            Text(answer.name)
                        }
                    }
                    .buttonStyle(.glass)
                    .accessibilityAddTraits(report.clearance == answer ? .isSelected : [])
                }
            }
            .sensoryFeedback(.success, trigger: report.clearance)
        case .severe where report.recoveryStartWeek == nil:
            Button("I'm ready to run again") {
                Trace.tap("Injury card", "I'm ready to run again")
                perform { state, runs, now, calendar in
                    BuildEngine.ready(reportID: id, state: state, runs: runs, now: now, calendar: calendar)
                }
            }
            .prominentAccentButton()
        default:
            Button("Faster or slower", action: editRecovery)
                .buttonStyle(.glass)
        }
    }
}
