//
//  CoachPlanView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The current plan: this week's sessions by day, then the weeks ahead.
struct CoachPlanView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let plan: CoachPlan

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                if let eventDate = plan.eventDate {
                    EventCountdown(eventDate: eventDate)
                }

                if let thisWeek {
                    CoachWeekCard(week: thisWeek, unit: unit, isCurrent: true)
                } else {
                    EmptyStateView(
                        title: "No sessions this week",
                        systemImage: "calendar",
                        description: "The coach plans each week as the one before it ends."
                    )
                }

                if !comingWeeks.isEmpty {
                    Text("Coming up")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    ForEach(comingWeeks) { week in
                        CoachWeekCard(week: week, unit: unit, isCurrent: false)
                    }
                }
            }
            .padding()
        }
        .navigationDestination(for: CoachWorkout.self) { workout in
            CoachWorkoutDetailView(workout: workout)
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
            HStack(alignment: .firstTextBaseline) {
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

/// One session: the day, what it is, and what it asks for.
struct CoachWorkoutRow: View {
    let workout: CoachWorkout
    let unit: DistanceUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.compactSpacing) {
            Text(dayName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, alignment: .leading)
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
                    .accessibilityLabel("Done")
            }
        }
        .accessibilityElement(children: .combine)
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
}
