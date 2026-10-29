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
                legend("Building", style: AnyShapeStyle(.tint))
                legend("Easy week", style: AnyShapeStyle(.tint.opacity(0.35)))
                Label("Event", systemImage: "flag.checkered")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func chart(value: @escaping (WeekVolume) -> Double, peak: Double, peakLabel: String, height: CGFloat) -> some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Week", week.number), y: .value("Amount", value(week.volume)), width: .ratio(0.7))
                    .foregroundStyle(week.kind == .easy || week.kind == .goal || week.kind == .recovery ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.tint))
                    .cornerRadius(2)
            }
            RuleMark(y: .value("Peak", peak))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.primary.opacity(0.6))
                .annotation(position: .top, alignment: .leading) {
                    Text(peakLabel)
                        .font(.caption2.weight(.semibold))
                }
        }
        .chartXAxis {
            AxisMarks(values: [weeks.first?.number ?? 1, weeks.last?.number ?? 1]) { mark in
                AxisValueLabel {
                    if let number = mark.as(Int.self) {
                        Text(timeline.calendar.end(of: number, calendar: .current), format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
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

    private func legend(_ title: String, style: AnyShapeStyle) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(style).frame(width: 10, height: 10)
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
