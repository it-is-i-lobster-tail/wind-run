import Charts
import SwiftData
import SwiftUI

struct ProgressHomeView: View {
    @Query(sort: \Run.startDateValue, order: .reverse) private var history: [Run]
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var minutes = false
    @State private var selectedWeek: Date?
    private var runs: [Run] { history.filter { $0.status == .complete } }

    var body: some View {
        NavigationStack {
            List {
                if runs.isEmpty {
                    ContentUnavailableView("No runs yet", systemImage: "chart.bar.xaxis", description: Text("Completed runs will appear here."))
                } else {
                    weeklyHistory
                    let groups = Dictionary(grouping: runs.filter { ProgressGroup($0) != nil }, by: { ProgressGroup($0)! })
                    Section("Repeat workouts") {
                        let keys = groups.keys.filter { $0 != .free && (groups[$0]?.count ?? 0) >= 2 }
                            .sorted { groups[$0]![0].startDate > groups[$1]![0].startDate }
                        if keys.isEmpty { Text("Complete the same workout twice to compare it.").foregroundStyle(.secondary) }
                        ForEach(keys, id: \.self) { group in
                            let attempts = groups[group]!
                            NavigationLink {
                                ProgressComparison(group: group, runs: attempts)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(group.title(unit))
                                        Text("\(attempts.count) sessions · Last \(attempts[0].startDate.formatted(.dateTime.month().day()))")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                } icon: { Image(systemName: group.type.systemImage) }
                            }
                        }
                    }
                    if let free = groups[.free] {
                        Section("Free runs") {
                            NavigationLink {
                                ProgressComparison(group: .free, runs: free)
                            } label: {
                                Label("Compare free runs", systemImage: "figure.run")
                            }
                            Text("\(free.count) individual runs").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }

    private struct Week: Identifiable {
        let id: Date
        let runs: [Run]
        var distance: Double { runs.reduce(0) { $0 + $1.distanceMeters } }
        var duration: Double { runs.reduce(0) { $0 + $1.activeDuration() } }
    }

    private var weeklyHistory: some View {
        let cal = Calendar.current
        let current = cal.dateInterval(of: .weekOfYear, for: .now)!.start
        let grouped = Dictionary(grouping: runs) { cal.dateInterval(of: .weekOfYear, for: $0.startDate)!.start }
        let weeks = (-7...0).compactMap { n -> Week? in
            guard let date = cal.date(byAdding: .weekOfYear, value: n, to: current) else { return nil }
            return Week(id: date, runs: grouped[date] ?? [])
        }
        let week = weeks.first { $0.id == selectedWeek } ?? weeks[7]
        let scaleUnit = minutes ? "min" : unit.symbol
        let weeklyTime = Duration.seconds(week.duration).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, fractionalPart: .hide(rounded: .towardZero))
        )
        return Section("Weekly history") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Weekly total", selection: $minutes) {
                    Text("Distance").tag(false)
                    Text("Time").tag(true)
                }.pickerStyle(.segmented)
                Text(minutes ? weeklyTime : RunFormat.distance(week.distance, unit: unit))
                    .font(.largeTitle.bold()).monospacedDigit()
                Text("Week of \(week.id.formatted(.dateTime.month().day()))\(week.id == current ? " · so far" : "")")
                    .font(.subheadline).foregroundStyle(.secondary)
                Chart(weeks) { value in
                    BarMark(x: .value("Week", value.id, unit: .weekOfYear),
                            y: .value(minutes ? "Minutes" : unit.symbol, minutes ? value.duration / 60 : value.distance / unit.meters))
                        .cornerRadius(4).foregroundStyle(value.id == week.id ? Color.accentColor : Color.secondary.opacity(0.35))
                }
                .chartXSelection(value: Binding(get: { selectedWeek }, set: { date in
                    if let date { selectedWeek = cal.dateInterval(of: .weekOfYear, for: date)?.start }
                }))
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { mark in
                        AxisGridLine()
                        if let value = mark.as(Double.self) {
                            // Anchor the zero numeral on its gridline, with the unit on the line below.
                            AxisValueLabel(anchor: UnitPoint(x: 0, y: value == 0 ? 0.25 : 0.5)) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(value, format: .number)
                                    if value == 0 { Text(scaleUnit) }
                                }
                            }
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { AxisValueLabel(format: .dateTime.month().day()) } }
                .frame(height: 108)
            }.padding(.vertical, 6)
            NavigationLink("\(week.runs.count) runs this week") {
                List(week.runs) { run in
                    NavigationLink { RunDetailView(run: run) } label: {
                        LabeledContent(run.startDate.formatted(.dateTime.weekday().month().day()), value: RunFormat.distance(run.distanceMeters, unit: unit))
                    }
                }.navigationTitle("Week of \(week.id.formatted(.dateTime.month().day()))")
            }
        }
    }
}
