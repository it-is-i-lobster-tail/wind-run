//
//  BuildAnswers.swift
//  Wind Run
//

import Foundation

/// Setup's answers kept between plans, so the next setup starts from them (Brendon, 2026-10-22). Stored as JSON in
/// the app's `CoachProfile`, which syncs with runs and plans when iCloud Sync is on. Every field is optional, so
/// answers saved by older setups still load: what they don't have is filled in fresh, and a peak week they kept
/// is left out, since the peak always follows from the event now.
struct SavedBuildAnswers: Codable, Hashable {
    var event: GoalEvent?
    var eventMeters: Double?
    var eventClimbMeters: Double?
    var goalDate: Date?
    var currentWeeklyMeters: Double?
    var currentWeeklyClimbMeters: Double?
    var runDays: [Weekday]?
    var easyWeeks: EasyWeekSchedule?
    var savedAt: Date?

    init() {}

    init(_ settings: BuildSettings, at date: Date) {
        event = settings.goal.event
        eventMeters = settings.goal.meters
        eventClimbMeters = settings.goal.climbMeters
        goalDate = settings.goal.date
        currentWeeklyMeters = settings.currentWeeklyMeters
        currentWeeklyClimbMeters = settings.currentWeeklyClimbMeters
        runDays = settings.runDays
        // Weeks picked by hand belong to one plan; the next one starts from the schedule.
        easyWeeks = settings.easyWeeks.isAutomatic ? settings.easyWeeks : .standard
        savedAt = date
    }

    /// The settings a new setup starts from: the saved answers, a goal date still ahead (else 16 weeks out),
    /// and the week now from the runs when there are any.
    func settings(recent: WeekVolume?, now: Date, calendar: Calendar) -> BuildSettings {
        let today = calendar.startOfDay(for: now)
        let soonest = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let date = goalDate.flatMap { $0 >= soonest ? $0 : nil }
            ?? calendar.date(byAdding: .weekOfYear, value: 16, to: today) ?? today
        let event = event ?? .halfMarathon
        let goal = BuildGoal(
            event: event,
            meters: event == .custom ? eventMeters : nil,
            climbMeters: eventClimbMeters ?? 0,
            date: date
        )
        return BuildSettings(
            currentWeeklyMeters: recent?.meters ?? currentWeeklyMeters ?? 0,
            currentWeeklyClimbMeters: recent?.climb ?? currentWeeklyClimbMeters ?? 0,
            goal: goal,
            runDays: runDays ?? [.tuesday, .thursday, .saturday],
            easyWeeks: easyWeeks ?? .standard
        )
    }
}

extension BuildPlanner {
    /// The runner's week now: the average of the last 4 weeks of runs (the 28 days before today), or nil when
    /// there are none.
    static func recentWeek(_ runs: [CoachRun], now: Date, calendar: Calendar) -> WeekVolume? {
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -28, to: today) else { return nil }
        let recent = runs.filter { $0.start >= from && $0.start < today }
        guard !recent.isEmpty else { return nil }
        return WeekVolume(meters: recent.reduce(0) { $0 + $1.meters } / 4, climb: recent.reduce(0) { $0 + $1.climb } / 4)
    }
}
