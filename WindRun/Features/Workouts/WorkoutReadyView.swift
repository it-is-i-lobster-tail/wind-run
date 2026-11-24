//
//  WorkoutReadyView.swift
//  Wind Run
//

import SwiftUI

/// The last page before a run: "When you're ready…", what's about to start, and a big Start that opens
/// the run screen.
struct WorkoutReadyPage<Details: View>: View {
    let title: String
    /// The goal in big type, such as "5 km" or "45 min", or nil when the details say it.
    var headline: String?
    var caption: String?
    let start: () -> Void
    @ViewBuilder var details: Details

    /// The goal's size, following the runner's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 56

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.sectionSpacing * 1.5) {
                VStack(spacing: LayoutMetrics.compactSpacing) {
                    Text("When you're ready…")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let headline {
                        Text(headline)
                            .font(.system(size: headlineSize, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    if let caption {
                        Text(caption)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, LayoutMetrics.sectionSpacing * 2)
                .accessibilityElement(children: .combine)

                StartBubble(title: "Start", systemImage: "figure.run", size: StartBubble.soloSize, isProminent: true, action: start)

                details
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension WorkoutReadyPage where Details == EmptyView {
    init(title: String, headline: String? = nil, caption: String? = nil, start: @escaping () -> Void) {
        self.init(title: title, headline: headline, caption: caption, start: start, details: { EmptyView() })
    }
}

/// The ready page for a free, distance, timed or coach run. The runner's own workouts have their own,
/// `SavedWorkoutView`, with Edit and Delete.
struct WorkoutReadyView: View {
    let ready: ReadyWorkout
    let unit: DistanceUnit
    let start: () -> Void

    var body: some View {
        Group {
            switch ready {
            // The built-in runs and the coach's have no editor, so they pick their display here.
            case .free(let name):
                WorkoutReadyPage(title: name, caption: "Just run. Finish when you're done.", start: start) {
                    DisplayChoiceRow(kind: .free)
                }
            case .distance(let name, let meters):
                WorkoutReadyPage(title: name, headline: WorkoutFormat.distance(meters, unit: unit), caption: "Keep going after it if you like.", start: start) {
                    DisplayChoiceRow(kind: .distance)
                }
            case .time(let name, let seconds):
                WorkoutReadyPage(title: name, headline: WorkoutFormat.time(seconds), caption: "Keep going after it if you like.", start: start) {
                    DisplayChoiceRow(kind: .timed)
                }
            case .coach(let workout):
                WorkoutReadyPage(title: "Coach's Workout", start: start) {
                    CoachSessionBanner(target: workout.target, unit: unit)
                    if let plan = workout.intervalPlan, !plan.timeline.isEmpty {
                        IntervalPlanCard(plan: plan, unit: unit)
                    }
                    CoachWorkoutChanges(workout: workout)
                    DisplayChoiceRow(kind: .coach)
                }
            case .saved:
                // Routed to SavedWorkoutView by WorkoutsHomeView.destination before reaching here.
                EmptyView()
            }
        }
        .traceScreen("Workout ready")
    }
}

#Preview("Distance") {
    NavigationStack {
        WorkoutReadyView(ready: .distance(name: "Distance Run", meters: 5_000), unit: .kilometers) {}
    }
}

#Preview("Free") {
    NavigationStack {
        WorkoutReadyView(ready: .free(name: "Free Run"), unit: .kilometers) {}
    }
}
