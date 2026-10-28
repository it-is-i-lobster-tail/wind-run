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
                        InjuryCard(report: report, perform: perform, editRecovery: { sheet = .recovery(report.id) })
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
                Button("Report injury", systemImage: "bandage") { sheet = .reportInjury }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Plan settings", systemImage: "slider.horizontal.3") { sheet = .settings }
            }
        }
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

    private func perform(_ call: @escaping (BuildPlanState, [CoachRun], Date, Calendar) -> BuildPlanState) {
        service.perform(on: plan, call)
    }

    // MARK: Sections

    private func countdown(_ state: BuildPlanState) -> some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: state.goalDate).day ?? 0
        let event = state.settings.goal.event
        let name = event == .custom ? "your event" : "your \(event.shortName)"
        return VStack(alignment: .leading, spacing: 4) {
            Label(days > 0 ? "\(days) days to \(name)" : days == 0 ? "\(name.capitalizedFirst) is today" : "\(name.capitalizedFirst) is done", systemImage: "flag.checkered")
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
        } else if let week = state.week(number), let stored = plan.week(at: number - 1) {
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
                }
                ForEach(stored.workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutRow(workout: workout, unit: unit)
                    }
                    .buttonStyle(.plain)
                }
                if stored.workouts.isEmpty {
                    Text(week.kind == .paused ? "No running while your plan is paused." : "No runs left this week.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .windRunGlassCard()
        }
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
            BuildTimelineChart(timeline: outlook, unit: unit, done: done)
            if let note = summary.ambitiousNote {
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

/// One run of the week: its day, kind and distance, done or missed.
private struct WorkoutRow: View {
    let workout: CoachWorkout
    let unit: DistanceUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text((workout.scheduledDate ?? .now).formatted(.dateTime.weekday(.abbreviated)))
                .font(.headline)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                if let meters = workout.targetMeters {
                    Text(workout.detail.isEmpty ? unit.weekly(meters) : "\(unit.weekly(meters)) · \(workout.detail)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if workout.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Done")
            } else if workout.status == "missed" {
                Text("Missed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}

/// An open injury report and what the runner can do about it.
private struct InjuryCard: View {
    let report: BuildInjury
    let perform: (@escaping (BuildPlanState, [CoachRun], Date, Calendar) -> BuildPlanState) -> Void
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
        case .intense: report.recoveryStartWeek == nil ? "Intense: plan paused" : "Recovery weeks"
        case .severe: report.recoveryStartWeek == nil ? "Severe: plan paused" : "Return weeks"
        }
    }

    private var message: String {
        switch report.level {
        case .mild:
            return "Your weeks stay the same size until your \(area) is better. Tell the coach when it is."
        case .intense where report.recoveryStartWeek == nil:
            return "Are you medically cleared to keep training? If you're not sure, the plan waits until a doctor or physio says you can train."
        case .severe where report.recoveryStartWeek == nil:
            return "No running until you're ready. Then 2 weeks at half your mileage, and the plan builds again from there."
        default:
            let recovery = report.recovery ?? .intense
            return "\(recovery.restWeeks) \(recovery.restWeeks == 1 ? "week" : "weeks") off, then \(recovery.reducedWeeks) at \(Int(recovery.reducedShare * 100))% of your week before, and back up from there."
        }
    }

    @ViewBuilder
    private var actions: some View {
        let id = report.id
        switch report.level {
        case .mild:
            Button("It's better") {
                perform { state, _, now, _ in BuildEngine.injuryBetter(reportID: id, state: state, now: now) }
            }
            .prominentAccentButton()
        case .intense where report.recoveryStartWeek == nil:
            HStack {
                ForEach(ClearanceAnswer.allCases, id: \.self) { answer in
                    Button(answer.name) {
                        perform { state, runs, now, calendar in
                            BuildEngine.answerClearance(answer, reportID: id, state: state, runs: runs, now: now, calendar: calendar)
                        }
                    }
                    .buttonStyle(.glass)
                }
            }
        case .severe where report.recoveryStartWeek == nil:
            Button("I'm ready to run again") {
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
