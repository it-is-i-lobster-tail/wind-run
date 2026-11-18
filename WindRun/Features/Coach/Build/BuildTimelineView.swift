//
//  BuildTimelineView.swift
//  Wind Run
//

import Charts
import SwiftUI

/// The weeks to the goal date as bars: building weeks in the accent, easy weeks lighter, the peak as a dashed line,
/// and the climb under it when the goal has climb. Weeks already run show what was done.
struct BuildTimelineChart: View {
    let timeline: BuildTimeline
    let unit: DistanceUnit
    /// Weeks already run, with what was done, before the timeline's own weeks.
    var done: [TimelineWeek] = []
    /// The last week that's over: it and the weeks before it show what was run, in their own color.
    var runThrough: Int?
    /// Tapping a week, for "I'll add them": nil when weeks can't be tapped.
    var onTapWeek: ((Int) -> Void)?

    @State private var tapped = 0

    private var weeks: [TimelineWeek] { done + timeline.weeks }

    /// Building weeks in the accent, easy and event weeks lighter, recovery weeks and weeks already run in grays, as
    /// plain colors so every chart draws them the same.
    private static let buildingColor = Color.accentColor
    private static let easyColor = Color.accentColor.opacity(0.35)
    private static let recoveryColor = Color.secondary.opacity(0.35)
    private static let runColor = Color.primary.opacity(0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Distance a week", peak: "Peak \(unit.weekly(timeline.peak.meters))")
            chart(value: { $0.meters / unit.meters }, describe: { unit.weekly($0.meters) }, peak: timeline.peak.meters / unit.meters, height: 170, flagsEvent: true)
                .accessibilityLabel("Weekly mileage by week")
            if timeline.peak.climb > 0 {
                header("Climb a week", peak: "Peak \(unit.climb(timeline.peak.climb))")
                chart(value: { unit == .miles ? $0.climb / 0.3048 : $0.climb }, describe: { unit.climb($0.climb) }, peak: unit == .miles ? timeline.peak.climb / 0.3048 : timeline.peak.climb, height: 80, flagsEvent: false)
                    .accessibilityLabel("Weekly climb by week")
            }
            HStack(spacing: 14) {
                if runThrough != nil {
                    legend("Run", color: Self.runColor)
                }
                legend("Building", color: Self.buildingColor)
                legend("Easy week", color: Self.easyColor)
                if weeks.contains(where: { $0.kind == .recovery }) {
                    legend("Recovery", color: Self.recoveryColor)
                }
                HStack(spacing: 5) {
                    Image(systemName: "flag.checkered")
                    Text("Event")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        // In a form, the row's separator starts at the row's edge, not at the legend's text.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .sensoryFeedback(.selection, trigger: tapped)
    }

    private var firstNumber: Int { weeks.first?.number ?? 1 }
    private var lastNumber: Int { weeks.last?.number ?? 1 }

    /// The chart's name, and the peak the dashed line marks. The peak's label sits here rather than on the line, where
    /// the bars at the peak can cover it.
    private func header(_ title: String, peak: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            HStack(spacing: 5) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0.5))
                    path.addLine(to: CGPoint(x: 14, y: 0.5))
                }
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 14, height: 1)
                Text(peak)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    /// Round steps for the amount axis: 0 and multiples of 1, 2 or 5 times a power of ten, three or four of them.
    static func ticks(upTo top: Double) -> [Double] {
        guard top > 0 else { return [0] }
        let rough = top / 4
        let power = pow(10, floor(log10(rough)))
        let step = [1.0, 2, 5, 10].map { $0 * power }.first { $0 >= rough } ?? rough
        return stride(from: 0, through: top, by: step).map { $0 }
    }

    private func chart(value: @escaping (WeekVolume) -> Double, describe: @escaping (WeekVolume) -> String, peak: Double, height: CGFloat, flagsEvent: Bool) -> some View {
        let top = max(peak, weeks.map { value($0.volume) }.max() ?? 0) * 1.1
        return Chart {
            ForEach(weeks) { week in
                bar(week, amount: value(week.volume), flagged: flagsEvent && week.kind == .goal)
                    .accessibilityLabel(weekLabel(week))
                    .accessibilityValue(describe(week.volume))
            }
            RuleMark(y: .value("Peak", peak))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary)
        }
        .chartXScale(domain: Double(firstNumber) - 0.5 ... Double(lastNumber) + 0.5)
        .chartYScale(domain: 0 ... max(top, 1))
        .chartXAxis {
            AxisMarks(values: [Double(firstNumber), Double(lastNumber)]) { mark in
                AxisValueLabel(anchor: mark.index == 0 ? .topLeading : .topTrailing) {
                    if let number = mark.as(Double.self) {
                        Text(timeline.calendar.end(of: Int(number.rounded()), calendar: .current), format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            // Labels drawn as text, as the dates are, so they show on the plan screen's card too.
            AxisMarks(position: .leading, values: Self.ticks(upTo: top)) { mark in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = mark.as(Double.self) {
                        Text(amount, format: .number.precision(.fractionLength(0 ... 1)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            if let onTapWeek {
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(.rect)
                        .onTapGesture { location in
                            guard let frame = proxy.plotFrame else { return }
                            let x = location.x - geometry[frame].origin.x
                            if let number = proxy.value(atX: x, as: Double.self) {
                                Trace.tap("Coach timeline", "Week", ["week": Int(number.rounded())])
                                tapped += 1
                                withAnimation(.snappy) { onTapWeek(Int(number.rounded())) }
                            }
                        }
                }
                // Each bar can be thin, so VoiceOver uses the list of weeks under the chart instead.
                .accessibilityHidden(true)
            }
        }
        .frame(height: height)
    }

    /// "Week 5, easy week, Mar 9": what VoiceOver reads for a bar, rather than its edges.
    private func weekLabel(_ week: TimelineWeek) -> String {
        let end = timeline.calendar.end(of: week.number, calendar: .current).formatted(.dateTime.month(.abbreviated).day())
        let kind = isRun(week) ? "run" : week.kind.name.lowercased()
        return "Week \(week.number), \(kind), to \(end)"
    }

    private func isRun(_ week: TimelineWeek) -> Bool {
        runThrough.map { week.number <= $0 } ?? false
    }

    /// A week's bar, from zero up and from a start to an end week: a rectangle, since a bar's width as a ratio needs
    /// categories, not numbers. The event week has a flag over it.
    private func bar(_ week: TimelineWeek, amount: Double, flagged: Bool) -> some ChartContent {
        let center = Double(week.number)
        let color: Color = if isRun(week) {
            Self.runColor
        } else {
            switch week.kind {
            case .easy, .goal: Self.easyColor
            case .recovery, .paused: Self.recoveryColor
            case .building, .holding: Self.buildingColor
            }
        }
        let xStart: PlottableValue<Double> = .value("Week", center - 0.35)
        let xEnd: PlottableValue<Double> = .value("Week", center + 0.35)
        let yStart: PlottableValue<Double> = .value("Amount", 0.0)
        let yEnd: PlottableValue<Double> = .value("Amount", amount)
        return RectangleMark(xStart: xStart, xEnd: xEnd, yStart: yStart, yEnd: yEnd)
            .foregroundStyle(color)
            .cornerRadius(2)
            .annotation(position: .top, spacing: 2) {
                if flagged {
                    Image(systemName: "flag.checkered")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}

/// The timeline's words: when the peak comes at 10% and 5% a week, and the ambitious note.
struct BuildTimelineSummary {
    let timeline: BuildTimeline
    let unit: DistanceUnit
    let event: GoalEvent
    var calendar: Calendar = .current

    private func date(_ week: Int?) -> String {
        guard let week else { return "not in sight" }
        if week == 0 { return "now" }
        return timeline.calendar.end(of: week, calendar: calendar).formatted(.dateTime.month(.abbreviated).day())
    }

    var headline: String {
        if timeline.isAmbitious {
            return "\(unit.weekly(timeline.top.meters)) of \(unit.weekly(timeline.peak.meters)) by \(event == .custom ? "the event" : "your \(event.shortName)")"
        }
        let slowest = min(timeline.slowestPeakWeek ?? timeline.calendar.count, timeline.calendar.count)
        if timeline.fastestPeakWeek == 0 { return "You're at your peak week already" }
        let fastest = date(timeline.fastestPeakWeek)
        let gentle = date(slowest)
        return fastest == gentle ? "Peak week by \(fastest)" : "Peak week between \(fastest) and \(gentle)"
    }

    var subheadline: String {
        let weeks = timeline.calendar.count
        let goal = timeline.calendar.end(of: weeks, calendar: calendar).formatted(.dateTime.month(.wide).day())
        if timeline.isAmbitious {
            return "\(CoachFormat.weeks(weeks)) to \(goal), adding the most the coach allows."
        }
        let rate = CoachFormat.percent(timeline.firstRate)
        return rate > 0
            ? "\(weeks) weeks to \(goal). Your plan adds about \(rate)% a week, then holds the peak."
            : "\(weeks) weeks to \(goal). Your plan holds your mileage."
    }

    /// When the peak comes building as fast as the coach allows (10% a week) and gently (5%), the climb's when
    /// there is one, and the easy weeks.
    var rows: [(String, String)] {
        var rows = [
            ("Fastest safe build", "\(unit.weekly(timeline.peak.meters)) by \(date(timeline.fastestPeakWeek))"),
            ("Gentle build", "\(unit.weekly(timeline.peak.meters)) by \(date(timeline.slowestPeakWeek))"),
        ]
        if timeline.peak.climb > 0 {
            rows.append(("Peak climb, fastest / gentle", "\(date(timeline.fastestClimbWeek)) / \(date(timeline.slowestClimbWeek))"))
        }
        rows.append(("Easy weeks", "\(timeline.easyWeekCount), including your event week"))
        return rows
    }

    /// "you'd reach 25 km a week, short of 31.6 km": what 10% a week gets to by the event.
    private var shortfall: String {
        var parts: [String] = []
        if !timeline.reachesPeak {
            parts.append("you'd reach \(unit.weekly(timeline.top.meters)) a week, short of \(unit.weekly(timeline.peak.meters))")
        }
        if !timeline.reachesClimb {
            parts.append("\(unit.climb(timeline.top.climb)) of climb a week, short of \(unit.climb(timeline.peak.climb))")
        }
        return parts.joined(separator: " and ")
    }

    /// When 10% a week isn't enough: the plan still starts (the owner, 2026-10-28).
    var ambitiousNote: String? {
        guard timeline.isAmbitious else { return nil }
        return "Even adding 10% every week, by the event \(shortfall). The plan still starts. You may need to walk some of the event, or pick a later date."
    }

    /// The same on the plan screen, once the date is set: what to expect rather than what to change.
    var planAmbitiousNote: String? {
        guard timeline.isAmbitious else { return nil }
        return "Your plan adds the most the coach allows each week. By the event \(shortfall), so you may need to walk some of it."
    }
}

/// "I'll add them" as a list: a switch for each week, for VoiceOver and Switch Control, and for weeks too thin to
/// tap on the chart. The event week is always an easy week, so it isn't listed.
struct EasyWeekList: View {
    let timeline: BuildTimeline
    let schedule: EasyWeekSchedule
    /// The first week that can change: past weeks stay as they were.
    var from = 1
    let toggle: (Int) -> Void

    var body: some View {
        let weeks = Array(max(1, from) ..< max(max(1, from), timeline.calendar.count))
        if !weeks.isEmpty {
            DisclosureGroup("Choose from a list") {
                ForEach(weeks, id: \.self) { number in
                    Toggle(isOn: Binding(get: { schedule.isEasy(number) }, set: { _ in
                        Trace.tap("Coach timeline", "Easy week from list", ["week": number])
                        toggle(number)
                    })) {
                        Text("Week \(number) · \(timeline.calendar.start(of: number, calendar: .current).formatted(.dateTime.month(.abbreviated).day()))")
                    }
                }
            }
        }
    }
}
