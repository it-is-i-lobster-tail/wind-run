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
    @State private var showsEntireIntervalRun = false
    @State private var cursor: Double?
    @State private var picking = false
    @State private var expandsRoutes = false
    @AppStorage(BodyWeight.storageKey) private var bodyWeight: Double = 0

    private var axis: ComparisonAxis {
        switch group.type {
        case .intervals: showsEntireIntervalRun ? .time : .rep
        case .distance: .distance
        default: .time
        }
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
                if group.type == .intervals {
                    Picker("Workout detail", selection: $showsEntireIntervalRun) {
                        Text("Work reps").tag(false)
                        Text("Entire run").tag(true)
                    }.pickerStyle(.segmented)
                }
                ForEach(ComparisonMetric.allCases, id: \.self) { metric in
                    ComparisonPlot(metric: metric, axis: axis, unit: unit, series: series, cursor: $cursor) { legend }
                }
                routes
                summary
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
                    sessionLine(index)
                    Text(session.run.startDate, format: .dateTime.month().day())
                }.font(.subheadline.bold())
                Text(role(session.run)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sessionLine(_ index: Int) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 3))
            path.addLine(to: CGPoint(x: 20, y: 3))
        }
        .stroke(comparisonColors[index], style: StrokeStyle(lineWidth: 3, dash: comparisonDashes[index]))
        .frame(width: 20, height: 6)
        .accessibilityHidden(true)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session summaries").font(.headline)
            ViewThatFits(in: .horizontal) {
                summaryGrid
                ScrollView(.horizontal) { summaryGrid.fixedSize(horizontal: true, vertical: false) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }

    private var summaryGrid: some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 0) {
            GridRow(alignment: .bottom) {
                Text("Metric").font(.caption.bold()).gridColumnAlignment(.leading)
                ForEach(Array(series.enumerated()), id: \.element.id) { index, session in
                    VStack(alignment: .trailing, spacing: 4) {
                        sessionLine(index)
                        Text(session.run.startDate, format: .dateTime.month().day())
                        if series.contains(where: { $0.id != session.id && Calendar.current.isDate($0.run.startDate, inSameDayAs: session.run.startDate) }) {
                            Text(session.run.startDate, format: .dateTime.hour().minute()).font(.caption2)
                        }
                    }
                    .font(.caption.bold())
                }
            }
            tableHeading("Run totals")
            row("Distance") { RunFormat.distance($0.run.distanceMeters, unit: unit) }
            row("Moving time") { RunFormat.duration($0.run.activeDuration()) }
            row("Paused") { RunFormat.duration($0.run.pausedDuration()) }
            row("Average pace") { RunFormat.pace($0.run.pace(), unit: unit) }
            if series.contains(where: { !$0.work.isEmpty }) {
                tableHeading("Work intervals")
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
            tableHeading("Heart rate")
            row("Average") { RunFormat.heartRate($0.heartStats?.mean) }
            row("Minimum") { RunFormat.heartRate($0.heartStats?.minimum) }
            row("Maximum") { RunFormat.heartRate($0.heartStats?.maximum) }
            row("Steadiness") { $0.heartStats.map { RunFormat.heartRateDeviation($0.standardDeviation) } ?? "—" }
            tableHeading("Stride")
            row("Cadence") { RunFormat.cadence(Run.meanCadence(steps: $0.steps, seconds: $0.run.activeDuration())) }
            row("Steps") { $0.steps.map { RunFormat.steps($0) } ?? "—" }
            tableHeading("Elevation and energy")
            row("Climb") { $0.elevation.map { RunFormat.elevation($0.gain, unit: unit) } ?? "—" }
            row("Descent") { $0.elevation.map { RunFormat.elevation($0.loss, unit: unit) } ?? "—" }
            row("Calories") { RunFormat.calories($0.calories(bodyWeight: bodyWeight)) }
            row("Hill calories") { session in
                guard let calories = session.calories(bodyWeight: bodyWeight), let energy = session.energy else { return "—" }
                let adjustment = Int((calories * energy.hillShare).rounded())
                return "\(adjustment.formatted(.number.sign(strategy: .always(includingZero: false)))) kcal"
            }
            GridRow {
                Text("Full run").padding(.top, 8)
                ForEach(series) { session in
                    NavigationLink("Open") { RunDetailView(run: session.run) }
                        .padding(.top, 8)
                        .accessibilityLabel("Open run from \(session.run.startDate.formatted())")
                }
            }
        }
        .backgroundPreferenceValue(MetricRowBounds.self) { bounds in
            GeometryReader { proxy in
                ForEach(bounds.indices.filter { !$0.isMultiple(of: 2) }, id: \.self) { index in
                    let rect = proxy[bounds[index]]
                    Rectangle().fill(Color(uiColor: .quaternarySystemFill))
                        .frame(width: proxy.size.width, height: rect.height)
                        .position(x: proxy.size.width / 2, y: rect.midY)
                }
            }.accessibilityHidden(true).allowsHitTesting(false)
        }
        .font(.footnote.monospacedDigit())
    }

    private func tableHeading(_ name: String) -> some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func row(_ name: String, value: @escaping (ComparisonSeries) -> String) -> some View {
        GridRow {
            Text(name).padding(.vertical, 6)
                .frame(maxHeight: .infinity)
                .anchorPreference(key: MetricRowBounds.self, value: .bounds) { [$0] }
                .gridColumnAlignment(.leading)
            ForEach(series) { session in
                let reading = value(session)
                Text(reading)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("\(session.run.startDate.formatted(date: .abbreviated, time: .shortened)), \(name), \(reading)")
            }
        }
        Divider().gridCellUnsizedAxes(.horizontal)
    }

    private var routes: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack {
                Text("Routes").font(.headline)
                Spacer()
                if series.contains(where: { !$0.coordinates.isEmpty }) {
                    ExpandChartButton(title: "Routes") { expandsRoutes = true }
                }
            }
            if series.allSatisfy({ $0.coordinates.isEmpty }) { ContentUnavailableView("No recorded routes", systemImage: "map") }
            else {
                routeMap
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: LayoutMetrics.compactCornerRadius))
                    .simultaneousGesture(TapGesture().onEnded { expandsRoutes = true })
                legend
                ForEach(series.filter { $0.coordinates.isEmpty }) { session in
                    Text("\(session.run.startDate.formatted(.dateTime.month().day())) · No recorded route")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
        .fullScreenCover(isPresented: $expandsRoutes) {
            FullScreenChart(title: "Routes", unit: nil, detail: nil, supportsZoom: false) {
                VStack(alignment: .leading) {
                    legend
                    routeMap
                }
            }
        }
    }

    private var routeMap: some View {
        Map(interactionModes: [.pan, .zoom]) {
            ForEach(Array(series.enumerated().reversed()), id: \.element.id) { index, session in
                ForEach(session.coordinates.indices, id: \.self) { i in
                    let stretch = session.coordinates[i]
                    if stretch.count == 1, let point = stretch.first {
                        MapCircle(center: point, radius: 6).foregroundStyle(comparisonColors[index])
                    } else {
                        MapPolyline(coordinates: stretch)
                            .stroke(comparisonColors[index], style: StrokeStyle(lineWidth: CGFloat(3 + index * 2), dash: comparisonDashes[index]))
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .id(selected)
    }
}

private struct MetricRowBounds: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
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
        }.allowsLandscape().scrollEdgeEffectStyle(.soft, for: .all)
    }

}

private struct ComparisonPlot<Legend: View>: View {
    let metric: ComparisonMetric
    let axis: ComparisonAxis
    let unit: DistanceUnit
    let series: [ComparisonSeries]
    @Binding var cursor: Double?
    @ViewBuilder let legend: Legend
    @State private var isExpanded = false

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

    private var title: String { metric == .elevation ? "Elevation from start" : metric.rawValue }

    var body: some View {
        let hasData = series.contains { !points($0).isEmpty }
        plot(expanded: false)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .windRunGlassCard()
            .contentShape(.rect)
            .simultaneousGesture(TapGesture().onEnded { if hasData { isExpanded = true } })
            .fullScreenCover(isPresented: $isExpanded) {
                FullScreenChart(title: title, unit: metric.unit(unit), detail: nil, supportsZoom: false) {
                    VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                        legend
                        plot(expanded: true)
                    }
                }
            }
    }

    private func plot(expanded: Bool) -> some View {
        let datasets = series.map(points)
        let values = datasets.flatMap { $0.map { metric.value($0.value, unit: unit) } }
        let minY = values.min() ?? 0, maxY = values.max() ?? 1
        let pad = max((maxY - minY) * 0.15, 1)
        return VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            if !expanded {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.headline)
                    Text(metric.unit(unit)).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if let cursor { Text(xLabel(cursor)).font(.caption).foregroundStyle(.secondary) }
                    if !values.isEmpty { ExpandChartButton(title: title) { isExpanded = true } }
                }
            } else if let cursor {
                Text(xLabel(cursor)).font(.caption).foregroundStyle(.secondary)
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
                .frame(height: expanded ? nil : 148)
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
        }
    }

    private func xLabel(_ x: Double) -> String {
        switch axis {
        case .rep: "Rep \(Int(x.rounded()))"
        case .time: RunFormat.duration(max(0, x * 60))
        case .distance: RunFormat.distance(max(0, x * unit.meters), unit: unit)
        }
    }
}
