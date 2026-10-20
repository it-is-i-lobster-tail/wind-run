//
//  InjuryTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Reporting an injury against the rules' examples: the three levels, the recovery plan and the Severe return, their
/// projections, the weekly checks and the 12-month memory (AD-13 to AD-14e, HL-15, HL-18, TI-3b, TI-3c).
@MainActor
struct InjuryTests {
    let calendar = CoachFixtures.calendar

    /// A plan with the worked examples' runner: a pre-injury week of 30 km over 4 runs and a 12 km long run.
    func examplePlan(level: InjuryLevel, ranThirtyMinutes: Bool = true) -> (state: CoachState, reportID: UUID) {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        state.cycle.runsPerWeek = 4
        state.assessment.runsCap = 4
        state.paces.easy = PaceBand(fast: 360, slow: 360)
        let baseline = InjuryBaseline(
            volumeUnit: .distance,
            weekVolume: 30_000,
            longRun: Load(12_000, in: .distance, pace: 360),
            ranThirtyMinutesNonStop: ranThirtyMinutes
        )
        let report = InjuryReport(reportedAt: CoachFixtures.day(27, hour: 20), origin: .planScreen, level: level, area: .shin, baseline: baseline)
        state.injuries.append(report)
        return (state, report.id)
    }

    func kilometres(_ weeks: [RecoveryWeekPreview]) -> [Double] {
        weeks.map { ($0.volume / 100).rounded() / 10 }
    }

    func longRuns(_ weeks: [RecoveryWeekPreview]) -> [Double] {
        weeks.map { (($0.longRun?.meters ?? 0) / 10).rounded() / 100 }
    }

    // MARK: Projections (AD-14b, AD-14c)

    /// AD-14b's default example: 5 planned weeks become 8 under HL-1 and HL-2.
    @Test func defaultRecoveryPlanProjection() {
        let (state, id) = examplePlan(level: .intense)
        let weeks = InjuryCoach.previewRecovery(.standard, reportID: id, state: state)
        #expect(weeks.map(\.label) == ["Week 1: no running", "Week 2: 50%", "Week 3: 50%", "Week 4: 75%", "Week 5: 100%", "Week 6: 100%", "Week 7: 100%", "Week 8: 100%"])
        #expect(kilometres(weeks) == [0, 15, 15, 22.5, 27, 30, 30, 30])
        #expect(longRuns(weeks) == [0, 6, 6, 9, 9.9, 10.89, 11.98, 12])
        #expect(weeks.map(\.capped) == [false, false, false, false, true, true, true, false])
        let report = state.injuries[0]
        let projection = InjuryCoach.recoveryProjection(.standard, report: report, state: state)
        #expect(projection.plannedWeeks == 5)
        #expect(projection.addedWeeks == 3)
    }

    /// AD-14b's faster example: no week off, 1 week at 70%, then straight back to 100%.
    @Test func fasterRecoveryPlanProjection() {
        let (state, id) = examplePlan(level: .intense)
        let faster = RecoveryPlanSettings(restWeeks: 0, reducedShare: 0.7, reducedWeeks: 1, rampStep: nil)
        let weeks = InjuryCoach.previewRecovery(faster, reportID: id, state: state)
        #expect(weeks.map(\.label) == ["Week 1: 70%", "Week 2: 100%"])
        #expect(kilometres(weeks) == [21, 30])
        #expect(longRuns(weeks) == [8.4, 12])
    }

    /// AD-14c's example: a 3-week pause (G2) gives 2 return weeks at 50%, then HL-2 and the long run's 10% steps.
    @Test func severeReturnProjection() {
        var (state, id) = examplePlan(level: .severe)
        state.injuries[0].pauseStart = CoachFixtures.day(27, hour: 20)
        state.injuries[0].lastRunBeforePause = CoachFixtures.day(27, hour: 7)
        let ready = CoachFixtures.day(48)
        let settings = InjuryCoach.defaultReturn(reportID: id, state: state, now: ready, calendar: calendar)
        #expect(settings == ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: 0.2))
        let weeks = InjuryCoach.previewReturn(settings, reportID: id, state: state, now: ready, calendar: calendar)
        #expect(kilometres(weeks) == [15, 15, 18, 21.6, 25.9, 30, 30, 30, 30, 30])
        #expect(longRuns(weeks) == [6, 6, 6.6, 7.2, 7.9, 8.6, 9.4, 10.3, 11.3, 12])
        #expect(weeks.first?.label == "Week 1: 50%")
        let report = state.injuries[0]
        let projection = InjuryCoach.returnProjection(settings, report: report, state: state, pauseDays: 21)
        #expect(projection.plannedWeeks == 5)
    }

    /// AD-14c's defaults by pause: 50% up to 4 weeks, else 30%; jogging only after a short pause and a 30-min long
    /// run; AD-10's step for the pause's tier.
    @Test func defaultReturnFollowsThePause() {
        var (state, id) = examplePlan(level: .severe)
        state.injuries[0].pauseStart = CoachFixtures.day(27, hour: 20)
        state.injuries[0].lastRunBeforePause = CoachFixtures.day(27, hour: 7)
        func settings(after days: Int) -> ReturnSettings {
            InjuryCoach.defaultReturn(reportID: id, state: state, now: CoachFixtures.day(27 + days), calendar: calendar)
        }
        #expect(settings(after: 5) == ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: 0.25))
        #expect(settings(after: 12) == ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: 0.25))
        #expect(settings(after: 28) == ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: 0.2))
        #expect(settings(after: 40) == ReturnSettings(weeks: 2, form: .jogWalk, share: 0.3, rampStep: 0.15))
        #expect(settings(after: 70) == ReturnSettings(weeks: 2, form: .jogWalk, share: 0.3, rampStep: 0.1))
        state.injuries[0].baseline.ranThirtyMinutesNonStop = false
        #expect(settings(after: 12).form == .jogWalk)
        // A return the runner already set is kept.
        let own = ReturnSettings(weeks: 1, form: .jogging, share: 0.7, rampStep: nil)
        state.injuries[0].returnPlan = own
        #expect(settings(after: 40) == own)
    }

    /// Jog/walk weeks show running minutes: 2 min jogging and 2 walking, then 3 and 1, then 1-min walks while the
    /// jogging doubles (6, 12, 24 min) until the runs are continuous again (AD-14c). After a pause over 4 weeks the
    /// first return week has no W4max to compare with, so it runs at its share.
    @Test func jogWalkReturnCountsRunningMinutes() {
        var (state, id) = examplePlan(level: .severe)
        state.injuries[0].pauseStart = CoachFixtures.day(27, hour: 20)
        state.injuries[0].lastRunBeforePause = CoachFixtures.day(27, hour: 7)
        let ready = CoachFixtures.day(67)
        let settings = InjuryCoach.defaultReturn(reportID: id, state: state, now: ready, calendar: calendar)
        #expect(settings == ReturnSettings(weeks: 2, form: .jogWalk, share: 0.3, rampStep: 0.15))
        let weeks = InjuryCoach.previewReturn(settings, reportID: id, state: state, now: ready, calendar: calendar)
        #expect(weeks.prefix(5).allSatisfy { $0.volumeUnit == .time })
        #expect(weeks.dropFirst(5).allSatisfy { $0.volumeUnit == .distance })
        #expect(weeks.last?.share == 1)
        // 30% of the pre-injury week's running: 9 km at 6:00/km is 54 running minutes, in both return weeks.
        #expect(weeks.prefix(2).map { ($0.volume / 60).rounded() } == [54, 54])
        #expect(weeks.first?.capped == false)
        #expect(InjuryCoach.jogWalkPattern(.returnWeek(number: 0, share: 0.5), form: .jogWalk)! == (120, 120))
        #expect(InjuryCoach.jogWalkPattern(.returnWeek(number: 1, share: 0.5), form: .jogWalk)! == (180, 60))
        #expect(InjuryCoach.jogWalkPattern(.ramp(position: 2, share: 0.9), form: .jogWalk)! == (1_440, 60))
        #expect(InjuryCoach.jogWalkPattern(.ramp(position: 3, share: 1), form: .jogWalk) == nil)
    }

    /// The edit ranges: shares in steps of 10 from 10 to 90%, ramp steps in steps of 5 from 10 to 50 (AD-14b).
    @Test func settingsStayInsideTheirRanges() {
        let settings = RecoveryPlanSettings(restWeeks: -1, reducedShare: 0.94, reducedWeeks: 0, rampStep: 0.63).normalized
        #expect(settings.restWeeks == 0)
        #expect(settings.reducedShare == 0.9)
        #expect(settings.reducedWeeks == 1)
        #expect(settings.rampStep == 0.5)
        #expect(RecoveryPlanSettings(reducedShare: 0.04, rampStep: 0.12).normalized.reducedShare == 0.1)
        #expect(RecoveryPlanSettings(reducedShare: 0.7, rampStep: 0.12).normalized.rampStep == 0.1)
        #expect(ReturnSettings(weeks: 0, form: .jogging, share: 0.35, rampStep: 0.17).normalized == ReturnSettings(weeks: 1, form: .jogging, share: 0.4, rampStep: 0.15))
    }

    /// A repeated ramp week holds the next week's share; the 65+ hold keeps each step for a second week (AD-14b,
    /// AD-10).
    @Test func rampSharesRepeatAndHold() {
        #expect(InjuryCoach.rampShare(0, from: 0.5, step: 0.25) == 0.75)
        #expect(InjuryCoach.rampShare(1, from: 0.5, step: 0.25) == 1)
        #expect(InjuryCoach.rampShare(1, from: 0.5, step: 0.25, holds: [0]) == 0.75)
        #expect(InjuryCoach.rampShare(2, from: 0.5, step: 0.25, holds: [0]) == 1)
        #expect(InjuryCoach.rampShare(1, from: 0.3, step: 0.2, twoWeekHold: true) == 0.5)
        #expect(InjuryCoach.rampShare(2, from: 0.3, step: 0.2, twoWeekHold: true) == 0.7)
        #expect(InjuryCoach.rampShare(2, from: 0.3, step: 0.2, drops: [0]) == 0.5)
        #expect(InjuryCoach.rampShare(0, from: 0.5, step: nil) == 1)
    }
}
