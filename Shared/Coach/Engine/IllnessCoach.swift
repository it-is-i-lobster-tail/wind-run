//
//  IllnessCoach.swift
//  Wind Run
//

import Foundation

/// "Has it gone?" every 3 days with a head cold (AD-12).
enum HeadColdCheck: String, Codable, CaseIterable {
    case gone
    case stillThere
    case nowFever

    var name: String {
        switch self {
        case .gone: "Gone"
        case .stillThere: "Still there"
        case .nowFever: "Now a fever or below the neck"
        }
    }
}

/// An answer to one of the illness questions (AD-12).
enum IllnessAnswer: Codable, Hashable {
    /// "Just a head cold, or a fever or anything below the neck?"
    case kind(IllnessKind)
    case headCold(HeadColdCheck)
    /// On "Ready": "Have you felt back to normal for 2 full days?"
    case ready(Bool)
    /// Stage 2's next-day check: "Still feeling normal after yesterday's run?"
    case stillNormal(Bool)
    /// The runner feels ill again: back one stage (a relapse).
    case feelIllAgain
}

/// Illness and heat illness: the pause, the return stages and the weeks they shape (AD-12, AD-16, HL-19).
enum IllnessCoach {
    /// The runner says they're ill (AD-12). With no kind yet, head-cold rules apply until it's answered (AD-17).
    static func report(kind: IllnessKind?, bedBound: Bool, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        let episode = IllnessEpisode(reportedAt: now, kind: kind, bedBound: bedBound)
        state.illnesses.append(episode)
        if episode.stopsRunning { state.status = .paused(reason: .illness, since: now) }
        let questions: [CoachQuestion] = kind == nil ? [.illnessKind(episodeID: episode.id)] : []
        return CoachUpdate(state: state, questions: questions)
    }

    static func answer(_ answer: IllnessAnswer, episodeID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// "Felt unwell in the heat" (AD-16): running pauses until the runner has felt normal for 24 h.
    static func reportHeatIllness(state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        state.heat.illnessDates.append(now)
        state.heat.easyRunsLeft = 2
        state.status = .paused(reason: .heat, since: now)
        return CoachUpdate(state: state, notes: [CoachNote(.illness, "That sounds like the heat got to you. No running until you've felt normal for a full day, then two short easy runs somewhere cool.")])
    }

    /// A saved run moves the return stages and the heat-illness runs along.
    static func runLogged(_ run: LoggedRun, state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// The week while an illness or heat illness shapes it, or nil.
    static func weekTargets(_ context: PlanningContext) -> WeekTargets? {
        let state = context.state
        guard let episode = state.activeIllness else { return nil }
        if episode.stopsRunning {
            return .paused(notes: [CoachNote(.illness, "No running for now, because you're ill. Your plan is paused, not lost. Tap 'Ready' when you want to start back. If it drags on or keeps coming back, it's worth seeing a doctor.")])
        }
        return nil
    }

    /// AD-5's illness rows, or nil.
    static func outcome(_ state: CoachState) -> (WeekOutcome, OutcomeReason)? {
        if case .paused(.heat, _) = state.status { return (.pause, .heatIllness) }
        guard let episode = state.activeIllness else { return nil }
        if episode.stopsRunning { return (.pause, .illness) }
        if episode.stage == .headCold { return (.ease, .headCold) }
        return nil
    }

    /// Questions the active episode is waiting on.
    static func questions(_ state: CoachState, now: Date, calendar: Calendar) -> [CoachQuestion] {
        guard let episode = state.activeIllness else { return [] }
        if episode.kind == nil { return [.illnessKind(episodeID: episode.id)] }
        return []
    }
}
