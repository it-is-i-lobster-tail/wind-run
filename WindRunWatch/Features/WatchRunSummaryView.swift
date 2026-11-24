//
//  WatchRunSummaryView.swift
//  Wind Run Watch
//

import SwiftUI

struct WatchRunHistoryRow: View {
    let run: Run
    let unit: DistanceUnit
    let isSynced: Bool

    var body: some View {
        let displayUnit = run.intervalPlan?.distanceUnit ?? unit
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.watchTitle)
                    .font(.headline)
                Text("\(RunFormat.distance(run.distanceMeters, unit: displayUnit)) · \(RunFormat.duration(run.activeDuration()))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(RunFormat.day(run.startDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !isSynced {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Waiting to sync")
            }
            Image(systemName: "chevron.forward")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WatchRunSummaryView: View {
    let run: Run
    let unit: DistanceUnit
    let isSynced: Bool

    var body: some View {
        let displayUnit = run.intervalPlan?.distanceUnit ?? unit
        List {
            Section {
                LabeledContent("Distance", value: RunFormat.distance(run.distanceMeters, unit: displayUnit))
                LabeledContent("Active time", value: RunFormat.duration(run.activeDuration()))
                if let pace = run.pace(), pace > 0 {
                    LabeledContent("Avg. pace", value: RunFormat.pace(pace, unit: displayUnit))
                }
                if let heartRate = run.heartRateStats?.mean {
                    LabeledContent("Avg. heart rate", value: RunFormat.heartRate(heartRate))
                }
                if let steps = run.stepTotal {
                    LabeledContent("Steps", value: RunFormat.steps(steps))
                }
                if let calories = run.activeCalories {
                    LabeledContent("Active calories", value: RunFormat.calories(calories))
                }
            } header: {
                Text(run.startDate, format: .dateTime.month(.abbreviated).day().year().hour().minute())
            }
            .monospacedDigit()

            if !isSynced {
                Section {
                    Label("Waiting to sync to iPhone", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(run.watchTitle)
    }
}

private extension Run {
    var watchTitle: String {
        if let coachWorkout { return coachWorkout.title }
        if let intervalPlan { return intervalPlan.name }
        switch kind {
        case .coached: return "Coach Run"
        case .intervals: return "Workout"
        case .free:
            switch goal {
            case .distance: return WorkoutChoice.distanceRun.name
            case .time: return WorkoutChoice.timedRun.name
            case nil: return WorkoutChoice.freeRun.name
            }
        }
    }
}
