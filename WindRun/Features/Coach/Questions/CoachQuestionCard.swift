//
//  CoachQuestionCard.swift
//  Wind Run
//

import SwiftUI

/// One question from the coach, with its answers right on the card or a button to the screen
/// that asks it.
struct CoachQuestionCard: View {
    let question: CoachQuestion
    let actions: CoachActions
    let open: (CoachSheet) -> Void

    private var state: CoachState? { actions.state() }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Text(CoachQuestionText.prompt(for: question, state: state))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            answers
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }

    @ViewBuilder
    private var answers: some View {
        switch question {
        case .runCheckIn(let runID):
            openButton("Rate it") { open(.runCheckIn(runID: runID)) }
        case .whatHappened(let runID):
            choices(WhatHappened.allCases, title: \.name) { answer in
                saveWhatHappened(answer, runID: runID)
            }
        case .morningCheck(let runID):
            openButton("Answer") { open(.morningCheck(runID: runID)) }
        case .weeklyCheckIn(let weekIndex):
            openButton("Check in") { open(.weeklyCheckIn(weekIndex: weekIndex)) }
        case .readiness(let sessionID):
            choices(ReadinessAnswer.allCases, title: \.name) { answer in
                actions.perform { state, runs, now, calendar in
                    CoachEngine.submitReadiness(answer, heat: nil, sessionID: sessionID, state: state, runs: runs, now: now, calendar: calendar)
                }
            }
        case .medicalClearance(let reportID):
            choices(ClearanceAnswer.allCases, title: \.name) { answer in
                answerInjury(.clearance(answer), reportID: reportID)
                if answer == .yes { open(.recoveryPlan(reportID: reportID)) }
            }
        case .recoveryPlan(let reportID):
            openButton("Set up") { open(.recoveryPlan(reportID: reportID)) }
        case .injuryCheck(let reportID):
            if state?.injuries.first(where: { $0.id == reportID })?.level == .mild {
                choices(MildCheckAnswer.allCases, title: \.name) { answerInjury(.mildCheck($0), reportID: reportID) }
            } else {
                choices(RecoveryCheckAnswer.allCases, title: \.name) { answerInjury(.recoveryCheck($0), reportID: reportID) }
            }
        case .readyToRun(let reportID):
            HStack {
                Button("Yes, I'm ready") {
                    answerInjury(.ready(true), reportID: reportID)
                    open(.returnPlan(reportID: reportID))
                }
                .buttonStyle(.glassProminent)
                Button("Not yet") { answerInjury(.ready(false), reportID: reportID) }
                    .buttonStyle(.glass)
            }
        case .mildFollowUp(let reportID):
            choices(FollowUpAnswer.allCases, title: \.name) { answerInjury(.followUp($0), reportID: reportID) }
        case .suggestIntense(let reportID):
            choices([InjurySuggestionChoice.switchToIntense, .keepGoing], title: \.name) { answerInjury(.suggestion($0), reportID: reportID) }
        case .suggestRepeatOrPause(let reportID):
            choices([InjurySuggestionChoice.repeatWeek, .pausePlan, .keepGoing], title: \.name) { answerInjury(.suggestion($0), reportID: reportID) }
        case .suggestRepeat(let reportID):
            choices([InjurySuggestionChoice.repeatWeek, .keepGoing], title: \.name) { answerInjury(.suggestion($0), reportID: reportID) }
        case .illnessKind(let episodeID):
            choices(IllnessKind.allCases, title: \.name) { answerIllness(.kind($0), episodeID: episodeID) }
        case .illnessGone(let episodeID):
            choices(HeadColdCheck.allCases, title: \.name) { answerIllness(.headCold($0), episodeID: episodeID) }
        case .stillNormal(let episodeID):
            yesNo { answerIllness(.stillNormal($0), episodeID: episodeID) }
        case .missedRuns:
            choices(MissedRunsReason.allCases.filter { $0 != .fine }, title: \.name) { route(actions.answer(.missedRuns($0))) }
        case .dipCheck:
            choices(MissedRunsReason.allCases, title: \.name) { route(actions.answer(.dipCheck($0))) }
        case .rampDrops:
            choices(MissedRunsReason.allCases.filter { $0 != .fine }, title: \.name) { route(actions.answer(.rampDrops($0))) }
        case .moveKeySession(let sessionID, let day):
            yesNo { route(actions.answer(.moveKeySession(sessionID: sessionID, toDay: day, accept: $0))) }
        case .levelUp(let level):
            yesNo(yes: "Move up to \(level.name)", no: "Stay") { _ = actions.answer(.levelUp($0)) }
        case .lighterWeek:
            yesNo(yes: "Yes, lighter", no: "No, keep it") { _ = actions.answer(.lighterWeek($0)) }
        case .ladderEasierRestart:
            yesNo { _ = actions.answer(.ladderEasierRestart($0)) }
        case .didYouRace, .nextGoal:
            // TODO: after-race screens arrive with the engine's after-race module.
            Text("Coming soon.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .reportInjury(let origin, let runID):
            openButton("Report injury") { open(.reportInjury(origin: origin, runID: runID)) }
        }
    }

    // MARK: Answering

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
            if let (update, _) = actions.service.saveCheckIn(checkIn, for: run, in: actions.plan) {
                actions.inbox.receive(update)
            }
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
            if let week = state?.weeks.last?.plan.index { open(.weeklyCheckIn(weekIndex: week)) }
        case .lifeHappensBusy: open(.lifeHappens(.busy))
        case .lifeHappensTravel: open(.lifeHappens(.travelling))
        case nil: break
        }
    }

    // MARK: Controls

    private func openButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.glassProminent)
    }

    private func yesNo(yes: String = "Yes", no: String = "No", answer: @escaping (Bool) -> Void) -> some View {
        HStack {
            Button(yes) { answer(true) }
                .buttonStyle(.glassProminent)
            Button(no) { answer(false) }
                .buttonStyle(.glass)
        }
    }

    private func choices<Choice: Hashable>(_ choices: [Choice], title: KeyPath<Choice, String>, answer: @escaping (Choice) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(choices, id: \.self) { choice in
                Button {
                    answer(choice)
                } label: {
                    Text(choice[keyPath: title])
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.secondary.opacity(VisualOpacity.subtle), in: .rect(cornerRadius: LayoutMetrics.compactCornerRadius))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension InjurySuggestionChoice {
    var name: String {
        switch self {
        case .repeatWeek: "Repeat the week"
        case .pausePlan: "Pause the plan"
        case .keepGoing: "Keep going"
        case .switchToIntense: "Move it to Intense"
        }
    }
}
