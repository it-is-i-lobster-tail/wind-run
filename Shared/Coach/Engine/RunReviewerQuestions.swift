//
//  RunReviewerQuestions.swift
//  Wind Run
//

import Foundation

/// The run review's questions after the run (AD-2, FB-3, AD-8, FB-4c, FB-4l, FB-4m, FB-4n): what is waiting now,
/// the words for the yes-or-no ones and what each answer changes.
extension RunReviewer {
    /// An offer's question waits this long for an answer.
    static let offerWindow: TimeInterval = 7 * 86_400
    /// FB-4n: the cue steps from +5% to +7.5% after 2 weeks.
    static let cadenceStep = 1.05
    static let cadenceSecondStep = 1.075
    static let cadenceStepAfter: TimeInterval = 14 * 86_400
    /// FB-4n: the baseline is the median of the last 6 easy runs (PZ-5's window).
    static let cadenceBaselineRuns = 6

    // MARK: Waiting now

    /// What run reviews wait on now: the optional morning check the day after a long run, a new longest run, a Q or
    /// a spike, and on day 2 after a spike (AD-2, AD-8), once a day; FB-3's question for a tough run of the last day;
    /// and offers from the last 7 days still unanswered and still possible. AD-1's check-in is the engine's own.
    static func questions(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [CoachQuestion] {
        var questions: [CoachQuestion] = []
        let recent = RunDataGate.usableRuns(runs)
            .filter { $0.start >= state.startDate && $0.start <= now }
            .sorted { $0.start > $1.start }

        if !state.morningChecks.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }),
           let run = recent.first(where: { run in
               switch ExtraRuns.days(from: run.start, to: now, calendar: calendar) {
               case 1: return asksMorningCheck(after: run, state: state, runs: runs, calendar: calendar)
               case 2: return spike(of: run, state: state, runs: runs) != nil
               default: return false
               }
           }) {
            questions.append(.morningCheck(runID: run.id))
        }

        let dayAgo = now.addingTimeInterval(-24 * 3_600)
        if let run = recent.first(where: { run in
            guard run.start >= dayAgo, run.checkIn?.effectiveWhatHappened == nil else { return false }
            let check = RunDataGate.check(run, runs: runs)
            return RunAnalysis.toughTrigger(run, session: matchedSession(run, in: state), check: check, state: state) != nil
        }) {
            questions.append(.whatHappened(runID: run.id))
        }

        for offer in state.runReview.offers.sorted(by: { $0.date > $1.date })
        where offer.answeredAt == nil && offer.date <= now && now.timeIntervalSince(offer.date) < offerWindow {
            if let question = offer.question, stillOpen(question, state: state) { questions.append(question) }
        }
        return unique(questions)
    }

    /// AD-2's runs: a long run, a new longest run, a Q (a hard extra run is the week's Q, AD-8) or a spike.
    static func asksMorningCheck(after run: LoggedRun, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> Bool {
        if let session = matchedSession(run, in: state) {
            if session.kind == .long || session.isNewLongest || session.isQuality { return true }
        } else if ExtraRuns.isHard(run, check: RunDataGate.check(run, runs: runs), state: state) {
            return true
        }
        if spike(of: run, state: state, runs: runs) != nil { return true }
        return Milestones.reached(by: run, runs: runs, state: state, calendar: calendar).contains { milestone, _ in
            if case .longestRun = milestone { return true }
            return false
        }
    }

    /// The spike record of the logged session holding the run (AD-8).
    static func spike(of run: LoggedRun, state: CoachState, runs: [LoggedRun]) -> SpikeRecord? {
        let ids = ExtraRuns.session(of: run, runs: runs)?.runIDs ?? [run.id]
        return state.runReview.spikes.first { ids.contains($0.runID) }
    }

    /// An offer whose answer can still change something.
    static func stillOpen(_ question: CoachQuestion, state: CoachState) -> Bool {
        switch question {
        case .extraRunSlot(let day):
            return !state.intake.runDays.contains(day) && canAddRun(state)
        case .swapRunDay(let from, let to):
            return state.intake.runDays.contains(from) && !state.intake.runDays.contains(to)
        case .walkBreaks:
            return !state.runReview.walkBreaks
        case .benchmarkSooner:
            return true
        case .cadenceCue:
            return state.runReview.cadence == nil && cadenceReport(state) != nil
        default:
            return true
        }
    }

    /// AD-8's planned slot: one more run within the runs-per-week cap, never a 6th, at most +1 run per 4 weeks (HL-9).
    static func canAddRun(_ state: CoachState) -> Bool {
        state.cycle.runsPerWeek + 1 <= min(state.assessment.runsCap, 5)
    }

    // MARK: Words

    /// The words for the run review's yes-or-no questions; nil for any other question.
    static func prompt(for question: CoachQuestion, state: CoachState, calendar: Calendar) -> RunReviewPrompt? {
        let stored = state.runReview.offers.last { $0.question == question }?.text
        switch question {
        case .extraRunSlot(let day):
            return RunReviewPrompt(
                text: stored ?? "You've been adding a run most \(day.name)s. Want me to make it a planned run? Your weekly total stays the same.",
                yes: "Add it",
                no: "Not now"
            )
        case .swapRunDay(let from, let to):
            return RunReviewPrompt(
                text: stored ?? "Want to move your \(from.name) run to \(to.name)? Your number of runs stays the same.",
                yes: "Move it",
                no: "Keep my days"
            )
        case .walkBreaks:
            return RunReviewPrompt(text: "Short walk breaks keep easy runs easy. Want to add them?", yes: "Add walk breaks", no: "No thanks")
        case .benchmarkSooner:
            return RunReviewPrompt(text: "Want to try a benchmark sooner?", detail: "I'll bring your next check run forward.", yes: "Yes", no: "Not now")
        case .cadenceCue:
            let area = cadenceReport(state)?.area?.name ?? "knee"
            return RunReviewPrompt(
                text: "Slightly shorter, quicker steps can ease the load on your \(area). Want a cue on easy runs?",
                yes: "Try it",
                no: "No thanks"
            )
        default:
            return nil
        }
    }

    // MARK: Answers

    /// The runner's answer to one of the run review's questions. Every answer closes the offers that asked it; a yes
    /// to a planned slot or a swap changes the run days from the current week on.
    static func answer(_ answer: RunReviewAnswer, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        var notes: [CoachNote] = []
        let current = max(0, state.weekIndex(on: now, calendar: calendar))
        func close(_ asked: (CoachQuestion) -> Bool) {
            for index in state.runReview.offers.indices where state.runReview.offers[index].answeredAt == nil {
                if let question = state.runReview.offers[index].question, asked(question) { state.runReview.offers[index].answeredAt = now }
            }
        }

        switch answer {
        case .extraRunSlot(let day, let accept):
            close { $0 == .extraRunSlot(day: day) }
            guard accept, !state.intake.runDays.contains(day) else { break }
            guard canAddRun(state), state.cycle.lastRunAddedWeek.map({ current - $0 >= 4 }) ?? true else {
                notes.append(CoachNote(.plan, "Your plan already has as many runs as it can take for now, so your days stay as they are."))
                break
            }
            state.intake.runDays.insert(day)
            state.cycle.runsPerWeek += 1
            state.cycle.lastRunAddedWeek = current
            state.runReview.slotChanges.append(SlotChange(week: current, runsPerWeek: state.cycle.runsPerWeek))
            notes.append(CoachNote(.plan, "Done: \(day.name) is now a planned run. Your weekly total stays the same."))
        case .swapRunDay(let from, let to, let accept):
            close { $0 == .swapRunDay(from: from, to: to) }
            guard accept, state.intake.runDays.contains(from), !state.intake.runDays.contains(to) else { break }
            state.intake.runDays.remove(from)
            state.intake.runDays.insert(to)
            notes.append(CoachNote(.plan, "Done: your \(from.name) run moves to \(to.name)."))
        case .walkBreaks(let accept):
            close { $0 == .walkBreaks }
            if accept {
                state.runReview.walkBreaks = true
                notes.append(CoachNote(.plan, "Done: your easy runs now have short walk breaks."))
            }
        case .benchmarkSooner(let accept):
            close { $0 == .benchmarkSooner }
            state.runReview.benchmarkAnsweredAt = now
            if accept {
                let request = RetestRequest(runID: nil, requestWeek: current, dueWeek: current + 1)
                if !state.runReview.retestRequests.contains(request) { state.runReview.retestRequests.append(request) }
                state.quality.retestWeek = min(state.quality.retestWeek ?? .max, request.dueWeek)
                notes.append(CoachNote(.plan, "I'll bring your next check run forward."))
            }
        case .cadenceCue(let accept):
            close { $0 == .cadenceCue }
            if accept, state.runReview.cadence == nil, let report = cadenceReport(state) {
                state.runReview.cadence = CadenceCueState(startedAt: now, reportID: report.id)
                notes.append(CoachNote(.plan, "Done: your easy runs now have a step cue. Tell me if your \(report.area?.name ?? "knee") feels worse."))
            }
        }
        return CoachUpdate(state: state, notes: notes)
    }

    // MARK: FB-4n

    /// FB-4n's cue for an easy run while it's on: about 5% more steps per minute than the runner's easy-run
    /// baseline (the median of the last 6 easy runs with step-rate data before the cue started), 7.5% after 2
    /// weeks. It stops when the knee or shin report it serves closes or is reported worse, and at once with a
    /// calf, Achilles, thigh or hamstring report. Step rate is read from the runs at each call, never stored.
    static func cadenceCue(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> String? {
        guard let cue = state.runReview.cadence,
              let report = state.injuries.first(where: { $0.id == cue.reportID }),
              !report.status.isClosed, !reportedWorse(report, since: cue.startedAt),
              !state.injuries.contains(where: { other in
                  other.reportedAt >= cue.startedAt && (other.area == .calfAchilles || other.area == .thighHamstring)
              }) else { return nil }
        let rates = RunDataGate.usableRuns(runs)
            .filter { $0.start < cue.startedAt && $0.cadence != nil && RunAnalysis.isEasyRun($0, state: state) }
            .sorted { $0.start < $1.start }
            .suffix(cadenceBaselineRuns)
            .compactMap(\.cadence)
            .sorted()
        guard !rates.isEmpty else { return nil }
        let middle = rates.count / 2
        let median = rates.count % 2 == 1 ? rates[middle] : (rates[middle - 1] + rates[middle]) / 2
        let step = now.timeIntervalSince(cue.startedAt) >= cadenceStepAfter ? cadenceSecondStep : cadenceStep
        return RunInsights.cadence(target: Int((median * step).rounded()), baseline: Int(median.rounded()))
    }

    /// The report got worse after `date`: a "Worse" check, or a move up a level (AD-13a, AD-13b, AD-13e).
    static func reportedWorse(_ report: InjuryReport, since date: Date) -> Bool {
        report.events.contains { event in
            guard event.date >= date else { return false }
            switch event.kind {
            case .mildCheck(.worse), .recoveryCheck(.worse): return true
            case .levelChanged(let from, let to, _): return to > from
            default: return false
            }
        }
    }
}
