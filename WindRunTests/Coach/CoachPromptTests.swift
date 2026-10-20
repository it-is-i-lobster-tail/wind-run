//
//  CoachPromptTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// The coach's wording for each question card (Check-ins, Reporting an injury, AD-9, AD-12, EV-9).
@MainActor
struct CoachPromptTests {
    let calendar = CoachFixtures.calendar

    @Test func everyQuestionHasWords() {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let id = UUID()
        let questions: [CoachQuestion] = [
            .runCheckIn(runID: id), .whatHappened(runID: id), .morningCheck(runID: id), .weeklyCheckIn(weekIndex: 0),
            .readiness(sessionID: id), .medicalClearance(reportID: id), .recoveryPlan(reportID: id), .injuryCheck(reportID: id),
            .readyToRun(reportID: id), .mildFollowUp(reportID: id), .suggestIntense(reportID: id), .suggestRepeatOrPause(reportID: id),
            .suggestRepeat(reportID: id), .illnessKind(episodeID: id), .illnessGone(episodeID: id), .stillNormal(episodeID: id),
            .missedRuns, .dipCheck, .rampDrops, .moveKeySession(sessionID: id, toDay: 2), .levelUp(.ambitious), .lighterWeek,
            .didYouRace, .nextGoal, .reportInjury(origin: .planScreen, runID: nil), .ladderEasierRestart,
            .extraRunSlot(day: .wednesday), .swapRunDay(from: .tuesday, to: .wednesday), .walkBreaks, .benchmarkSooner, .cadenceCue,
            .ladderIdleRestart, .ladderRestartWhere, .raceIllness(daysOut: 14), .raceHeat(daysOut: 3), .eventDetails,
            .reask(.otherTraining), .redoIntake, .goalAlternatives,
        ]
        for question in questions {
            let prompt = CoachEngine.prompt(for: question, state: state, calendar: calendar)
            #expect(!prompt.text.isEmpty)
            #expect(Set(prompt.choices.map(\.value)).count == prompt.choices.count)
        }
    }

    @Test func answersMapBackToTheirCases() {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let dip = CoachEngine.prompt(for: .dipCheck, state: state, calendar: calendar)
        #expect(dip.text == "Your running dipped this week. Everything OK?")
        #expect(dip.choices.map(\.label) == ["Busy", "Ill", "Injured", "Tired", "Fine"])
        #expect(dip.choices.compactMap { MissedRunsReason(rawValue: $0.value) } == [.busy, .sick, .injured, .wornOut, .fine])

        let clearance = CoachEngine.prompt(for: .medicalClearance(reportID: UUID()), state: state, calendar: calendar)
        #expect(clearance.choices.compactMap { ClearanceAnswer(rawValue: $0.value) } == [.yes, .no, .notSure])

        let level = CoachEngine.prompt(for: .reportInjury(origin: .planScreen, runID: nil), state: state, calendar: calendar)
        #expect(level.choices.map(\.value) == ["mild", "intense", "severe"])
    }

    /// The injury questions name the area, and Mild asks its own weekly check (AD-13a, AD-13b, AD-14a).
    @Test func injuryWordingNamesTheArea() {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        let baseline = InjuryBaseline(volumeUnit: .distance, weekVolume: 20_000, longRun: Load(meters: 8_000, seconds: 2_880))
        let mild = InjuryReport(reportedAt: CoachFixtures.day(3), origin: .planScreen, level: .mild, area: .knee, baseline: baseline)
        let intense = InjuryReport(reportedAt: CoachFixtures.day(3), origin: .planScreen, level: .intense, baseline: baseline)
        state.injuries = [mild, intense]

        let mildCheck = CoachEngine.prompt(for: .injuryCheck(reportID: mild.id), state: state, calendar: calendar)
        #expect(mildCheck.text == "How's your knee?")
        #expect(mildCheck.choices.compactMap { MildCheckAnswer(rawValue: $0.value) } == [.cleared, .stillThere, .worse])

        let intenseCheck = CoachEngine.prompt(for: .injuryCheck(reportID: intense.id), state: state, calendar: calendar)
        #expect(intenseCheck.text == "How's your injury now?")
        #expect(intenseCheck.choices.map(\.label) == ["Better", "Same", "Worse"])

        let followUp = CoachEngine.prompt(for: .mildFollowUp(reportID: mild.id), state: state, calendar: calendar)
        #expect(followUp.text == "Your knee has been clear for a week. Still clear?")

        let offer = CoachEngine.prompt(for: .recoveryPlan(reportID: intense.id), state: state, calendar: calendar)
        #expect(offer.text == "Here's a recovery plan: 1 week off running, 2 weeks at half your usual distance, then 2 weeks building back.")
    }

    /// With no weather source the pre-session check carries the heat question (RB-8, AD-16), and the stop line
    /// keeps its heat part until the runner says it's cool, and always on runs over 90 minutes (AD-19b).
    @Test func readinessAsksAboutHeat() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let week = try #require(state.weeks.first?.plan)
        let long = try #require(week.sessions.first { $0.kind == .long })
        let heat = try #require(CoachEngine.prompt(for: .readiness(sessionID: long.id), state: state, calendar: calendar).also.first)
        #expect(heat.text == "How hot will it be when you run?")
        #expect(heat.choices.compactMap { HeatAnswer(rawValue: $0.value) } == [.cool, .warm, .hot, .veryHot])

        let easy = try #require(week.sessions.first { $0.kind == .easy })
        let now = CoachFixtures.day(easy.dayOffset, hour: 7)
        func hasHeatPart(_ session: PlannedSession, _ state: CoachState) -> Bool {
            CoachEngine.stopLine(for: session, state: state, now: now, calendar: calendar).contains("in the heat")
        }
        #expect(hasHeatPart(easy, state))
        let cool = CoachEngine.submitReadiness(.goodToGo, heat: .cool, sessionID: easy.id, state: state, runs: [], now: now, calendar: calendar).state
        #expect(CoachEngine.stopLine(for: easy, state: cool, now: now, calendar: calendar) == SafetyText.stopLine)
        let warm = CoachEngine.submitReadiness(.goodToGo, heat: .warm, sessionID: easy.id, state: state, runs: [], now: now, calendar: calendar).state
        #expect(hasHeatPart(easy, warm))
        var longer = easy
        longer.target = Load(meters: 0, seconds: 100 * 60)
        #expect(hasHeatPart(longer, cool))
    }

    /// AD-9's offer names the days.
    @Test func moveOfferNamesTheDays() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let week = try #require(state.weeks.first?.plan)
        let long = try #require(week.sessions.first { $0.kind == .long })
        let prompt = CoachEngine.prompt(for: .moveKeySession(sessionID: long.id, toDay: 1), state: state, calendar: calendar)
        let from = Weekday(of: week.start, calendar: calendar).adding(long.dayOffset).name
        let to = Weekday(of: week.start, calendar: calendar).adding(1).name
        #expect(prompt.text == "Move \(from)'s long run to \(to)?")
    }
}
