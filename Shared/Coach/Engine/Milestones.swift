//
//  Milestones.swift
//  Wind Run
//

import Foundation

/// BD-1e: short-term wins, shown once each right after the run that reached them. Each one belongs to the first
/// run that reached it, worked out from the runs, so a second review of the same run shows it again and no other
/// run ever does. Runs count when the data gate keeps their distance and time (treadmills count, FB-2).
enum Milestones {
    /// The first distances worth a message, largest first.
    static let firsts: [RaceDistance] = [.halfMarathon, .tenK, .fiveK, .mile]
    /// GPS undercounts a little: 99% of a distance counts as reaching it.
    static let distanceTolerance = 0.99
    /// A longest run needs this much more than every earlier one, so GPS noise doesn't make a new record.
    static let longestMargin = 100.0

    /// The milestones this run reached, most notable first, with what the coach says.
    static func reached(by run: LoggedRun, runs: [LoggedRun], state: CoachState, calendar: Calendar) -> [(Milestone, CoachNote)] {
        guard counts(run, runs: runs) else { return [] }
        let earlier = runs.filter { $0.id != run.id && $0.start < run.start && counts($0, runs: runs) }
        let unit = state.intake.distanceUnit
        var found: [(Milestone, CoachNote)] = []

        // 30 min non-stop: the end of the run-walk ladder (also RPE 5 or less and no open report, TI-6).
        let couldRun30 = state.intake.runs30Minutes == true
        if !couldRun30, let seconds = nonStopSeconds(run), seconds >= 30 * 60,
           !earlier.contains(where: { (nonStopSeconds($0) ?? 0) >= 30 * 60 && ($0.rpe ?? 99) <= 5 }),
           let rpe = run.rpe, rpe <= 5, state.openInjuries.isEmpty {
            let text = state.ladder == nil ? "30 minutes without stopping." : "30 minutes without stopping. You've finished the run-walk ladder."
            found.append((.nonStopMinutes(30), CoachNote(.milestone, text)))
        }

        // The first mile, 5K, 10K and half without stopping; only the largest new one shows.
        if let meters = nonStopMeters(run) {
            let reportedLongest = state.assessment.start.reportedLongest?.meters ?? 0
            let finishedGoal = state.intake.finished == .yesRecently || state.intake.finished == .yesLongerAgo
            for distance in firsts where meters >= distance.meters * distanceTolerance {
                if reportedLongest >= distance.meters * distanceTolerance { break }
                if finishedGoal, distance <= state.goal.distance { break }
                if distance == .mile, couldRun30 { break }
                if earlier.contains(where: { (nonStopMeters($0) ?? 0) >= distance.meters * distanceTolerance }) { break }
                found.append((.firstDistance(distance), CoachNote(.milestone, "\(CoachFormat.distance(distance.meters, unit: unit)) without stopping. That's a first.")))
                break
            }
        }

        // 10 and 20 min non-stop, on the way to 30; only the larger new one shows.
        if !couldRun30, let seconds = nonStopSeconds(run) {
            for minutes in [20, 10] where seconds >= Double(minutes) * 60 && seconds < 30 * 60 {
                if earlier.contains(where: { (nonStopSeconds($0) ?? 0) >= Double(minutes) * 60 }) { break }
                var text = "\(minutes) minutes without stopping."
                if let first = dayOneSeconds(state) { text += " On day one it was \(duration(first))." }
                found.append((.nonStopMinutes(minutes), CoachNote(.milestone, text)))
                break
            }
        }

        // Longest run yet: beyond every logged run and the intake's longest.
        let meters = sessionMeters(run, runs: runs)
        let previous = earlier.map { sessionMeters($0, runs: runs) }.max()
        let reported = state.assessment.start.reportedLongest?.meters
        if meters > 0, previous != nil || reported != nil,
           meters > max(previous ?? 0, reported ?? 0) + longestMargin {
            found.append((.longestRun(meters: meters), CoachNote(.milestone, "Longest run yet: \(CoachFormat.distance(meters, unit: unit)).")))
        }
        return found
    }

    /// Runs that count: not dropped by the data gate, not entered by hand, no GPS or bad-data flag.
    static func counts(_ run: LoggedRun, runs: [LoggedRun]) -> Bool {
        let check = RunDataGate.check(run, runs: runs)
        return check.gate != .dropped && !check.dataProblem && !check.reasons.contains(.manual)
    }

    /// The longest stretch run without walking or stopping: the track's, else the whole run when nothing was walked.
    static func nonStopSeconds(_ run: LoggedRun) -> Double? {
        if let seconds = run.track?.longestNonStopSeconds { return seconds }
        return RunDataGate.isRunWalk(run) ? nil : run.movingSeconds
    }

    static func nonStopMeters(_ run: LoggedRun) -> Double? {
        if let meters = run.track?.longestNonStopMeters { return meters }
        return RunDataGate.isRunWalk(run) || run.meters <= 0 ? nil : run.meters
    }

    /// The run's distance with any part less than 15 minutes away (Terms).
    static func sessionMeters(_ run: LoggedRun, runs: [LoggedRun]) -> Double {
        LoadMetrics.sessions(from: RunDataGate.usableRuns(runs)).first { $0.runIDs.contains(run.id) }?.meters ?? run.meters
    }

    /// The non-stop running on day one: the ladder's first step, else the intake's longest non-stop band.
    static func dayOneSeconds(_ state: CoachState) -> Double? {
        if let ladder = state.ladder, ladder.form != .walkStage {
            return RunWalkStep.sequence[ladder.firstStepIndex.clamped(to: 0 ... RunWalkStep.lastIndex)].runSeconds
        }
        guard let band = state.intake.longestNonStop, band.lowMinutes > 0 else { return nil }
        return band.lowMinutes * 60
    }

    /// "1 minute", "4.5 minutes", "30 seconds".
    static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded())) seconds" }
        let minutes = seconds / 60
        if minutes == 1 { return "1 minute" }
        if minutes == minutes.rounded() { return "\(Int(minutes)) minutes" }
        return String(format: "%.1f minutes", minutes)
    }
}
