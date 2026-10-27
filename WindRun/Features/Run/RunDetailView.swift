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
    /// Set when this is the summary shown straight after finishing: it closes with Done instead of
    /// offering to delete, since the run screen underneath still holds the run.
    var done: (() -> Void)?

    @State private var isConfirmingDelete = false
    /// Set once the run is deleted, so nothing reads it while the screen closes.
    @State private var isDeleted = false
    /// Worked out once from the route, which can hold thousands of fixes.
    @State private var summary: Summary?

    init(run: Run, openCoach: ((CoachSheet) -> Void)? = nil, done: (() -> Void)? = nil) {
        self.run = run
        self.openCoach = openCoach
        self.done = done
    }

    /// What the page draws, worked out from the run's route, steps and heart rate.
    private struct Summary {
        let sections: [RunSection]
        let segments: [RouteSegment]
        let pace: [PacePoint]
        let elevation: ElevationSummary?

        init(_ run: Run) {
            sections = run.sections
            segments = run.routeSegments(sections: sections)
            pace = run.paceTimeline
            elevation = run.elevation
        }
    }

    var body: some View {
        if isDeleted {
            Color.clear
        } else {
            details
                // Before the first frame, so the map doesn't pop in after the numbers.
                .onAppear { if summary == nil { summary = Summary(run) } }
        }
    }

    /// "Intervals · 4 × 4 min", "Coach · Long run" or "Run".
    private var caption: String {
        let name = run.coachWorkout?.title ?? run.intervalPlan?.name
        return [run.kind.name, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var details: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.sectionSpacing) {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let segments = summary?.segments, !segments.isEmpty {
                    Map(interactionModes: [.zoom, .pan]) {
                        // Easy steps first, so the hard ones draw on top where they meet.
                        ForEach(segments.sorted { !$0.isWork && $1.isWork }) { segment in
                            MapPolyline(coordinates: segment.coordinates)
                                .stroke(segment.isWork || summary?.sections.isEmpty == true ? AnyShapeStyle(.tint) : AnyShapeStyle(.gray), lineWidth: 5)
                        }
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
                        Stat(title: "Avg pace", value: RunFormat.pace(run.pace(), unit: unit)),
                        elevationStat,
                    ],
                ] + stepRows)

                if let sections = summary?.sections, sections.count > 1 {
                    SectionPaceBars(sections: sections, unit: unit)
                }

                if let pace = summary?.pace, pace.count > 1 {
                    ChartCard(title: "Pace") {
                        PaceChart(
                            points: pace,
                            average: run.pace(),
                            duration: run.activeDuration(),
                            sections: summary?.sections ?? [],
                            unit: unit
                        )
                        .frame(height: 180)
                    }
                }

                if let heartRate = run.heartRateStats {
                    HeartRateSummary(
                        timeline: run.heartRateTimeline,
                        stats: heartRate,
                        duration: run.activeDuration(),
                        sections: summary?.sections ?? []
                    )
                }

                if let elevation = summary?.elevation, elevation.profile.count > 1 {
                    ChartCard(
                        title: "Elevation",
                        detail: "\(RunFormat.elevation(elevation.gain, unit: unit, sign: .plus))  \(RunFormat.elevation(elevation.loss, unit: unit, sign: .minus))"
                    ) {
                        ElevationChart(
                            points: elevation.profile,
                            duration: run.activeDuration(),
                            sections: summary?.sections ?? [],
                            unit: unit
                        )
                        .frame(height: 120)
                    }
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
            if let done {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete run", systemImage: "trash") {
                        isConfirmingDelete = true
                    }
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

    /// The climb, with the drop under it, or a dash when the route has no good altitude.
    private var elevationStat: Stat {
        guard let elevation = summary?.elevation else { return Stat(title: "Elevation", value: "–") }
        return Stat(
            title: "Elevation",
            value: RunFormat.elevation(elevation.gain, unit: unit, sign: .plus),
            detail: RunFormat.elevation(elevation.loss, unit: unit, sign: .minus)
        )
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

/// A titled card holding one of the run's charts.
private struct ChartCard<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }
}

/// The run's heart rate over time, then its lowest, highest, mean and spread.
private struct HeartRateSummary: View {
    let timeline: [HeartRatePoint]
    let stats: HeartRateStats
    let duration: TimeInterval
    var sections: [RunSection] = []

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            // A line needs two readings.
            if timeline.count > 1 {
                ChartCard(title: "Heart rate") {
                    HeartRateChart(points: timeline, mean: stats.mean, duration: duration, sections: sections)
                        .frame(height: 200)
                }
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
    let run = try! container.mainContext.fetch(FetchDescriptor<Run>()).first { $0.kind == .free }!
    return NavigationStack {
        RunDetailView(run: run)
    }
    .modelContainer(container)
    .environment(CoachInbox())
}

#Preview("Interval run summary") {
    let container = WindRunSchema.makeContainer(inMemory: true)
    let run = WindRunSeed.intervalRun(in: container.mainContext)
    return NavigationStack {
        RunDetailView(run: run, done: {})
    }
    .modelContainer(container)
    .environment(CoachInbox())
}
