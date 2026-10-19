//
//  LadderCoach.swift
//  Wind Run
//

import Foundation

/// The walk stage, the short run-walk and the run-walk ladder to 30 minutes (TI-2, BD-2, AD-18).
enum LadderCoach {
    /// Where a starting runner begins.
    static func initialState(for entry: StarterEntry) -> LadderState {
        switch entry {
        case .walkStage(let minutes):
            LadderState(form: .walkStage, walkMinutes: minutes, stepIndex: 0)
        case .shortRunWalk:
            LadderState(form: .runWalk, stepIndex: 0)
        case .ladder(let step):
            LadderState(form: .runWalk, stepIndex: step.clamped(to: 0 ... RunWalkStep.lastIndex))
        }
    }

    /// The week on the walk stage or the ladder, or nil once the ladder is done.
    static func weekTargets(_ context: PlanningContext) -> WeekTargets? {
        guard let ladder = context.state.ladder, ladder.form != .done else { return nil }
        let runs = min(3, max(2, context.state.cycle.runsPerWeek))
        switch ladder.form {
        case .walkStage:
            return WeekTargets(kind: .ladder, volume: Double(runs) * ladder.walkMinutes * 60, runs: runs, form: .walk)
        case .runWalk:
            let step = ladder.step
            return WeekTargets(
                kind: .ladder,
                volume: Double(runs) * step.sessionSeconds,
                runs: runs,
                form: .runWalk(runSeconds: step.runSeconds, walkSeconds: step.walkSeconds),
                sessionCap: Load(meters: 0, seconds: step.sessionSeconds)
            )
        case .done:
            return nil
        }
    }

    /// The week-end step: up, repeat or back (BD-2b, BD-2c, AD-18). May be called again for the same week
    /// after a late check-in, so it must not apply a step twice.
    static func weekEnded(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// A saved run on the ladder: an unplanned run or a longer non-stop segment (AD-18).
    static func runLogged(_ run: LoggedRun, state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// AD-18's easier restart, after the runner accepts it.
    static func restartEasier(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// Questions the ladder is waiting on (AD-18's easier restart).
    static func questions(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [CoachQuestion] {
        []
    }
}
