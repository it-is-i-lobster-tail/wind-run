import Charts
import MapKit
import SwiftUI

private let comparisonColors: [Color] = [.accentColor, .secondary, .purple]
private let comparisonDashes: [[CGFloat]] = [[], [6, 4], [2, 4]]

struct ProgressComparison: View {
    let group: ProgressGroup
    let runs: [Run]
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var selected: [UUID] = []
    @State private var bestID: UUID?
    @State private var series: [ComparisonSeries] = []
    @State private var axis: ComparisonAxis = .time
    @State private var cursor: Double?
    @State private var picking = false
    @AppStorage(BodyWeight.storageKey) private var bodyWeight: Double = 0

    private var axes: [ComparisonAxis] {
        group.type == .intervals ? [.rep, .time, .distance] : [.time, .distance]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                HStack {
                    Text(group == .free ? "Individual free runs" : group.type.name)
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Change sessions", systemImage: "slider.horizontal.3") {
                        picking = true
                    }.font(.subheadline)
                }
                legend
                Picker("Compare by", selection: $axis) {
                    ForEach(axes, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                ForEach(ComparisonMetric.allCases, id: \.self) { metric in
                    ComparisonPlot(metric: metric, axis: axis, unit: unit, series: series, cursor: $cursor)
                }
                NavigationLink { summary } label: {
                    Label("Session summaries", systemImage: "tablecells")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered)
                NavigationLink { routes } label: {
                    Label("Route maps", systemImage: "map")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered)
            }.padding()
        }
        .navigationTitle(group.title(unit))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: axis) { cursor = nil }
        .task {
            guard selected.isEmpty else { return }
            let best = runs.compactMap { r in group.rank(r).map { (r.runID, $0) } }.min { $0.1 < $1.1 }?.0
            bestID = best
            var ids = Array(runs.prefix(group == .free ? 1 : 2).map(\.runID))
            if let best, !ids.contains(best) { ids.append(best) }
            axis = group.type == .intervals ? .rep : group.type == .distance ? .distance : .time
            apply(ids)
            if group == .free, runs.count > 1 { picking = true }
        }
        .sheet(isPresented: $picking) {
            SessionPicker(group: group, runs: runs, unit: unit, role: role, initial: selected, apply: apply)
        }
        .traceScreen("Compare runs")
    }

    private func apply(_ ids: [UUID]) {
        let previous = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        let chosen = runs.filter { ids.contains($0.runID) }
        selected = chosen.map(\.runID)
        series = chosen.map { previous[$0.runID] ?? ComparisonSeries($0) }
        cursor = nil
    }

    private func role(_ run: Run) -> String {
        guard group != .free else { return RunFormat.distance(run.distanceMeters, unit: unit) }
        var roles: [String] = []
        if runs.first?.runID == run.runID { roles.append("Latest") }
        else if runs.dropFirst().first?.runID == run.runID { roles.append("Previous") }
        if run.runID == bestID { roles.append("Best") }
        return roles.joined(separator: " · ")
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { legendItems }
            VStack(alignment: .leading, spacing: 8) { legendItems }
        }
    }

    @ViewBuilder private var legendItems: some View {
        ForEach(Array(series.enumerated()), id: \.element.id) { index, session in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Path { p in p.move(to: CGPoint(x: 0, y: 3)); p.addLine(to: CGPoint(x: 20, y: 3)) }
                        .stroke(comparisonColors[index], style: StrokeStyle(lineWidth: 3, dash: comparisonDashes[index]))
                        .frame(width: 20, height: 6)
                    Text(session.run.startDate, format: .dateTime.month().day())
                }.font(.subheadline.bold())
                Text(role(session.run)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var summary: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .trailing, horizontalSpacing: 13, verticalSpacing: 14) {
                GridRow {
                    Text("Session")
                    ForEach(series) { s in Text(s.run.startDate, format: .dateTime.month().day()) }
                }.font(.subheadline.bold())
                Divider()
                row("Distance") { RunFormat.distance($0.run.distanceMeters, unit: unit) }
                row("Moving time") { RunFormat.duration($0.run.activeDuration()) }
                row("Paused") { RunFormat.duration($0.run.pausedDuration()) }
                row("Average pace") { RunFormat.pace($0.run.pace(), unit: unit) }
                if series.contains(where: { !$0.work.isEmpty }) {
                    row("Work time") { s in s.work.isEmpty ? "—" : RunFormat.duration(s.work.reduce(0) { $0 + $1.seconds }) }
                }
                if group.type == .intervals, case .plan(let plan) = group {
                    let work = plan.timeline.enumerated().filter { $0.element.kind == .work && !$0.element.isWalk }
                    ForEach(Array(work.enumerated()), id: \.element.offset) { index, step in
                        row("Rep \(index + 1)") { session in
                            guard let rep = session.work.first(where: { $0.id == step.offset }) else { return "—" }
                            if case .time = step.element.goal { return RunFormat.distance(rep.meters, unit: unit) }
                            return RunFormat.duration(rep.seconds)
                        }
                    }
                }
                row("Avg HR") { RunFormat.heartRate($0.heartStats?.mean) }
                row("Min HR") { RunFormat.heartRate($0.heartStats?.minimum) }
                row("Max HR") { RunFormat.heartRate($0.heartStats?.maximum) }
                row("Cadence") { RunFormat.cadence(Run.meanCadence(steps: $0.steps, seconds: $0.run.activeDuration())) }
                row("Steps") { $0.steps.map { RunFormat.steps($0) } ?? "—" }
                row("Climb") { $0.elevation.map { RunFormat.elevation($0.gain, unit: unit) } ?? "—" }
                row("Descent") { $0.elevation.map { RunFormat.elevation($0.loss, unit: unit) } ?? "—" }
                row("HR steadiness") { $0.heartStats.map { RunFormat.heartRateDeviation($0.standardDeviation) } ?? "—" }
                row("Calories") { RunFormat.calories($0.calories(bodyWeight: bodyWeight)) }
                row("Hill calories") { session in
                    guard let calories = session.calories(bodyWeight: bodyWeight), let energy = session.energy else { return "—" }
                    let adjustment = Int((calories * energy.hillShare).rounded())
                    return "\(adjustment.formatted(.number.sign(strategy: .always(includingZero: false)))) kcal"
                }
                Divider()
                GridRow {
                    Text("Full run")
                    ForEach(series) { s in NavigationLink("Open") { RunDetailView(run: s.run) } }
                }
            }.font(.subheadline.monospacedDigit()).padding()
        }.navigationTitle("Session summaries")
    }

    private func row(_ name: String, value: @escaping (ComparisonSeries) -> String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            ForEach(series) { s in Text(value(s)) }
        }
    }

    private var routes: some View {
        VStack(alignment: .leading) {
            legend.padding()
            if series.allSatisfy({ $0.coordinates.isEmpty }) { ContentUnavailableView("No recorded routes", systemImage: "map") }
            else {
                Map {
                    ForEach(Array(series.enumerated().reversed()), id: \.element.id) { index, session in
                        ForEach(session.coordinates.indices, id: \.self) { i in
                            MapPolyline(coordinates: session.coordinates[i])
                                .stroke(comparisonColors[index], style: StrokeStyle(lineWidth: CGFloat(3 + index * 2), dash: comparisonDashes[index]))
                        }
                    }
                }
            }
        }.navigationTitle("Route maps")
    }
}

private struct SessionPicker: View {
    let group: ProgressGroup
    let runs: [Run]
    let unit: DistanceUnit
    let role: (Run) -> String
    let apply: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing: [UUID]

    init(group: ProgressGroup, runs: [Run], unit: DistanceUnit, role: @escaping (Run) -> String,
         initial: [UUID], apply: @escaping ([UUID]) -> Void) {
        self.group = group
        self.runs = runs
        self.unit = unit
        self.role = role
        self.apply = apply
        _editing = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(runs) { run in
                        let checked = editing.contains(run.runID)
                        Button {
                            if checked { editing.removeAll { $0 == run.runID } }
                            else if editing.count < 3 { editing.append(run.runID) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(run.startDate, format: .dateTime.month().day().year().hour().minute())
                                    Text("\(RunFormat.distance(run.distanceMeters, unit: unit)) · \(RunFormat.duration(run.activeDuration()))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if group != .free { Text(role(run)).font(.caption) }
                                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked ? Color.accentColor : .secondary)
                            }
                        }.disabled(!checked && editing.count == 3)
                        .accessibilityAddTraits(checked ? .isSelected : [])
                    }
                } header: { Text("Choose up to three") } footer: {
                    if let label = group.bestLabel { Text("Best · \(label)") }
                }
            }
            .navigationTitle(group == .free ? "Choose free runs" : "Compare sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Compare") { apply(editing); dismiss() }.disabled(editing.isEmpty)
                }
            }
        }.scrollEdgeEffectStyle(.soft, for: .all)
    }

}

private struct ComparisonPlot: View {
    let metric: ComparisonMetric
    let axis: ComparisonAxis
    let unit: DistanceUnit
    let series: [ComparisonSeries]
    @Binding var cursor: Double?

    private func points(_ s: ComparisonSeries) -> [ComparisonPoint] {
        if axis == .distance && s.coordinates.isEmpty { return [] }
        return (axis == .rep ? s.reps : s.lines)[metric] ?? []
    }

    private var domain: ClosedRange<Double> {
        switch axis {
        case .rep: return 1...Double(max(2, series.map(\.repCount).max() ?? 2))
        case .time: return 0...max(1, (series.map { $0.run.activeDuration() }.max() ?? 0) / 60)
        case .distance: return 0...max(0.1, (series.map { $0.run.distanceMeters }.max() ?? 0) / unit.meters)
        }
    }

    var body: some View {
        let datasets = series.map(points)
        let values = datasets.flatMap { $0.map { metric.value($0.value, unit: unit) } }
        let minY = values.min() ?? 0, maxY = values.max() ?? 1
        let pad = max((maxY - minY) * 0.15, 1)
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric == .elevation ? "Elevation from start" : metric.rawValue).font(.headline)
                Text(metric.unit(unit)).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let cursor { Text(xLabel(cursor)).font(.caption).foregroundStyle(.secondary) }
            }
            if values.isEmpty {
                Text("No recorded \(metric.rawValue.lowercased()) for this comparison.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(datasets.indices, id: \.self) { i in
                        ForEach(datasets[i]) { p in
                            let x = axis.x(p, unit: unit)
                            let y = metric.value(p.value, unit: unit)
                            LineMark(x: .value("Position", x), y: .value(metric.rawValue, y),
                                     series: .value("Session segment", "\(i)-\(p.segment)"))
                                .foregroundStyle(comparisonColors[i])
                                .lineStyle(StrokeStyle(lineWidth: 2.2, dash: comparisonDashes[i]))
                            if axis == .rep {
                                PointMark(x: .value("Rep", x), y: .value(metric.rawValue, y))
                                    .foregroundStyle(comparisonColors[i]).symbolSize(30)
                            }
                        }
                    }
                    if let cursor { RuleMark(x: .value("Selection", cursor)).foregroundStyle(.secondary.opacity(0.5)) }
                }
                .chartXScale(domain: domain, range: .plotDimension(startPadding: 8, endPadding: 8))
                .chartYScale(domain: (minY - pad)...(maxY + pad))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        if let v = value.as(Double.self) { AxisValueLabel { Text(metric.label(v)) } }
                    }
                }
                .chartXAxis {
                    if axis == .rep { AxisMarks(values: .stride(by: max(1, (domain.upperBound / 8).rounded(.up)))) { AxisValueLabel(centered: false) } }
                    else { AxisMarks(values: .automatic(desiredCount: 4)) }
                }
                .chartXAxisLabel(axis == .rep ? "Work rep" : axis == .time ? "Moving time (min)" : "Distance (\(unit.symbol))")
                .chartXSelection(value: Binding(get: { cursor }, set: { if let x = $0 { cursor = axis == .rep ? x.rounded() : x } }))
                .frame(height: 148)
                if cursor != nil || datasets.contains(where: \.isEmpty) {
                    ForEach(series.indices, id: \.self) { index in
                        if let cursor, let first = datasets[index].first, let last = datasets[index].last,
                           cursor >= axis.x(first, unit: unit), cursor <= axis.x(last, unit: unit),
                           let nearest = datasets[index].min(by: { abs(axis.x($0, unit: unit) - cursor) < abs(axis.x($1, unit: unit) - cursor) }) {
                            Text("\(series[index].run.startDate.formatted(.dateTime.month().day())) · \(metric.label(metric.value(nearest.value, unit: unit))) \(metric.unit(unit))").font(.caption)
                        } else if datasets[index].isEmpty {
                            Text("\(series[index].run.startDate.formatted(.dateTime.month().day())) · No data").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).windRunGlassCard()
    }

    private func xLabel(_ x: Double) -> String {
        switch axis {
        case .rep: "Rep \(Int(x.rounded()))"
        case .time: RunFormat.duration(max(0, x * 60))
        case .distance: RunFormat.distance(max(0, x * unit.meters), unit: unit)
        }
    }
}
