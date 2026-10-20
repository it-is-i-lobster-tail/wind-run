//
//  CoachQuestionCard.swift
//  Wind Run
//

import SwiftUI

/// One question from the coach, in the coach's words, with its answers right on the card or a
/// button to the screen that asks it.
struct CoachQuestionCard: View {
    let question: CoachQuestion
    let actions: CoachActions
    let open: (CoachSheet) -> Void

    /// Answers to the card's optional extra questions, by position, such as the heat question on
    /// the pre-session check. They go in with the main answer.
    @State private var extraAnswers: [Int: String] = [:]

    var body: some View {
        let state = actions.state()
        let prompt = state.map { CoachEngine.prompt(for: question, state: $0, calendar: .current) }
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            if let prompt {
                Text(prompt.text)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = prompt.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if prompt.choices.isEmpty || !answersOnCard {
                    screenButton
                } else {
                    ForEach(Array(prompt.also.enumerated()), id: \.offset) { position, extra in
                        OptionalQuestion(prompt: extra, selection: Binding(
                            get: { extraAnswers[position] },
                            set: { extraAnswers[position] = $0 }
                        ))
                    }
                    ChoiceButtons(choices: prompt.choices) { answer($0, state: state) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }

    /// Questions the engine doesn't ask yet have no answers on the card.
    private var answersOnCard: Bool {
        switch question {
        case .raceIllness, .raceHeat, .eventDetails, .reask, .redoIntake, .goalAlternatives: false
        default: true
        }
    }

    // MARK: Cards that open a screen

    @ViewBuilder
    private var screenButton: some View {
        switch question {
        case .runCheckIn(let runID):
            openButton("Rate it") { open(.runCheckIn(runID: runID)) }
        case .morningCheck(let runID):
            openButton("Answer") { open(.morningCheck(runID: runID)) }
        case .weeklyCheckIn(let weekIndex):
            openButton("Check in") { open(.weeklyCheckIn(weekIndex: weekIndex)) }
        case .recoveryPlan(let reportID):
            openButton("Set it up") { open(.recoveryPlan(reportID: reportID)) }
        case .reportInjury(let origin, let runID):
            openButton("Report injury") { open(.reportInjury(origin: origin, runID: runID)) }
        default:
            EmptyView()
        }
    }

    // MARK: Answers on the card

    /// Maps a tapped choice back to its answer. Choice values are the answer case's name, or "yes"/"no".
    private func answer(_ value: String, state: CoachState?) {
        let yes = value == "yes"
        switch question {
        case .whatHappened(let runID):
            if let answer: WhatHappened = Self.decode(value) { saveWhatHappened(answer, runID: runID) }
        case .readiness(let sessionID):
            if let answer: ReadinessAnswer = Self.decode(value) {
                // The heat question rides along on the same card; skipped, it stays unknown.
                let heat = extraAnswers[0].flatMap(HeatAnswer.init(rawValue:))
                actions.perform { state, runs, now, calendar in
                    CoachEngine.submitReadiness(answer, heat: heat, sessionID: sessionID, state: state, runs: runs, now: now, calendar: calendar)
                }
            }
        case .medicalClearance(let reportID):
            if let answer: ClearanceAnswer = Self.decode(value) {
                answerInjury(.clearance(answer), reportID: reportID)
                if answer == .yes { open(.recoveryPlan(reportID: reportID)) }
            }
        case .injuryCheck(let reportID):
            if let answer: MildCheckAnswer = Self.decode(value), state?.injuries.first(where: { $0.id == reportID })?.level == .mild {
                answerInjury(.mildCheck(answer), reportID: reportID)
            } else if let answer: RecoveryCheckAnswer = Self.decode(value) {
                answerInjury(.recoveryCheck(answer), reportID: reportID)
            }
        case .readyToRun(let reportID):
            answerInjury(.ready(yes), reportID: reportID)
            if yes, state?.injuries.first(where: { $0.id == reportID })?.level == .severe {
                open(.returnPlan(reportID: reportID))
            }
        case .mildFollowUp(let reportID):
            if let answer: FollowUpAnswer = Self.decode(value) { answerInjury(.followUp(answer), reportID: reportID) }
        case .suggestIntense(let reportID), .suggestRepeatOrPause(let reportID), .suggestRepeat(let reportID):
            if let answer: InjurySuggestionChoice = Self.decode(value) { answerInjury(.suggestion(answer), reportID: reportID) }
        case .reportInjury(let origin, let runID):
            open(.reportInjury(origin: origin, runID: runID, level: Self.decode(value)))
        case .illnessKind(let episodeID):
            if let answer: IllnessKind = Self.decode(value) { answerIllness(.kind(answer), episodeID: episodeID) }
        case .illnessGone(let episodeID):
            if let answer: HeadColdCheck = Self.decode(value) { answerIllness(.headCold(answer), episodeID: episodeID) }
        case .stillNormal(let episodeID):
            answerIllness(.stillNormal(yes), episodeID: episodeID)
        case .missedRuns, .dipCheck, .rampDrops, .moveKeySession, .levelUp, .lighterWeek, .ladderEasierRestart,
             .ladderIdleRestart, .ladderRestartWhere, .extraRunSlot, .swapRunDay, .walkBreaks, .benchmarkSooner, .cadenceCue:
            if let answer = Self.coachAnswer(for: question, value: value, state: state) { route(actions.answer(answer)) }
        case .didYouRace:
            switch value {
            case "recordedElsewhere": open(.raceRecordedElsewhere)
            case "raceMoved": open(.raceMoved)
            default: if let answer = Self.coachAnswer(for: question, value: value, state: state) { route(actions.answer(answer)) }
            }
        case .nextGoal:
            if let answer = Self.coachAnswer(for: question, value: value, state: state) {
                route(actions.answer(answer))
            } else if let state {
                // A new goal opens the goal screen: Speed Work at this distance, any distance, or an event.
                switch value {
                case "newGoal": open(.newGoal(.speedWork, distance: state.goal.distance))
                case "newDistance": open(.newGoal(.speedWork, distance: nil))
                case "event": open(.newGoal(.event, distance: nil))
                default: break
                }
            }
        case .runCheckIn, .morningCheck, .weeklyCheckIn, .recoveryPlan,
             .raceIllness, .raceHeat, .eventDetails, .reask, .redoIntake, .goalAlternatives:
            break
        }
    }

    /// The answer for the questions `CoachEngine.answer` takes, from a choice's value. The ladder's
    /// restart choices are positions in `LadderCoach.restartOptions`, so they need the state.
    static func coachAnswer(for question: CoachQuestion, value: String, state: CoachState? = nil) -> CoachAnswer? {
        let yes = value == "yes"
        switch question {
        case .missedRuns: return decode(value).map(CoachAnswer.missedRuns)
        case .dipCheck: return decode(value).map(CoachAnswer.dipCheck)
        case .rampDrops: return decode(value).map(CoachAnswer.rampDrops)
        case .moveKeySession(let sessionID, let day): return .moveKeySession(sessionID: sessionID, toDay: day, accept: yes)
        case .levelUp: return .levelUp(yes)
        case .lighterWeek: return .lighterWeek(yes)
        case .ladderEasierRestart, .ladderIdleRestart: return .ladderEasierRestart(yes)
        case .ladderRestartWhere:
            guard let state, let index = Int(value) else { return nil }
            let options = LadderCoach.restartOptions(state)
            return options.indices.contains(index) ? .ladderRestartAt(options[index]) : nil
        case .extraRunSlot(let day): return .runReview(.extraRunSlot(day: day, accept: yes))
        case .swapRunDay(let from, let to): return .runReview(.swapRunDay(from: from, to: to, accept: yes))
        case .walkBreaks: return .runReview(.walkBreaks(yes))
        case .benchmarkSooner: return .runReview(.benchmarkSooner(yes))
        case .cadenceCue: return .runReview(.cadenceCue(yes))
        case .didYouRace: return value == "didNotStart" ? .didYouRace(.didNotStart) : nil
        case .nextGoal:
            switch value {
            case "maintain": return .nextGoal(.maintain)
            case "nextRung": return .nextGoal(.nextRung)
            case "speedWork": return .nextGoal(.speedWork)
            default: return nil
            }
        default: return nil
        }
    }

    /// The answer case named by a choice's value.
    static func decode<Answer: CaseIterable>(_ value: String) -> Answer? {
        Answer.allCases.first { "\($0)" == value }
    }

    private func answerInjury(_ answer: InjuryAnswer, reportID: UUID) {
        actions.perform { state, runs, now, calendar in
            CoachEngine.answerInjury(answer, reportID: reportID, state: state, runs: runs, now: now, calendar: calendar)
        }
    }

    private func answerIllness(_ answer: IllnessAnswer, episodeID: UUID) {
        actions.perform { state, runs, now, calendar in
            CoachEngine.answerIllness(answer, episodeID: episodeID, state: state, runs: runs, now: now, calendar: calendar)
        }
    }

    private func saveWhatHappened(_ answer: WhatHappened, runID: UUID) {
        if let run = actions.run(withID: runID) {
            var checkIn = run.checkIn ?? RunCheckIn()
            checkIn.whatHappened = answer
            _ = actions.saveCheckIn(checkIn, for: run)
        }
        if answer == .somethingHurt {
            open(.reportInjury(origin: .whatHappened, runID: runID))
        }
    }

    /// Opens the screen a routed answer points to.
    private func route(_ route: CoachRoute?) {
        switch route {
        case .reportInjury: open(.reportInjury(origin: .missedRuns, runID: nil))
        case .wellnessQuestions:
            if let week = actions.state()?.weeks.last?.plan.index { open(.weeklyCheckIn(weekIndex: week)) }
        case .lifeHappensBusy: open(.lifeHappens(.busy))
        case .lifeHappensTravel: open(.lifeHappens(.travelling))
        case nil: break
        }
    }

    private func openButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.glassProminent)
    }
}

/// An optional extra question on a card: its choices as chips, tap again to clear.
private struct OptionalQuestion: View {
    let prompt: CoachPrompt
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(prompt.text) (optional)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips }
                VStack(alignment: .leading, spacing: 6) { chips }
            }
            if let detail = prompt.choices.first(where: { $0.value == selection })?.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }

    private var chips: some View {
        ForEach(prompt.choices, id: \.value) { choice in
            let isOn = selection == choice.value
            Button {
                selection = isOn ? nil : choice.value
            } label: {
                Text(choice.label)
                    .font(.subheadline)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .background(isOn ? Color.accentColor : Color.secondary.opacity(VisualOpacity.subtle), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }
}

/// The answers on a card, one full-width button each.
private struct ChoiceButtons: View {
    let choices: [CoachPrompt.Choice]
    let answer: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(choices, id: \.self) { choice in
                Button {
                    answer(choice.value)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.label)
                        if let detail = choice.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(VisualOpacity.subtle), in: .rect(cornerRadius: LayoutMetrics.compactCornerRadius))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
