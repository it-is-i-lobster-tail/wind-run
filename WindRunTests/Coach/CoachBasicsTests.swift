//
//  CoachBasicsTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// The coach's small value helpers: recovery settings, easy-week schedules, saved answers, the week now, weekdays,
/// growth, splitting, the timeline's words and the formats the coach screens use.
@MainActor
struct CoachBasicsTests {
    static var calendar: Calendar { BuildPlannerTests.calendar }

    static func day(_ offset: Int) -> Date { BuildPlannerTests.day(offset) }

    // MARK: Recovery

    @Test func recoverySettingsStayInTheirRange() {
        let low = RecoverySettings(restWeeks: -1, reducedWeeks: 0, reducedShare: 0.04)
        #expect(low.restWeeks == 0)
        #expect(low.reducedWeeks == 1)
        #expect(low.reducedShare == 0.1)
        #expect(RecoverySettings(restWeeks: 0, reducedWeeks: 1, reducedShare: 0.97).reducedShare == 0.9)
        // Shares go in tenths.
        #expect(RecoverySettings(restWeeks: 0, reducedWeeks: 1, reducedShare: 0.56).reducedShare == 0.6)
    }

    @Test func recoveryWeeksAreRestThenReduced() {
        let settings = RecoverySettings(restWeeks: 2, reducedWeeks: 3, reducedShare: 0.5)
        #expect(settings.weeks == 5)
        #expect(settings.share(at: 0) == 0)
        #expect(settings.share(at: 1) == 0)
        #expect(settings.share(at: 2) == 0.5)
        #expect(settings.share(at: 4) == 0.5)
    }

    /// The injury card's Severe text says "Then 2 weeks at half your mileage" (BuildPlanView's InjuryCard), so these
    /// numbers can't change without it.
    @Test func defaultRecoveriesMatchTheCardText() {
        #expect(RecoverySettings.intense == RecoverySettings(restWeeks: 1, reducedWeeks: 2, reducedShare: 0.5))
        #expect(RecoverySettings.severe == RecoverySettings(restWeeks: 0, reducedWeeks: 2, reducedShare: 0.5))
    }

    @Test func aReportKnowsWhereItsRecoveryIsUpTo() {
        var report = BuildInjury(id: UUID(), reportedAt: BuildPlannerTests.now, level: .intense, area: nil, runID: nil, baseAtReport: WeekVolume(meters: 20_000, climb: 200))
        #expect(report.recoveryIndex(ofWeek: 5) == nil)
        #expect(!report.recoveryIsOver(byWeek: 50))
        #expect(report.returnBase == nil)
        // A start week alone isn't a recovery set up.
        report.recoveryStartWeek = 3
        #expect(report.recoveryIndex(ofWeek: 5) == nil)
        #expect(!report.recoveryIsOver(byWeek: 50))
        report.recovery = .intense
        #expect(report.recoveryIndex(ofWeek: 3) == 0)
        #expect(report.recoveryIndex(ofWeek: 5) == 2)
        #expect(report.recoveryIndex(ofWeek: 2) == -1)
        #expect(!report.recoveryIsOver(byWeek: 5))
        #expect(report.recoveryIsOver(byWeek: 6))
        #expect(report.returnBase == WeekVolume(meters: 10_000, climb: 100))
    }

    // MARK: Easy weeks

    @Test func automaticEasyWeeksKeepTheirSpacing() {
        // Spacing is kept to 3...6.
        #expect(EasyWeekSchedule.every(2).isEasy(3))
        #expect(!EasyWeekSchedule.every(2).isEasy(2))
        #expect(EasyWeekSchedule.every(9).isEasy(6))
        #expect(!EasyWeekSchedule.every(9).isEasy(9))
        #expect(!EasyWeekSchedule.every(4).isEasy(0))
        #expect(!EasyWeekSchedule.every(4).isEasy(-4))
        #expect(EasyWeekSchedule.every(4).isAutomatic)
        #expect(!EasyWeekSchedule.chosen([]).isAutomatic)
    }

    @Test func togglingEasyWeeksMakesThemTheRunnersOwn() {
        #expect(EasyWeekSchedule.chosen([2]).isEasy(2))
        #expect(!EasyWeekSchedule.chosen([2]).isEasy(3))
        #expect(EasyWeekSchedule.chosen([5]).toggling(5, through: 10) == .chosen([]))
        #expect(EasyWeekSchedule.every(4).toggling(2, through: 1) == .chosen([2]))
    }

    // MARK: Run days

    @Test func aPlanKeepsAtLeastOneRunDay() {
        let one = BuildSettings(currentWeeklyMeters: 0, goal: BuildGoal(event: .fiveK, date: BuildPlannerTests.now), runDays: [.friday])
        #expect(one.runDays(toggling: .friday) == nil)
        #expect(one.runDays(toggling: .sunday) == [.sunday, .friday])
        let two = BuildSettings(currentWeeklyMeters: 0, goal: BuildGoal(event: .fiveK, date: BuildPlannerTests.now), runDays: [.friday, .monday])
        #expect(two.runDays == [.monday, .friday])
        #expect(two.runDays(toggling: .monday) == [.friday])
    }

    @Test func setupTogglesRunDaysInOrder() {
        let model = BuildSetupModel(saved: nil, unit: .kilometers, now: BuildPlannerTests.now, calendar: Self.calendar)
        #expect(model.settings.runDays == [.tuesday, .thursday, .saturday])
        model.toggle(.monday)
        #expect(model.settings.runDays == [.monday, .tuesday, .thursday, .saturday])
        model.toggle(.tuesday)
        model.toggle(.thursday)
        model.toggle(.saturday)
        #expect(model.settings.runDays == [.monday])
        model.toggle(.monday)
        #expect(model.settings.runDays == [.monday])
    }

    // MARK: Saved answers

    @Test func savedAnswersFillInWhatTheyDontHave() {
        let settings = SavedBuildAnswers().settings(recent: nil, now: BuildPlannerTests.now, calendar: Self.calendar)
        #expect(settings.goal.event == .halfMarathon)
        #expect(settings.goal.meters == 21_097.5)
        #expect(settings.runDays == [.tuesday, .thursday, .saturday])
        #expect(settings.easyWeeks == .standard)
        #expect(settings.currentWeeklyMeters == 0)
        #expect(settings.currentWeeklyClimbMeters == 0)
        // No goal date saved: 16 weeks out.
        #expect(settings.goal.date == Self.day(112))
    }

    @Test func aSavedGoalDateNeedsAWeekLeft() {
        var saved = SavedBuildAnswers()
        saved.goalDate = Self.day(7)
        #expect(saved.settings(recent: nil, now: BuildPlannerTests.now, calendar: Self.calendar).goal.date == Self.day(7))
        saved.goalDate = Self.day(6)
        #expect(saved.settings(recent: nil, now: BuildPlannerTests.now, calendar: Self.calendar).goal.date == Self.day(112))
        #expect(BuildGoal.soonestDate(now: BuildPlannerTests.now, calendar: Self.calendar) == Self.day(7))
    }

    @Test func setupsDateRangeStartsAtTheSoonestDate() {
        let model = BuildSetupModel(saved: nil, unit: .kilometers, now: BuildPlannerTests.now, calendar: Self.calendar)
        #expect(model.goalDateRange.lowerBound == BuildGoal.soonestDate(now: BuildPlannerTests.now, calendar: Self.calendar))
        #expect(model.goalDateRange.upperBound == Self.calendar.date(byAdding: .year, value: 2, to: Self.day(0)))
        #expect(!model.goalDateRange.contains(Self.day(6)))
        // The date saved answers fall back to is one setup accepts.
        #expect(model.goalDateRange.contains(model.settings.goal.date))
    }

    @Test func onlyACustomEventKeepsItsDistance() {
        var saved = SavedBuildAnswers()
        saved.event = .marathon
        saved.eventMeters = 1_000
        #expect(saved.settings(recent: nil, now: BuildPlannerTests.now, calendar: Self.calendar).goal.meters == 42_195)
        saved.event = .custom
        saved.eventMeters = 30_000
        #expect(saved.settings(recent: nil, now: BuildPlannerTests.now, calendar: Self.calendar).goal.meters == 30_000)
    }

    @Test func recentRunsOverrideTheSavedWeek() {
        var saved = SavedBuildAnswers()
        saved.currentWeeklyMeters = 5_000
        saved.currentWeeklyClimbMeters = 50
        let fromRuns = saved.settings(recent: WeekVolume(meters: 12_000, climb: 300), now: BuildPlannerTests.now, calendar: Self.calendar)
        #expect(fromRuns.currentWeeklyMeters == 12_000)
        #expect(fromRuns.currentWeeklyClimbMeters == 300)
        let fromSaved = saved.settings(recent: nil, now: BuildPlannerTests.now, calendar: Self.calendar)
        #expect(fromSaved.currentWeeklyMeters == 5_000)
        #expect(fromSaved.currentWeeklyClimbMeters == 50)
    }

    @Test func handPickedEasyWeeksArentSaved() {
        #expect(SavedBuildAnswers(BuildPlannerTests.fiftyK(easyWeeks: .chosen([3])), at: BuildPlannerTests.now).easyWeeks == .standard)
        #expect(SavedBuildAnswers(BuildPlannerTests.fiftyK(easyWeeks: .every(5)), at: BuildPlannerTests.now).easyWeeks == .every(5))
    }

    @Test func savedAnswersComeBackAsTheSameSettings() throws {
        let answers = SavedBuildAnswers(BuildPlannerTests.fiftyK(), at: BuildPlannerTests.now)
        let decoded = try JSONDecoder().decode(SavedBuildAnswers.self, from: JSONEncoder().encode(answers))
        #expect(decoded == answers)
        #expect(decoded.settings(recent: nil, now: BuildPlannerTests.now, calendar: Self.calendar) == BuildPlannerTests.fiftyK())
    }

    // MARK: The week now

    @Test func theWeekNowAveragesTheFourWeeksBeforeToday() {
        let runs = [
            CoachRun(start: Self.day(-29), meters: 100_000, climb: 1_000),
            CoachRun(start: Self.day(-28), meters: 4_000, climb: 40),
            CoachRun(start: Self.day(-1).addingTimeInterval(3_600), meters: 8_000, climb: 80),
            CoachRun(start: Self.day(0).addingTimeInterval(3_600), meters: 100_000, climb: 1_000),
        ]
        let week = BuildPlanner.recentWeek(runs, now: BuildPlannerTests.now, calendar: Self.calendar)
        #expect(week == WeekVolume(meters: 3_000, climb: 30))
        #expect(BuildPlanner.recentDays == 28)
        #expect(BuildPlanner.recentWeek([], now: BuildPlannerTests.now, calendar: Self.calendar) == nil)
        #expect(BuildPlanner.recentWeek([runs[3]], now: BuildPlannerTests.now, calendar: Self.calendar) == nil)
    }

    @Test func weekVolumesAddUpAndAverage() {
        let sessions = [
            BuildSession(date: Self.day(1), kind: .easy, target: WeekVolume(meters: 1_000, climb: 10)),
            BuildSession(date: Self.day(2), kind: .long, target: WeekVolume(meters: 2_000, climb: 20)),
        ]
        #expect(BuildEngine.total(sessions) == WeekVolume(meters: 3_000, climb: 30))
        #expect(BuildEngine.total([]) == .zero)
        #expect(WeekVolume.sum(sessions) { $0.target }.divided(by: 2) == WeekVolume(meters: 1_500, climb: 15))
    }

    // MARK: Weekdays

    @Test func weekdaysWrapAroundTheWeek() {
        #expect(Weekday.sunday.adding(-1) == .saturday)
        #expect(Weekday.monday.adding(15) == .tuesday)
        #expect(Weekday.saturday.adding(1) == .sunday)
        #expect(Weekday.wednesday.adding(0) == .wednesday)
        #expect(Weekday(of: BuildPlannerTests.now, calendar: Self.calendar) == .wednesday)
        #expect(Weekday.thursday.shortName == "Thu")
    }

    // MARK: Growth

    @Test func growthEdges() {
        #expect(BuildPlanner.rate(from: 0, to: 10, weeks: 5) == BuildLimits.maxGrowth)
        #expect(BuildPlanner.rate(from: 5, to: 0, weeks: 3) == 0)
        #expect(BuildPlanner.rate(from: 10, to: 20, weeks: 0) == BuildLimits.maxGrowth)
        #expect(BuildPlanner.grow(30, by: 0.1, to: 20) == 30)
        #expect(BuildPlanner.grow(10, by: 0.1, to: 10.5) == 10.5)
        #expect(BuildPlanner.grow(8, by: 0.5, to: 20) == 12)
    }

    @Test func weekReachingCountsBuildingWeeksOnly() {
        #expect(BuildPlanner.weekReaching(0, from: 5, rate: 0.1, first: 1, schedule: .standard) == nil)
        #expect(BuildPlanner.weekReaching(10, from: 10, rate: 0.1, first: 1, schedule: .standard) == 0)
        // Within the peak tolerance counts as there.
        #expect(BuildPlanner.weekReaching(10, from: 9.995, rate: 0.1, first: 1, schedule: .standard) == 0)
        #expect(BuildPlanner.weekReaching(10, from: 0, rate: 0.1, first: 1, schedule: .standard) == nil)
        // Week 1 is easy, so week 2 is the first that grows.
        #expect(BuildPlanner.weekReaching(12, from: 8, rate: 0.5, first: 1, schedule: .chosen([1])) == 2)
    }

    @Test func keptRunsGoToTheLongRunFirst() {
        #expect(BuildPlanner.keptRuns(900, runs: 3, longIndex: 2).isEmpty)
        #expect(BuildPlanner.keptRuns(4_500, runs: 4, longIndex: 3) == [3, 0])
        #expect(BuildPlanner.keptRuns(10_000, runs: 3, longIndex: nil) == [0, 1, 2])
        #expect(BuildPlanner.keptRuns(1_500, runs: 3, longIndex: nil) == [0])
    }

    // MARK: Timeline

    static func timeline(_ volumes: [WeekVolume], peak: WeekVolume, fastest: Int? = nil, firstRate: Double = 0) -> BuildTimeline {
        BuildTimeline(
            calendar: PlanCalendar(firstStart: day(0), count: volumes.count),
            weeks: volumes.enumerated().map { TimelineWeek(number: $0.offset + 1, kind: .building, volume: $0.element) },
            peak: peak,
            fastestPeakWeek: fastest,
            slowestPeakWeek: fastest,
            fastestClimbWeek: nil,
            slowestClimbWeek: nil,
            firstRate: firstRate
        )
    }

    @Test func aWeekWithinTheToleranceReachesThePeak() {
        let near = Self.timeline([WeekVolume(meters: 9_000), WeekVolume(meters: 9_995)], peak: WeekVolume(meters: 10_000))
        #expect(near.reachesPeak)
        #expect(near.reachesClimb)
        #expect(!near.isAmbitious)
        #expect(near.planPeakWeek == 2)
        let short = Self.timeline([WeekVolume(meters: 9_000), WeekVolume(meters: 9_980)], peak: WeekVolume(meters: 10_000))
        #expect(!short.reachesPeak)
        #expect(short.isAmbitious)
        #expect(short.planPeakWeek == nil)
    }

    @Test func thePeakWeekNeedsTheClimbToo() {
        let peak = WeekVolume(meters: 10_000, climb: 100)
        let climbs = Self.timeline([WeekVolume(meters: 10_000, climb: 50), WeekVolume(meters: 10_000, climb: 99.95)], peak: peak)
        #expect(climbs.reachesClimb)
        #expect(climbs.planPeakWeek == 2)
        let flat = Self.timeline([WeekVolume(meters: 10_000, climb: 50)], peak: peak)
        #expect(flat.reachesPeak)
        #expect(!flat.reachesClimb)
        #expect(flat.isAmbitious)
        #expect(flat.planPeakWeek == nil)
    }

    /// Only the words with no dates or formatted numbers, which follow the device's locale.
    @Test func timelineSummaryWords() {
        let atPeak = Self.timeline(Array(repeating: WeekVolume(meters: 10_000), count: 4), peak: WeekVolume(meters: 10_000), fastest: 0)
        let summary = BuildTimelineSummary(timeline: atPeak, unit: .kilometers, event: .marathon, calendar: Self.calendar)
        #expect(summary.headline == "You're at your peak week already")
        #expect(summary.subheadline.hasPrefix("4 weeks to "))
        #expect(summary.subheadline.hasSuffix(". Your plan holds your mileage."))
        #expect(summary.ambitiousNote == nil)
        #expect(summary.planAmbitiousNote == nil)
        #expect(summary.rows.map { $0.0 } == ["Fastest safe build", "Gentle build", "Easy weeks"])
        #expect(summary.rows.last?.1 == "0, including your event week")

        let growing = Self.timeline(Array(repeating: WeekVolume(meters: 10_000), count: 4), peak: WeekVolume(meters: 10_000), fastest: 0, firstRate: 0.05)
        #expect(BuildTimelineSummary(timeline: growing, unit: .kilometers, event: .marathon, calendar: Self.calendar).subheadline.hasSuffix(". Your plan adds about 5% a week, then holds the peak."))

        let hilly = Self.timeline([WeekVolume(meters: 10_000, climb: 100)], peak: WeekVolume(meters: 10_000, climb: 100), fastest: 0)
        let hillyRows = BuildTimelineSummary(timeline: hilly, unit: .kilometers, event: .marathon, calendar: Self.calendar).rows
        #expect(hillyRows.count == 4)
        #expect(hillyRows[2].0 == "Peak climb, fastest / gentle")
        #expect(hillyRows[2].1 == "not in sight / not in sight")
    }

    @Test func anAmbitiousTimelineSaysSo() throws {
        let short = Self.timeline([WeekVolume(meters: 9_000)], peak: WeekVolume(meters: 10_000))
        let summary = BuildTimelineSummary(timeline: short, unit: .kilometers, event: .marathon, calendar: Self.calendar)
        #expect(summary.subheadline.hasPrefix("1 week to "))
        #expect(summary.subheadline.hasSuffix(", adding the most the coach allows."))
        let note = try #require(summary.ambitiousNote)
        #expect(note.hasPrefix("Even adding 10% every week, by the event you'd reach "))
        #expect(note.hasSuffix(". The plan still starts. You may need to walk some of the event, or pick a later date."))
        let planNote = try #require(summary.planAmbitiousNote)
        #expect(planNote.hasPrefix("Your plan adds the most the coach allows each week. By the event you'd reach "))
        #expect(planNote.hasSuffix(", so you may need to walk some of it."))
    }

    // MARK: Words and formats

    @Test func yourEventReadsTheSameForEveryEvent() {
        for event in GoalEvent.allCases {
            #expect(event.yourName == (event == .custom ? "your event" : "your \(event.shortName)"))
        }
        #expect(GoalEvent.marathon.yourName == "your marathon")
        #expect(GoalEvent.halfMarathon.yourName == "your half")
        #expect(GoalEvent.fiveK.yourName == "your 5K")
        #expect(GoalEvent.custom.yourName == "your event")
    }

    @Test func coachFormats() {
        #expect(CoachFormat.weeks(0) == "0 weeks")
        #expect(CoachFormat.weeks(1) == "1 week")
        #expect(CoachFormat.weeks(3) == "3 weeks")
        #expect(CoachFormat.percent(0.5) == 50)
        #expect(CoachFormat.percent(0.05) == 5)
        #expect(CoachFormat.percent(0) == 0)
        #expect(CoachFormat.percent(0.104) == 10)
        #expect(CoachFormat.minutes(29) == "0 min")
        #expect(CoachFormat.minutes(2_700) == "45 min")
        #expect(CoachFormat.minutes(3_600) == "1 h")
        #expect(CoachFormat.minutes(4_800) == "1 h 20 min")
    }

    @Test func targetSummaryLeavesOutWhatIsntSet() {
        var target = CoachWorkoutTarget(title: "Easy run", detail: "", notes: "", meters: nil, seconds: 2_700, pace: nil, effort: 2 ... 3, runWalk: "4 min run, 1 min walk", isKeySession: false, isQuality: false)
        #expect(CoachFormat.targetSummary(target, unit: .kilometers) == "45 min · effort 2–3 · 4 min run, 1 min walk")
        target.seconds = nil
        target.effort = 2 ... 2
        target.runWalk = nil
        #expect(CoachFormat.targetSummary(target, unit: .kilometers) == "effort 2")
    }

    @Test func climbUnitsFollowTheDistanceUnit() {
        #expect(DistanceUnit.miles.metersPerClimbUnit == 0.3048)
        #expect(DistanceUnit.kilometers.metersPerClimbUnit == 1)
        // Under 1,000, so no grouping separator depends on the locale.
        #expect(DistanceUnit.miles.climb(152.4) == "500 ft")
        #expect(DistanceUnit.kilometers.climb(160) == "160 m")
        let model = BuildSetupModel(saved: nil, unit: .miles, now: BuildPlannerTests.now, calendar: Self.calendar)
        #expect(model.climbStep == 0.3048)
        #expect(model.climbSymbol == "ft")
    }

    // MARK: Stored names

    @Test func sessionStatusesKeepTheirStoredNames() {
        #expect(BuildSessionStatus.planned.rawName == "planned")
        #expect(BuildSessionStatus.done(runID: UUID()).rawName == "done")
        #expect(BuildSessionStatus.missed.rawName == "missed")
        #expect(CoachWorkoutStatus.done == "done")
        #expect(CoachWorkoutStatus.missed == "missed")
    }

    @Test func aClosedWeekIsDoneAtNinetyPercent() {
        var week = BuildWeek(number: 1, start: Self.day(0), kind: .building, target: WeekVolume(meters: 10_000), baseBefore: .zero, holdBefore: false, sessions: [], done: WeekVolume(meters: 9_000), closed: false)
        #expect(week.outcomeName == nil)
        week.closed = true
        #expect(week.outcomeName == "done")
        week.done = WeekVolume(meters: 5_000)
        #expect(week.outcomeName == "short")
        // Nothing planned reads as done.
        week.target = .zero
        #expect(week.outcomeName == "done")
    }

    // MARK: Heart rate

    @Test func onlyAStrapOrWatchCanCue() {
        #expect(!HeartRateDevice.off.canCue)
        #expect(HeartRateDevice.appleWatch.canCue)
        #expect(HeartRateDevice.chestStrap.canCue)
        #expect(!HeartRateDevice.earbuds.canCue)
    }

    @Test func heartRateSettingsFromBeforeTheSwitch() throws {
        func decode(_ json: String) throws -> HeartRateSettings {
            try JSONDecoder().decode(HeartRateSettings.self, from: Data(json.utf8))
        }
        let strap = try decode(#"{"device":"chestStrap"}"#)
        #expect(strap.enabled)
        #expect(strap.device == .chestStrap)
        #expect(strap.useForCoaching)
        #expect(strap.labMax == nil)
        #expect(strap.coachingAllowed)
        let empty = try decode("{}")
        #expect(empty.device == .off)
        #expect(!empty.enabled)
        let switchedOff = try decode(#"{"device":"appleWatch","enabled":false}"#)
        #expect(switchedOff.device == .appleWatch)
        #expect(!switchedOff.enabled)
        let showOnly = try decode(#"{"device":"chestStrap","useForCoaching":false,"labMax":180}"#)
        #expect(!showOnly.useForCoaching)
        #expect(showOnly.labMax == 180)
        #expect(!showOnly.coachingAllowed)
    }

    @Test func aLabMaximumOnlyLowersTheEstimate() {
        #expect(HeartRateZones.estimated(age: 18).max == 195)
        #expect(HeartRateZones.estimated(age: 18, labMax: 180).max == 180)
        #expect(HeartRateZones.estimated(age: 18, labMax: 200).max == 195)
        #expect(HeartRateZones.estimated(age: 18, labMax: 300).max == 195)
    }
}
