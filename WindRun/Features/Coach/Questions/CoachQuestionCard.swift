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
                    ChoiceButtons(choices: prompt.choices) { answer($0, state: state) }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }

    /// The after-race questions wait for the engine's after-race module.
    private var answersOnCard: Bool {
        switch question {
        case .didYouRace, .nextGoal: false
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
        case .didYouRace, .nextGoal:
            // TODO: answer these once the engine's after-race module lands.
            Text("Coming soon.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                actions.perform { state, runs, now, calendar in
                    CoachEngine.submitReadiness(answer, heat: nil, sessionID: sessionID, state: state, runs: runs, now: now, calendar: calendar)
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
        case .missedRuns:
            if let reason: MissedRunsReason = Self.decode(value) { route(actions.answer(.missedRuns(reason))) }
        case .dipCheck:
            if let reason: MissedRunsReason = Self.decode(value) { route(actions.answer(.dipCheck(reason))) }
        case .rampDrops:
            if let reason: MissedRunsReason = Self.decode(value) { route(actions.answer(.rampDrops(reason))) }
        case .moveKeySession(let sessionID, let day):
            route(actions.answer(.moveKeySession(sessionID: sessionID, toDay: day, accept: yes)))
        case .levelUp:
            route(actions.answer(.levelUp(yes)))
        case .lighterWeek:
            route(actions.answer(.lighterWeek(yes)))
        case .ladderEasierRestart:
            route(actions.answer(.ladderEasierRestart(yes)))
        case .runCheckIn, .morningCheck, .weeklyCheckIn, .recoveryPlan, .didYouRace, .nextGoal:
            break
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
