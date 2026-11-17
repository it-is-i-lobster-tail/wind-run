//
//  RunDetailView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

struct RunDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(WindRunStore.iCloudSyncKey) private var syncsWithICloud = false
    @AppStorage(BodyWeight.storageKey) private var bodyWeight: Double = 0
    @Query private var coachPlans: [CoachPlan]

    let run: Run
    /// Set when this is the summary shown straight after finishing: it closes with Done instead of
    /// offering to delete, since the run screen underneath still holds the run.
    var done: (() -> Void)?

    @State private var isConfirmingDelete = false
    @State private var isReportingInjury = false
    /// Set once the run is deleted, so nothing reads it while the screen closes.
    @State private var isDeleted = false
    /// Worked out once from the route, which can hold thousands of fixes.
    @State private var summary: Summary?

    init(run: Run, done: (() -> Void)? = nil) {
        self.run = run
        self.done = done
    }

    /// The runner's coach plan, once the terms are accepted.
    private var coachPlan: CoachPlan? {
        TermsAcceptance.isCurrent() ? coachPlans.active : nil
    }

    /// What the page draws, worked out from the run's route, steps and heart rate.
    private struct Summary {
        let sections: [RunSection]
        let routes: [ColoredRoute]
        let pace: [PacePoint]
        let cadence: [CadencePoint]
        let elevation: ElevationSummary?
        let calories: CalorieEstimate?
        let heartRate: [HeartRatePoint]
        let heartRateStats: HeartRateStats?
        /// Steps and steps a minute, decoded once rather than on every redraw.
        let steps: Double?
        let meanCadence: Double?
        /// How many fixes were taken while running, for the trace.
        let fixCount: Int

        /// Walks the route once: the map, the pace chart, the climb and the calories all share its fixes
        /// and heights.
        init(_ run: Run) {
            let fixes = run.activeRoute
            let track = run.altitudeTrack(for: fixes)
            let cadence = run.cadenceTimeline
            fixCount = fixes.count
            sections = run.sections
            routes = Run.coloredRoutes(fixes: fixes, track: track, cadence: cadence)
            pace = Run.paceTimeline(fixes)
            self.cadence = cadence
            elevation = Run.elevation(track)
            calories = CalorieEstimator.estimate(Run.energyLegs(fixes: fixes, track: track))
            heartRate = run.heartRateTimeline
            heartRateStats = Run.heartRateStats(of: heartRate)
            steps = run.stepTotal
            let seconds = run.activeDuration()
            meanCadence = steps.flatMap { seconds > 0 ? $0 / seconds * 60 : nil }
        }
    }

    var body: some View {
        if isDeleted {
            Color.clear
        } else {
            details
                // Before the first frame, so the map doesn't pop in after the numbers.
                .onAppear { if summary == nil { buildSummary() } }
        }
    }

    /// "Run summary" straight after finishing, "Run detail" when opened from the list, so a trace tells the
    /// two apart.
    private var screen: String {
        done == nil ? "Run detail" : "Run summary"
    }

    private func buildSummary() {
        let started = ContinuousClock.now
        let built = Summary(run)
        summary = built
        // Counts and time only: no places or heart rates.
        Trace.log(.screen, "Run summary built", [
            "screen": screen,
            "ms": Int((ContinuousClock.now - started) / .milliseconds(1)),
            "fixes": built.fixCount,
            "routes": built.routes.count,
            "segments": built.routes.map { $0.segments.count }.max() ?? 0,
            "pacePoints": built.pace.count,
            "cadencePoints": built.cadence.count,
            "heartRatePoints": built.heartRate.count,
            "sections": built.sections.count,
            "hasElevation": built.elevation != nil,
            "hasCalories": built.calories != nil,
        ])
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

                if let routes = summary?.routes, !routes.isEmpty {
                    RouteMapCard(routes: routes)
                }

                StatGrid(rows: [
                    [
                        Stat(title: "Distance", value: RunFormat.distance(run.distanceMeters, unit: unit)),
                        Stat(
                            title: "Avg pace",
                            value: RunFormat.pace(run.pace(), unit: unit),
                            spoken: SpokenFormat.pace(run.pace(), unit: unit) ?? "none"
                        ),
                    ],
                    [
                        // Running time; stops at lights and the like are in Time paused.
                        Stat(
                            title: "Moving time",
                            value: RunFormat.duration(run.activeDuration()),
                            detail: run.pausedDuration() >= 1 ? "Total \(RunFormat.duration(run.activeDuration() + run.pausedDuration()))" : nil,
                            spoken: SpokenFormat.duration(run.activeDuration())
                        ),
                        Stat(
                            title: "Time paused",
                            value: RunFormat.duration(run.pausedDuration()),
                            spoken: SpokenFormat.duration(run.pausedDuration())
                        ),
                    ],
                    [elevationStat, caloriesStat],
                ] + stepRows)

                if let sections = summary?.sections, sections.count > 1 {
                    SectionPaceBars(sections: sections, unit: unit)
                }

                if let pace = summary?.pace, pace.count > 1 {
                    ChartCard(title: "Pace", unit: "min/\(unit.symbol)", legend: workLegend) {
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

                if let elevation = summary?.elevation, elevation.profile.count > 1 {
                    ChartCard(
                        // Without a GPS level the barometer only knows the climb, so 0 is the start, not the sea.
                        title: elevation.isRelative ? "Height from start" : "Elevation",
                        unit: unit == .miles ? "ft" : "m",
                        detail: "\(RunFormat.elevation(elevation.gain, unit: unit, sign: .plus))  \(RunFormat.elevation(elevation.loss, unit: unit, sign: .minus))",
                        legend: workLegend
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

                if let cadence = summary?.cadence, cadence.count > 1 {
                    ChartCard(title: "Cadence", unit: "spm", legend: workLegend) {
                        CadenceChart(
                            points: cadence,
                            mean: summary?.meanCadence,
                            duration: run.activeDuration(),
                            sections: summary?.sections ?? []
                        )
                        .frame(height: 140)
                    }
                }

                if let summary, let heartRate = summary.heartRateStats {
                    HeartRateSummary(
                        timeline: summary.heartRate,
                        stats: heartRate,
                        duration: run.activeDuration(),
                        sections: summary.sections
                    )
                }

                if coachPlan != nil, run.status == .complete {
                    Button("Report injury", systemImage: "bandage") {
                        Trace.tap(screen, "Report injury")
                        isReportingInjury = true
                    }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                }

                if run.healthWorkoutID != nil {
                    Label("Saved to Apple Health", systemImage: "heart")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                RecordingDetails(run: run, unit: unit)
            }
            .padding()
        }
        .clearsFloatingBar()
        .navigationTitle(run.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen(screen)
        .toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Trace.tap(screen, "Done")
                        done()
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete run", systemImage: "trash") {
                        Trace.tap(screen, "Delete run")
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
        .sheet(isPresented: $isReportingInjury) {
            if let coachPlan {
                BuildReportInjuryView(perform: { call in
                    _ = BuildService(context: modelContext).perform(on: coachPlan, call)
                }, runID: run.runID)
            }
        }
    }

    /// The key under each chart, naming the work bands when the run had hard steps.
    private var workLegend: [ChartLegend.Item] {
        summary?.sections.contains(where: \.isWork) == true ? [.workSections] : []
    }

    /// Steps and mean cadence, when the run counted steps.
    private var stepRows: [[Stat]] {
        guard let summary, let steps = summary.steps else { return [] }
        return [[
            Stat(title: "Steps", value: RunFormat.steps(steps)),
            Stat(title: "Cadence", value: RunFormat.cadence(summary.meanCadence)),
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

    /// Calories with what the hills added or the downhills saved, or a nudge to give a weight. A run that
    /// finished before a weight was given uses the weight given since.
    private var caloriesStat: Stat {
        let estimate = summary?.calories
        let weight = BodyWeight.range.contains(bodyWeight) ? bodyWeight : nil
        guard let calories = run.activeCalories ?? weight.flatMap({ estimate?.kilocalories(bodyMass: $0) }) else {
            return Stat(title: "Calories", value: "–", detail: estimate == nil ? nil : "Add your weight in Settings")
        }
        return Stat(
            title: "Calories",
            value: RunFormat.calories(calories),
            detail: estimate.flatMap { RunFormat.hillCalories(calories * $0.hillShare) }
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
        if coachPlan != nil {
            lines.append("Your coach will plan as if you hadn't run it.")
        }
        if run.healthWorkoutID != nil, !canDeleteFromHealth {
            lines.append("Its workout stays in Apple Health.")
        }
        return lines.joined(separator: " ")
    }

    private func delete(fromHealth: Bool) {
        Trace.tap(screen, "Delete this run?: Delete", ["fromHealth": fromHealth])
        isDeleted = true
        dismiss()
        RunDeletion(context: modelContext).delete(run, fromHealth: fromHealth)
    }
}

/// A titled card holding one of the run's charts, with what its values are measured in after the title
/// and a key under it.
private struct ChartCard<Content: View>: View {
    let title: String
    var unit: String? = nil
    var detail: String? = nil
    var legend: [ChartLegend.Item] = []
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                if let unit {
                    Text("\(title) \(Text("(\(unit))").foregroundStyle(.secondary))")
                        .font(.headline)
                } else {
                    Text(title)
                        .font(.headline)
                }
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            content
            if !legend.isEmpty {
                ChartLegend(items: legend)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }
}

/// The run's heart rate over time, then its lowest, highest, mean and spread after the first minutes.
private struct HeartRateSummary: View {
    let timeline: [HeartRatePoint]
    let stats: HeartRateStats
    let duration: TimeInterval
    var sections: [RunSection] = []

    private var legend: [ChartLegend.Item] {
        (sections.contains(where: \.isWork) ? [.workSections] : [])
            + (HeartRateChart.hasSettlingStretch(timeline) ? [.heartRateSettling] : [])
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            // A line needs two readings.
            if timeline.count > 1 {
                ChartCard(title: "Heart rate", unit: "bpm", legend: legend) {
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
                    // The standard deviation, in plain beats a minute.
                    Stat(
                        title: "Steadiness",
                        value: RunFormat.heartRateDeviation(stats.standardDeviation),
                        detail: "How far it moved from your average",
                        spoken: "plus or minus \(Int(stats.standardDeviation.rounded())) beats a minute"
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
                        // A stat on its own takes the whole row.
                        ForEach(rows[row], id: \.title) { $0.gridCellColumns(rows[row].count == 1 ? 2 : 1) }
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
    /// The value as VoiceOver should say it, where the screen's form reads badly: "32:10" can sound like
    /// a time of day, and "/km" like a fraction.
    var spoken: String? = nil

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([spoken ?? value, detail].compactMap { $0 }.joined(separator: ", "))
    }
}

#Preview("Run detail") {
    let container = WindRunSeed.containerWithRuns()
    let run = try! container.mainContext.fetch(FetchDescriptor<Run>()).first { $0.kind == .free }!
    return NavigationStack {
        RunDetailView(run: run)
    }
    .modelContainer(container)
}

#Preview("Interval run summary") {
    let container = WindRunSchema.makeContainer(inMemory: true)
    let run = WindRunSeed.intervalRun(in: container.mainContext)
    return NavigationStack {
        RunDetailView(run: run, done: {})
    }
    .modelContainer(container)
}

/// Which devices made the run, with their versions, and Apple's own distance when a workout session gave one.
/// Folded away, since it's mostly for checking a recording rather than the run itself.
private struct RecordingDetails: View {
    let run: Run
    let unit: DistanceUnit

    @State private var isExpanded = false

    var body: some View {
        // Decoded once for the whole section.
        let devices = run.devices
        let apple = run.appleDistanceMeters.flatMap { $0 > 0 ? $0 : nil }
        if devices != nil || apple != nil {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    if let devices {
                        Text("Recorded on \(Self.describe(devices.recorder))")
                        ForEach(devices.heartRate, id: \.self) { device in
                            Text("Heart rate from \(Self.describe(device))")
                        }
                        if let receiver = devices.receivedBy {
                            Text("Sent to \(Self.describe(receiver))")
                        }
                    }
                    if let apple {
                        Text("\(devices?.recorder.kind.name ?? "Apple's workout") measured \(RunFormat.distance(apple, unit: unit)). The distance above is Wind Run's own GPS measure.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                Text("Recording details")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .onChange(of: isExpanded) { _, open in
                Trace.changed("Run detail", "Recording details", to: open)
            }
        }
    }

    /// "iPhone (iPhone17,1, iOS 26.1.0, Wind Run 0.2.0 (57))".
    static func describe(_ device: DeviceInfo) -> String {
        let parts = [device.manufacturer, device.model, device.system, device.firmware.map { "firmware \($0)" }, device.app.map { "Wind Run \($0)" }]
            .compactMap { $0 }
        return parts.isEmpty ? device.kind.name : "\(device.kind.name) (\(parts.joined(separator: ", ")))"
    }
}
