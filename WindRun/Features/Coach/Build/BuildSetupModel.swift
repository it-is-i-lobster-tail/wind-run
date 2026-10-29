//
//  BuildSetupModel.swift
//  Wind Run
//

import Foundation
import Observation

/// Setup's answers while the runner fills the form in, and the timeline they make.
@Observable
final class BuildSetupModel {
    var settings: BuildSettings
    /// The runner typed a peak of their own, so changing the event doesn't move it.
    var customPeak: Bool
    /// "Weekly mileage now" came from the runs, so the form says so.
    private(set) var filledFromRuns = false
    /// The runner changed "now" by hand, so runs coming in late don't overwrite it.
    private var editedNow = false

    let unit: DistanceUnit
    let now: Date
    let calendar: Calendar

    init(saved: SavedBuildAnswers?, unit: DistanceUnit, now: Date = .now, calendar: Calendar = .current) {
        self.unit = unit
        self.now = now
        self.calendar = calendar
        let saved = saved ?? SavedBuildAnswers()
        settings = saved.settings(recent: nil, now: now, calendar: calendar)
        customPeak = saved.peakWeekMeters != nil
    }

    /// Fills "now" in from the last 4 weeks of runs, unless the runner already changed it.
    func fill(recent runs: [CoachRun]) {
        guard !editedNow, let week = BuildPlanner.recentWeek(runs, now: now, calendar: calendar) else { return }
        settings.currentWeeklyMeters = week.meters
        settings.currentWeeklyClimbMeters = week.climb
        filledFromRuns = true
    }

    var timeline: BuildTimeline {
        BuildPlanner.timeline(settings, now: now, calendar: calendar)
    }

    // MARK: Fields, in the runner's units

    /// Meters per unit of distance (km or mi) and of climb (m or ft).
    var distanceStep: Double { unit.meters }
    var climbStep: Double { unit == .miles ? 0.3048 : 1 }
    var climbSymbol: String { unit == .miles ? "ft" : "m" }

    var currentDistance: Double {
        get { settings.currentWeeklyMeters / distanceStep }
        set { settings.currentWeeklyMeters = max(0, newValue) * distanceStep; editedNow = true }
    }

    var currentClimb: Double {
        get { settings.currentWeeklyClimbMeters / climbStep }
        set { settings.currentWeeklyClimbMeters = max(0, newValue) * climbStep; editedNow = true }
    }

    var event: GoalEvent {
        get { settings.goal.event }
        set {
            settings.goal.event = newValue
            if let meters = newValue.meters { settings.goal.meters = meters }
            presetPeak()
        }
    }

    var customDistance: Double {
        get { settings.goal.meters / distanceStep }
        set { settings.goal.meters = max(0, newValue) * distanceStep; presetPeak() }
    }

    var eventClimb: Double {
        get { settings.goal.climbMeters / climbStep }
        set { settings.goal.climbMeters = max(0, newValue) * climbStep; presetPeak() }
    }

    var peakDistance: Double {
        get { settings.goal.peakWeekMeters / distanceStep }
        set { settings.goal.peakWeekMeters = max(0, newValue) * distanceStep; customPeak = true }
    }

    var peakClimb: Double {
        get { settings.goal.peakWeekClimbMeters / climbStep }
        set { settings.goal.peakWeekClimbMeters = max(0, newValue) * climbStep; customPeak = true }
    }

    var goalDate: Date {
        get { settings.goal.date }
        set { settings.goal.date = calendar.startOfDay(for: newValue) }
    }

    /// A week out at the soonest, so the plan has a week before the event, and up to 2 years.
    var goalDateRange: ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let soonest = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let latest = calendar.date(byAdding: .year, value: 2, to: today) ?? today
        return soonest ... latest
    }

    func toggle(_ day: Weekday) {
        var days = Set(settings.runDays)
        if days.contains(day) {
            guard days.count > 1 else { return }
            days.remove(day)
        } else {
            days.insert(day)
        }
        settings.runDays = days.sorted()
    }

    var plansEasyWeeks: Bool {
        get { settings.easyWeeks.isAutomatic }
        set { settings.easyWeeks = newValue ? .standard : .chosen([]) }
    }

    var easySpacing: Int {
        get {
            if case .every(let n) = settings.easyWeeks { return n }
            return 4
        }
        set { settings.easyWeeks = .every(newValue.clamped(to: EasyWeekSchedule.spacing)) }
    }

    /// Makes a week an easy week, or a building week again. The goal week is always easy.
    func toggleEasyWeek(_ number: Int) {
        let count = timeline.calendar.count
        guard number < count else { return }
        settings.easyWeeks = settings.easyWeeks.toggling(number, through: count)
    }

    var canStart: Bool {
        settings.goal.meters > 0 && goalDateRange.contains(settings.goal.date) && !settings.runDays.isEmpty
    }

    private func presetPeak() {
        guard !customPeak else { return }
        settings.goal.peakWeekMeters = BuildGoal.defaultPeak(forMeters: settings.goal.meters)
        settings.goal.peakWeekClimbMeters = BuildGoal.defaultPeakClimb(forClimb: settings.goal.climbMeters)
    }

    /// The answers to keep for the next setup.
    var answers: SavedBuildAnswers {
        SavedBuildAnswers(settings, customPeak: customPeak, at: .now)
    }
}

extension DistanceUnit {
    /// Climb in this unit system's height unit: "3,800 ft" or "1,160 m".
    func climb(_ meters: Double) -> String {
        let value = self == .miles ? meters / 0.3048 : meters
        return "\(Int(value.rounded()).formatted()) \(self == .miles ? "ft" : "m")"
    }

    /// A weekly or run distance to one decimal: "26.4 mi".
    func weekly(_ meters: Double) -> String {
        "\((meters / self.meters).formatted(.number.precision(.fractionLength(0 ... 1)))) \(symbol)"
    }
}
