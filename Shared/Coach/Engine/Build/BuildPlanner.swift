//
//  BuildPlanner.swift
//  Wind Run
//

import Foundation

/// A week's mileage and climb, in meters.
struct WeekVolume: Codable, Hashable {
    var meters: Double
    var climb: Double

    static let zero = WeekVolume(meters: 0, climb: 0)

    init(meters: Double, climb: Double = 0) {
        self.meters = meters
        self.climb = climb
    }

    func scaled(by share: Double) -> WeekVolume {
        WeekVolume(meters: meters * share, climb: climb * share)
    }
}

/// What a plan week is.
enum BuildWeekKind: String, Codable, Hashable {
    /// Up to 10% more than the last building week, or the peak held.
    case building
    /// The same as the last building week: a short week before it, or an open Mild injury.
    case holding
    /// 25% under the last building week.
    case easy
    /// The last week, ending on the goal date: an easy week with the event in it.
    case goal
    /// An injury's recovery or return weeks.
    case recovery
    /// No running planned: an injury pause.
    case paused

    var name: String {
        switch self {
        case .building: "Building week"
        case .holding: "Same as last week"
        case .easy: "Easy week"
        case .goal: "Event week"
        case .recovery: "Recovery week"
        case .paused: "Paused"
        }
    }

    /// Weeks the next building week grows from.
    var isBuilding: Bool { self == .building || self == .holding }
}

/// The plan's weeks on the calendar. Weeks end on the goal date, so the first one may have started before the plan:
/// when fewer than 3 of its days are left, the plan starts the week after.
struct PlanCalendar: Codable, Hashable {
    /// The first day of week 1.
    var firstStart: Date
    /// Weeks from week 1 through the goal week.
    var count: Int

    static func make(goalDate: Date, now: Date, calendar: Calendar) -> PlanCalendar {
        let today = calendar.startOfDay(for: now)
        let goal = calendar.startOfDay(for: goalDate)
        let days = max(0, calendar.dateComponents([.day], from: today, to: goal).day ?? 0)
        var count = days / 7 + 1
        let daysLeftInFirstWeek = days % 7 + 1
        if daysLeftInFirstWeek < BuildLimits.firstWeekDays, count > 1 { count -= 1 }
        let firstStart = calendar.date(byAdding: .day, value: -(7 * count - 1), to: goal) ?? today
        return PlanCalendar(firstStart: firstStart, count: count)
    }

    /// The first day of week `number`, counting past the goal week too (for the timeline's estimates).
    func start(of number: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 7 * (number - 1), to: firstStart) ?? firstStart
    }

    /// The last day of week `number`.
    func end(of number: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 7 * number - 1, to: firstStart) ?? firstStart
    }

    /// The goal date: the last day of the goal week.
    func goalDate(calendar: Calendar) -> Date { end(of: count, calendar: calendar) }

    /// The week a date falls in: 0 or less before the plan, more than `count` after the goal week.
    func number(on date: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: firstStart, to: calendar.startOfDay(for: date)).day ?? 0
        return days >= 0 ? days / 7 + 1 : -((-days - 1) / 7)
    }
}

/// One week of the timeline.
struct TimelineWeek: Hashable, Identifiable {
    var number: Int
    var kind: BuildWeekKind
    var volume: WeekVolume

    var id: Int { number }
}

/// The timeline setup shows as the runner fills it in, and the plan screen shows ahead of the current week.
struct BuildTimeline: Hashable {
    var calendar: PlanCalendar
    var weeks: [TimelineWeek]
    var peak: WeekVolume
    /// The weeks the peak is reached adding 10% or 5% each building week, past the goal week if need be. Nil when
    /// it's out of sight (10 years); 0 when it's already reached.
    var fastestPeakWeek: Int?
    var slowestPeakWeek: Int?
    var fastestClimbWeek: Int?
    var slowestClimbWeek: Int?
    /// The plan's first growth: what it needs to reach the peak in time, between 5% and 10%.
    var firstRate: Double

    /// The most the plan gets to before the event.
    var top: WeekVolume {
        WeekVolume(meters: weeks.map(\.volume.meters).max() ?? 0, climb: weeks.map(\.volume.climb).max() ?? 0)
    }

    var reachesPeak: Bool { top.meters >= peak.meters * 0.999 }

    var reachesClimb: Bool { peak.climb <= 0 || top.climb >= peak.climb * 0.999 }

    /// 10% a week can't reach the peak by the goal date. The plan still starts (Brendon, 2026-10-28).
    var isAmbitious: Bool { !reachesPeak || !reachesClimb }

    /// The first week the plan itself reaches the peak, or nil when it doesn't.
    var planPeakWeek: Int? {
        weeks.first { $0.volume.meters >= peak.meters * 0.999 && (peak.climb <= 0 || $0.volume.climb >= peak.climb * 0.999) }?.number
    }

    var easyWeekCount: Int { weeks.filter { $0.kind == .easy || $0.kind == .goal }.count }
}

/// Builds a Build Distance plan's weeks: weekly mileage and climb from where the runner is to the peak week, never
/// more than 10% on the last building week, with easy weeks 25% under it and the goal week easy too.
enum BuildPlanner {
    /// The timeline for setup's answers, from week 1.
    static func timeline(_ settings: BuildSettings, now: Date, calendar: Calendar) -> BuildTimeline {
        let planCalendar = PlanCalendar.make(goalDate: settings.goal.date, now: now, calendar: calendar)
        return timeline(settings, planCalendar: planCalendar, from: 1, base: startingBase(settings), hold: false)
    }

    /// The timeline from week `first` on, growing from `base` (the last building week). `hold` keeps week `first`
    /// at the base when it's a building week.
    static func timeline(_ settings: BuildSettings, planCalendar: PlanCalendar, from first: Int, base: WeekVolume, hold: Bool) -> BuildTimeline {
        let peak = WeekVolume(meters: settings.goal.peakWeekMeters, climb: settings.goal.peakWeekClimbMeters)
        let count = planCalendar.count
        let schedule = settings.easyWeeks
        var weeks: [TimelineWeek] = []
        var current = base
        var firstRate: Double?
        if first <= count {
            for number in first ... count {
                let kind = weekKind(number, count: count, schedule: schedule)
                switch kind {
                case .goal, .easy:
                    weeks.append(TimelineWeek(number: number, kind: kind, volume: current.scaled(by: BuildLimits.easyWeekShare)))
                default:
                    if hold, number == first {
                        weeks.append(TimelineWeek(number: number, kind: .holding, volume: current))
                        continue
                    }
                    let left = buildingWeeks(from: number, count: count, schedule: schedule)
                    let meterRate = rate(from: current.meters, to: peak.meters, weeks: left)
                    let climbRate = rate(from: current.climb, to: peak.climb, weeks: left)
                    if firstRate == nil { firstRate = meterRate }
                    current = WeekVolume(meters: grow(current.meters, by: meterRate, to: peak.meters), climb: grow(current.climb, by: climbRate, to: peak.climb))
                    weeks.append(TimelineWeek(number: number, kind: .building, volume: current))
                }
            }
        }
        let floor = startingFloor(peakClimb: peak.climb)
        return BuildTimeline(
            calendar: planCalendar,
            weeks: weeks,
            peak: peak,
            fastestPeakWeek: weekReaching(peak.meters, from: max(base.meters, floor.meters), rate: BuildLimits.maxGrowth, first: first, schedule: schedule),
            slowestPeakWeek: weekReaching(peak.meters, from: max(base.meters, floor.meters), rate: BuildLimits.minGrowth, first: first, schedule: schedule),
            fastestClimbWeek: peak.climb > 0 ? weekReaching(peak.climb, from: max(base.climb, floor.climb), rate: BuildLimits.maxGrowth, first: first, schedule: schedule) : nil,
            slowestClimbWeek: peak.climb > 0 ? weekReaching(peak.climb, from: max(base.climb, floor.climb), rate: BuildLimits.minGrowth, first: first, schedule: schedule) : nil,
            firstRate: firstRate ?? 0
        )
    }

    /// What week 1 grows from: the runner's week now, but at least 5 km (3 mi) and 10% of the peak's climb.
    static func startingBase(_ settings: BuildSettings) -> WeekVolume {
        let floor = startingFloor(peakClimb: settings.goal.peakWeekClimbMeters)
        return WeekVolume(meters: max(settings.currentWeeklyMeters, floor.meters), climb: max(settings.currentWeeklyClimbMeters, floor.climb))
    }

    static func startingFloor(peakClimb: Double) -> WeekVolume {
        WeekVolume(meters: BuildLimits.floorMeters, climb: peakClimb * BuildLimits.climbFloorShare)
    }

    static func weekKind(_ number: Int, count: Int, schedule: EasyWeekSchedule) -> BuildWeekKind {
        if number == count { return .goal }
        return schedule.isEasy(number) ? .easy : .building
    }

    /// Building weeks from `number` up to the goal week.
    static func buildingWeeks(from number: Int, count: Int, schedule: EasyWeekSchedule) -> Int {
        guard number < count else { return 0 }
        return (number ..< count).filter { !schedule.isEasy($0) }.count
    }

    /// The growth each building week needs to reach `peak` in `weeks`, never under 5% or over 10%. Zero once the
    /// peak is reached.
    static func rate(from base: Double, to peak: Double, weeks: Int) -> Double {
        guard peak > 0, base < peak else { return 0 }
        guard base > 0, weeks > 0 else { return BuildLimits.maxGrowth }
        let needed = pow(peak / base, 1 / Double(weeks)) - 1
        return needed.clamped(to: BuildLimits.minGrowth ... BuildLimits.maxGrowth)
    }

    /// One building week on: `base` grown by `rate`, never past the peak, and never down if it's already over it.
    static func grow(_ base: Double, by rate: Double, to peak: Double) -> Double {
        guard base < peak else { return base }
        return min(peak, base * (1 + rate))
    }

    /// The week a fixed growth reaches `peak`, with the easy weeks in between, counting past the goal week.
    static func weekReaching(_ peak: Double, from base: Double, rate: Double, first: Int, schedule: EasyWeekSchedule) -> Int? {
        guard peak > 0 else { return nil }
        if base >= peak * 0.999 { return 0 }
        guard base > 0 else { return nil }
        var current = base
        for number in first ..< first + 520 where !schedule.isEasy(number) {
            current *= 1 + rate
            if current >= peak * 0.999 { return number }
        }
        return nil
    }
}

// MARK: Splitting a week

/// What a planned run is.
enum BuildSessionKind: String, Codable, Hashable {
    case easy
    case long
    /// The goal event, on the goal date.
    case event

    var name: String {
        switch self {
        case .easy: "Easy run"
        case .long: "Long run"
        case .event: "Event day"
        }
    }
}

extension BuildPlanner {
    /// The long run's share of a week of `runs` runs: twice each other run, never more than half the week.
    static func longShare(runs: Int) -> Double {
        guard runs > 1 else { return 1 }
        return min(0.5, 2 / Double(runs + 1))
    }

    /// Which of the week's run days takes the long run: Saturday, else Sunday, else the last one.
    static func longRunIndex(_ days: [Date], calendar: Calendar) -> Int? {
        guard !days.isEmpty else { return nil }
        let weekdays = days.map { Weekday(of: $0, calendar: calendar) }
        return weekdays.firstIndex(of: .saturday) ?? weekdays.firstIndex(of: .sunday) ?? days.count - 1
    }

    /// The run days of week `number` from `from` on, in order.
    static func runDates(week number: Int, planCalendar: PlanCalendar, runDays: [Weekday], from: Date, calendar: Calendar) -> [Date] {
        let start = planCalendar.start(of: number, calendar: calendar)
        let earliest = calendar.startOfDay(for: from)
        return (0 ..< 7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start), day >= earliest,
                  runDays.contains(Weekday(of: day, calendar: calendar)) else { return nil }
            return day
        }
    }

    /// Splits `volume` over runs on `dates`: the long run twice each other run, up to half the week.
    /// - Parameter longRun: false when the week's long run is already done or replaced by the event.
    static func split(_ volume: WeekVolume, over dates: [Date], longRun: Bool, calendar: Calendar) -> [(date: Date, kind: BuildSessionKind, volume: WeekVolume)] {
        guard !dates.isEmpty else { return [] }
        guard longRun, let longIndex = longRunIndex(dates, calendar: calendar) else {
            let each = volume.scaled(by: 1 / Double(dates.count))
            return dates.map { (date: $0, kind: BuildSessionKind.easy, volume: each) }
        }
        let share = longShare(runs: dates.count)
        let rest = dates.count > 1 ? (1 - share) / Double(dates.count - 1) : 0
        return dates.enumerated().map { index, date in
            let isLong = index == longIndex
            return (date: date, kind: isLong ? BuildSessionKind.long : BuildSessionKind.easy, volume: volume.scaled(by: isLong ? share : rest))
        }
    }
}
