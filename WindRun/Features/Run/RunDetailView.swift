//
//  RunDetailView.swift
//  Wind Run
//

import MapKit
import SwiftData
import SwiftUI

struct RunDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachInbox.self) private var inbox
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(WindRunStore.iCloudSyncKey) private var syncsWithICloud = false

    let run: Run
    /// Opens a coach screen when the runner has a coach plan.
    var openCoach: ((CoachSheet) -> Void)?

    @State private var isConfirmingDelete = false
    /// Set once the run is deleted, so nothing reads it while the screen closes.
    @State private var isDeleted = false

    private var coordinates: [CLLocationCoordinate2D] {
        run.route.map(\.coordinate)
    }

    var body: some View {
        if isDeleted {
            Color.clear
        } else {
            details
        }
    }

    private var details: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.sectionSpacing) {
                if coordinates.count > 1 {
                    Map(interactionModes: [.zoom, .pan]) {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.tint, lineWidth: 5)
                    }
                    // Just the route and the streets, no shops or venues.
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .frame(height: 280)
                    .clipShape(.rect(cornerRadius: LayoutMetrics.cardCornerRadius))
                }

                StatGrid(rows: [
                    [
                        Stat(title: "Distance", value: RunFormat.distance(run.distanceMeters, unit: unit)),
                        Stat(title: "Time", value: RunFormat.duration(run.activeDuration())),
                    ],
                    [
                        Stat(title: "Pace", value: RunFormat.pace(run.pace(), unit: unit)),
                        Stat(title: "Type", value: run.kind.name),
                    ],
                ] + stepRows)

                if let heartRate = run.heartRateStats {
                    HeartRateSummary(timeline: run.heartRateTimeline, stats: heartRate, duration: run.activeDuration())
                }

                if let openCoach, run.status == .complete {
                    HStack(spacing: LayoutMetrics.compactSpacing) {
                        Button("How was it?", systemImage: "text.bubble") {
                            openCoach(.runCheckIn(runID: run.runID))
                        }
                        .buttonStyle(.glass)
                        Button("Report injury", systemImage: "bandage") {
                            openCoach(.reportInjury(origin: .runSummary, runID: run.runID))
                        }
                        .buttonStyle(.glass)
                    }
                    .frame(maxWidth: .infinity)
                }

                if run.healthWorkoutID != nil {
                    Label("Saved to Apple Health", systemImage: "heart")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .clearsFloatingBar()
        .navigationTitle(run.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete run", systemImage: "trash") {
                    isConfirmingDelete = true
                }
            }
        }
        .confirmationDialog("Delete this run?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            if canDeleteFromHealth {
                Button("Delete from Wind Run and Health", role: .destructive) {
                    delete(fromHealth: true)
                }
                Button("Delete from Wind Run only", role: .destructive) {
                    delete(fromHealth: false)
                }
            } else {
                Button("Delete run", role: .destructive) {
                    delete(fromHealth: false)
                }
            }
        } message: {
            Text(deleteMessage)
        }
    }

    /// Steps and mean cadence, when the run counted steps.
    private var stepRows: [[Stat]] {
        guard let steps = run.stepTotal else { return [] }
        return [[
            Stat(title: "Steps", value: RunFormat.steps(steps)),
            Stat(title: "Cadence", value: RunFormat.cadence(run.meanCadence)),
        ]]
    }

    /// Health lets Wind Run delete the workouts it saved, but only while it may still write workouts.
    private var canDeleteFromHealth: Bool {
        run.healthWorkoutID != nil && HealthSync.shared.access == .allowed
    }

    private var deleteMessage: String {
        var lines = ["This can't be undone."]
        if syncsWithICloud {
            lines.append("It's also deleted from iCloud and your other devices.")
        }
        if openCoach != nil {
            lines.append("Your coach will plan as if you hadn't run it.")
        }
        if run.healthWorkoutID != nil, !canDeleteFromHealth {
            lines.append("Its workout stays in Apple Health.")
        }
        return lines.joined(separator: " ")
    }

    private func delete(fromHealth: Bool) {
        isDeleted = true
        dismiss()
        if let update = RunDeletion(context: modelContext).delete(run, fromHealth: fromHealth) {
            inbox.receive(update)
        }
    }
}

/// The run's heart rate over time, then its lowest, highest, mean and spread.
private struct HeartRateSummary: View {
    let timeline: [HeartRatePoint]
    let stats: HeartRateStats
    let duration: TimeInterval

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            // A line needs two readings.
            if timeline.count > 1 {
                VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                    Text("Heart rate")
                        .font(.headline)
                    HeartRateChart(points: timeline, mean: stats.mean, duration: duration)
                        .frame(height: 200)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .windRunGlassCard()
            }

            StatGrid(rows: [
                [
                    Stat(title: "Avg heart rate", value: RunFormat.heartRate(stats.mean)),
                    Stat(title: "Max heart rate", value: RunFormat.heartRate(stats.maximum)),
                ],
                [
                    Stat(title: "Min heart rate", value: RunFormat.heartRate(stats.minimum)),
                    Stat(
                        title: "Variance",
                        value: RunFormat.heartRateVariance(stats.variance),
                        detail: "Std dev \(RunFormat.heartRateDeviation(stats.standardDeviation))"
                    ),
                ],
            ])
        }
    }
}

/// Stats two to a row, or one to a row at accessibility text sizes so words don't break.
private struct StatGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let rows: [[Stat]]

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: LayoutMetrics.compactSpacing) {
                ForEach(rows.flatMap { $0 }, id: \.title) { $0 }
            }
        } else {
            Grid(horizontalSpacing: LayoutMetrics.compactSpacing, verticalSpacing: LayoutMetrics.compactSpacing) {
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(rows[row], id: \.title) { $0 }
                    }
                }
            }
        }
    }
}

private struct Stat: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            if let detail {
                Text(detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        // Fill the row, so a card with a detail line doesn't stand taller than its neighbor.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .windRunGlassCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview("Run detail") {
    let container = WindRunSeed.containerWithRuns()
    let run = try! container.mainContext.fetch(FetchDescriptor<Run>()).first!
    return NavigationStack {
        RunDetailView(run: run)
    }
    .modelContainer(container)
    .environment(CoachInbox())
}
