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
    /// Tapping a week, for "I'll add them": nil when weeks can't be tapped.
    var onTapWeek: ((Int) -> Void)?

    private var weeks: [TimelineWeek] { done + timeline.weeks }

    /// Building weeks in the accent, easy, event and recovery weeks lighter, as plain colors so every chart draws
    /// them the same.
    private static let buildingColor = Color.accentColor
    private static let easyColor = Color.accentColor.opacity(0.35)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chart(value: { $0.meters / unit.meters }, peak: timeline.peak.meters / unit.meters, peakLabel: "Peak \(unit.weekly(timeline.peak.meters))", height: 170)
                .accessibilityLabel("Weekly mileage by week")
            if timeline.peak.climb > 0 {
                Text("Climb a week")
                    .font(.subheadline.weight(.semibold))
                chart(value: { unit == .miles ? $0.climb / 0.3048 : $0.climb }, peak: unit == .miles ? timeline.peak.climb / 0.3048 : timeline.peak.climb, peakLabel: "Peak \(unit.climb(timeline.peak.climb))", height: 80)
                    .accessibilityLabel("Weekly climb by week")
            }
            HStack(spacing: 14) {
                legend("Building", color: Self.buildingColor)
                legend("Easy week", color: Self.easyColor)
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
    }

    private var firstNumber: Int { weeks.first?.number ?? 1 }
    private var lastNumber: Int { weeks.last?.number ?? 1 }

    private func chart(value: @escaping (WeekVolume) -> Double, peak: Double, peakLabel: String, height: CGFloat) -> some View {
        // Room over the tallest bar or the peak line for the peak's label.
        let top = max(peak, weeks.map { value($0.volume) }.max() ?? 0) * 1.2
        return Chart {
            ForEach(weeks) { week in
                // Bars from a start to an end week, since a bar's width as a ratio needs categories, not numbers.
                BarMark(
                    xStart: .value("Week", Double(week.number) - 0.35),
                    xEnd: .value("Week", Double(week.number) + 0.35),
                    y: .value("Amount", value(week.volume))
                )
                .foregroundStyle(week.kind == .easy || week.kind == .goal || week.kind == .recovery ? Self.easyColor : Self.buildingColor)
                .cornerRadius(2)
            }
            RuleMark(y: .value("Peak", peak))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text(peakLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
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
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartOverlay { proxy in
            if let onTapWeek {
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(.rect)
                        .onTapGesture { location in
                            guard let frame = proxy.plotFrame else { return }
                            let x = location.x - geometry[frame].origin.x
                            if let number = proxy.value(atX: x, as: Double.self) { onTapWeek(Int(number.rounded())) }
                        }
                }
            }
        }
        .frame(height: height)
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
        return "Peak week by \(date(timeline.fastestPeakWeek)) to \(date(slowest))"
    }

    var subheadline: String {
        let weeks = timeline.calendar.count
        let goal = timeline.calendar.end(of: weeks, calendar: calendar).formatted(.dateTime.month(.wide).day())
        if timeline.isAmbitious {
            return "\(weeks) \(weeks == 1 ? "week" : "weeks") to \(goal), adding the most the coach allows."
        }
        let rate = Int((timeline.firstRate * 100).rounded())
        return rate > 0
            ? "\(weeks) weeks to \(goal). Your plan adds about \(rate)% a week, then holds the peak."
            : "\(weeks) weeks to \(goal). Your plan holds your mileage."
    }

    /// "At 10% a week" and "At 5% a week" rows, and the climb's when there is one.
    var rows: [(String, String)] {
        var rows = [
            ("At 10% a week", "\(unit.weekly(timeline.peak.meters)) by \(date(timeline.fastestPeakWeek))"),
            ("At 5% a week", "\(unit.weekly(timeline.peak.meters)) by \(date(timeline.slowestPeakWeek))"),
        ]
        if timeline.peak.climb > 0 {
            rows.append(("Climb at 10% / 5%", "\(date(timeline.fastestClimbWeek)) / \(date(timeline.slowestClimbWeek))"))
        }
        rows.append(("Easy weeks", "\(timeline.easyWeekCount), with \(event == .custom ? "event" : event.shortName) week"))
        return rows
    }

    /// When 10% a week isn't enough: the plan still starts (Brendon, 2026-10-28).
    var ambitiousNote: String? {
        guard timeline.isAmbitious else { return nil }
        var parts: [String] = []
        if !timeline.reachesPeak {
            parts.append("you'd reach \(unit.weekly(timeline.top.meters)) a week, short of \(unit.weekly(timeline.peak.meters))")
        }
        if !timeline.reachesClimb {
            parts.append("\(unit.climb(timeline.top.climb)) of climb a week, short of \(unit.climb(timeline.peak.climb))")
        }
        return "Even adding 10% every week, by the event \(parts.joined(separator: " and ")). The plan still starts. You may need to walk some of the event, or pick a later date."
    }
}
