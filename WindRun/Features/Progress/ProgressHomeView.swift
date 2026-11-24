import Charts
import SwiftData
import SwiftUI

struct ProgressHomeView: View {
    @Query(sort: \Run.startDateValue, order: .reverse) private var history: [Run]
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var minutes = false
    @State private var expandsHistory = false
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
                        let keys = groups.keys.filter { !$0.isOpen && (groups[$0]?.count ?? 0) >= 2 }
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
                                } icon: { Image(systemName: group.sport == .cycling ? group.sport.systemImage : group.type.systemImage) }
                            }
                        }
                    }
                    ForEach([ProgressGroup.free, .cycling], id: \.self) { group in
                        if let sessions = groups[group] {
                            Section(group.title(unit)) {
                                NavigationLink {
                                    ProgressComparison(group: group, runs: sessions)
                                } label: {
                                    Label(group == .cycling ? "Compare rides" : "Compare free runs", systemImage: group.sport.systemImage)
                                }
                                Text("\(sessions.count) sessions").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
        .allowsLandscape()
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
        return Section("Weekly history") {
            weeklyPanel(weeks: weeks, current: current, expanded: false)
                .padding(.vertical, 6)
                .chartFullScreenCover(isPresented: $expandsHistory) {
                    FullScreenChart(title: minutes ? "Weekly moving time" : "Weekly distance", unit: nil, detail: nil) {
                        weeklyPanel(weeks: weeks, current: current, expanded: true)
                    }
                }
            NavigationLink("\(week.runs.count) workouts this week") {
                List(week.runs) { run in
                    NavigationLink { RunDetailView(run: run) } label: {
                        LabeledContent(run.startDate.formatted(.dateTime.weekday().month().day()), value: RunFormat.distance(run.distanceMeters, unit: unit))
                    }
                }.navigationTitle("Week of \(week.id.formatted(.dateTime.month().day()))")
            }
        }
    }

    private func weeklyPanel(weeks: [Week], current: Date, expanded: Bool) -> some View {
        let week = weeks.first { $0.id == selectedWeek } ?? weeks[7]
        let weeklyTime = Duration.seconds(week.duration).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, fractionalPart: .hide(rounded: .towardZero))
        )
        return VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            if !expanded { Text(minutes ? "Weekly moving time" : "Weekly distance").font(.headline) }
            Picker("Weekly total", selection: $minutes) {
                Text("Distance").tag(false)
                Text("Time").tag(true)
            }.pickerStyle(.segmented)
            HStack {
                Text(minutes ? weeklyTime : RunFormat.distance(week.distance, unit: unit))
                    .font(expanded ? .headline : .largeTitle.bold()).monospacedDigit()
                Spacer()
                if !expanded { ExpandChartButton(title: "Weekly history") { expandsHistory = true } }
            }
            Text("Week of \(week.id.formatted(.dateTime.month().day()))\(week.id == current ? " · so far" : "")")
                .font(.subheadline).foregroundStyle(.secondary)
            if expanded {
                weekChart(weeks: weeks, selected: week.id)
            } else {
                weekChart(weeks: weeks, selected: week.id)
                    .frame(height: 108)
                    .environment(\.expandRunChart, $expandsHistory)
            }
        }
    }

    private func weekChart(weeks: [Week], selected: Date) -> some View {
        let scaleUnit = minutes ? "min" : unit.symbol
        let cal = Calendar.current
        let start = weeks[0].id
        let end = cal.dateInterval(of: .weekOfYear, for: weeks[7].id)!.end
        return ZoomableChart(domain: start.timeIntervalSinceReferenceDate...end.timeIntervalSinceReferenceDate,
                             minimumSpan: 7 * 86_400) { window in
            Chart(weeks) { value in
                BarMark(x: .value("Week", value.id, unit: .weekOfYear),
                        y: .value(minutes ? "Minutes" : unit.symbol, minutes ? value.duration / 60 : value.distance / unit.meters))
                    .cornerRadius(4).foregroundStyle(value.id == selected ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .chartXScale(domain: Date(timeIntervalSinceReferenceDate: window.lowerBound)...Date(timeIntervalSinceReferenceDate: window.upperBound))
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
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: window.upperBound - window.lowerBound > 35 * 86_400 ? 2 : 1)) { AxisValueLabel(format: .dateTime.month().day()) } }
        }
    }
}
