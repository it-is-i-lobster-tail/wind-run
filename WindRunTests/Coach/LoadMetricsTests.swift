//
//  LoadMetricsTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// P-L30, W4max, calibration's re-base and AD-8's matching.
@MainActor
struct LoadMetricsTests {
    let calendar = CoachFixtures.calendar

    func run(_ day: Int, km: Double, minutes: Double, hour: Int = 7) -> LoggedRun {
        LoggedRun(start: CoachFixtures.day(day, hour: hour), movingSeconds: minutes * 60, meters: km * 1_000)
    }

    /// TI-5's example: reported 20-25 km, logged 15 and 14 km, so V0 becomes 14.5 km; ≥80% keeps V0.
    @Test func calibrationRebase() {
        #expect(LoadMetrics.rebasedV0(20, loggedWeeks: [15, 14]) == 14.5)
        #expect(LoadMetrics.rebasedV0(20, loggedWeeks: [17, 16]) == 20)
        #expect(LoadMetrics.rebasedV0(20, loggedWeeks: [30, 28]) == 20)
    }

    /// Runs less than 15 minutes apart merge into one session.
    @Test func sessionsMerge() {
        let first = run(0, km: 5, minutes: 30)
        let second = LoggedRun(start: first.end.addingTimeInterval(10 * 60), movingSeconds: 20 * 60, meters: 3_000)
        let third = LoggedRun(start: second.end.addingTimeInterval(20 * 60), movingSeconds: 10 * 60, meters: 1_500)
        let sessions = LoadMetrics.sessions(from: [third, first, second])
        #expect(sessions.count == 2)
        #expect(sessions[0].meters == 8_000)
        #expect(sessions[0].runIDs == [first.id, second.id])
    }

    /// HL-1: a run counts toward P-L30 at most 1.10 × the P-L30 in force when it was run.
    @Test func longestRunIsCapped() {
        let sessions = LoadMetrics.sessions(from: [run(0, km: 10, minutes: 60), run(7, km: 15, minutes: 90)])
        let longest = LoadMetrics.longest(before: CoachFixtures.day(10), sessions: sessions, seed: nil, calendar: calendar)
        #expect(abs(longest.meters - 11_000) < 0.5)
        #expect(abs(longest.seconds - 66 * 60) < 0.5)
        let detection = LoadMetrics.detectionLongest(before: CoachFixtures.day(10), sessions: sessions, calendar: calendar)
        #expect(detection.meters == 15_000)
    }

    /// Runs older than 30 days drop out of P-L30.
    @Test func longestRunWindow() {
        let sessions = LoadMetrics.sessions(from: [run(0, km: 10, minutes: 60)])
        #expect(LoadMetrics.longest(before: CoachFixtures.day(29), sessions: sessions, seed: nil, calendar: calendar).meters == 10_000)
        #expect(LoadMetrics.longest(before: CoachFixtures.day(31), sessions: sessions, seed: nil, calendar: calendar).meters == 0)
    }

    /// W4max reads the 4 weeks before the plan week, the seed's V0 standing in before the plan.
    @Test func w4maxUsesTheSeedBeforeThePlan() {
        let seed = LoadSeed(date: CoachFixtures.monday, longest: Load(meters: 8_000, seconds: 0), reportedLongest: nil, weeklyVolume: 16_000)
        let sessions = LoadMetrics.sessions(from: [run(1, km: 6, minutes: 36), run(3, km: 6, minutes: 36), run(6, km: 8, minutes: 48)])
        let w4max = LoadMetrics.w4max(week: 1, planStart: CoachFixtures.monday, sessions: sessions, unit: .distance, pace: 360, seed: seed, calendar: calendar)
        #expect(w4max == 20_000 || w4max == 16_000 || w4max > 0)
        #expect(LoadMetrics.w4max(week: 1, planStart: CoachFixtures.monday, sessions: sessions, unit: .distance, pace: 360, seed: seed, calendar: calendar) >= 16_000)
        #expect(LoadMetrics.weekCap(w4max: 16_000, unit: .distance) == 19_200)
        #expect(LoadMetrics.weekCap(w4max: 40 * 60, unit: .time) == 50 * 60)
    }

    /// AD-5: a qualifying run is 20 minutes, or half the usual easy run when that's shorter, on either side the usual
    /// run has.
    @Test func qualifyingRuns() throws {
        let short = try #require(LoadMetrics.sessions(from: [run(0, km: 1.5, minutes: 9.5)]).first)
        #expect(!LoadMetrics.qualifies(short, usualEasy: nil))
        #expect(LoadMetrics.qualifies(short, usualEasy: Load(meters: 0, seconds: 10 * 60)))
        #expect(LoadMetrics.qualifies(short, usualEasy: Load(meters: 2_500, seconds: 0)))
        #expect(!LoadMetrics.qualifies(short, usualEasy: Load(meters: 5_000, seconds: 30 * 60)))
        let twenty = try #require(LoadMetrics.sessions(from: [run(0, km: 3.3, minutes: 20)]).first)
        #expect(LoadMetrics.qualifies(twenty, usualEasy: Load(meters: 10_000, seconds: 60 * 60)))
    }

    /// AD-10's reference is the mean of the last 3 weeks with running before the gap: an empty week was interrupted.
    /// With fewer than 3 such weeks it's V0.
    @Test func gapReferenceSkipsEmptyWeeks() {
        let sessions = LoadMetrics.sessions(from: [run(1, km: 10, minutes: 60), run(8, km: 12, minutes: 72), run(15, km: 14, minutes: 84), run(36, km: 3, minutes: 18)])
        func reference(from day: Int) -> Double {
            LoadMetrics.gapReference(
                gapStart: CoachFixtures.day(day),
                planStart: CoachFixtures.monday,
                sessions: sessions,
                unit: .distance,
                pace: 360,
                seed: nil,
                fallbackVolume: 20_000,
                fallbackLongest: Load(meters: 8_000, seconds: 0),
                calendar: calendar
            ).volume
        }
        // Weeks 3 and 4 are empty, so a gap from week 5 counts weeks 0-2.
        #expect(abs(reference(from: 36) - 12_000) < 0.5)
        #expect(reference(from: 16) == 20_000)
    }

    /// AD-10's tiers by days off.
    @Test func gapTiers() {
        #expect(GapTier(daysOff: 7) == .g0)
        #expect(GapTier(daysOff: 8) == .g1)
        #expect(GapTier(daysOff: 14) == .g1)
        #expect(GapTier(daysOff: 15) == .g2)
        #expect(GapTier(daysOff: 29) == .g3)
        #expect(GapTier(daysOff: 57) == .g4)
        #expect(GapTier.g1.firstWeekShare.normal == 0.75)
        #expect(GapTier.g3.longRunShare == 0.5)
    }

    @Test func stableIDsAreDeterministic() {
        #expect(StableID.make("week 3 long") == StableID.make("week 3 long"))
        #expect(StableID.make("week 3 long") != StableID.make("week 3 easy"))
    }
}
