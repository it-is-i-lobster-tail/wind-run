//
//  RunReviewer.swift
//  Wind Run
//

import Foundation

/// What the coach makes of each saved run: the match to the plan, the data gate, extra runs and spikes, the Q's
/// outcome and the pace changes it makes, insights and milestones, and the questions after it (AD-1, AD-2, AD-8,
/// FB-1 to FB-7, PZ-7, PZ-8, BD-1e). Reviewing the same run again (after its check-in, or after a re-plan) updates
/// what the first review did and never applies a change twice. Heart rate is read from the run at each call and only
/// ever becomes notes on the review, never part of the plan's state (PZ-13).
enum RunReviewer {
    /// A run's duration may differ from the planned run's by this much and still match it (AD-8).
    static let matchTolerance = 0.25
    /// FB-4k: decoupling of 5% or more gets its note.
    static let decouplingLine = 0.05
    /// FB-4l, FB-4m: "Want to try a benchmark sooner?" waits 4 weeks after an answer.
    static let benchmarkGap: TimeInterval = 28 * 86_400
    static let benchmarkQuestion = " Want to try a benchmark sooner?"
    /// FB-4g: outcomes kept per Q type in `quality.outcomes`.
    static let outcomeHistory = 6

    // MARK: Reviewing a run

    /// Reviews a saved run; `runs` holds every run, this one included. Calling it again for the same run (after its
    /// check-in) updates the review: matches, judgements and pace changes are kept with the run.
    static func review(_ run: LoggedRun, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> (CoachState, RunReview) {
        var state = state
        let runs = runs.contains { $0.id == run.id } ? runs : runs + [run]
        if !state.runReview.reviewedRunIDs.contains(run.id) { state.runReview.reviewedRunIDs.append(run.id) }

        // FB-2: a duplicate, or a run under 500 m or over 100 km, never counts or matches.
        let check = RunDataGate.check(run, runs: runs)
        guard check.gate != .dropped else {
            state = forget([run.id], state: state, now: now, calendar: calendar)
            return (state, RunReview(runID: run.id, match: .extra, gate: .dropped))
        }

        // AD-8: the planned run it completes, or extra. A run found extra while its week was planned stays extra.
        let match = self.match(run, state: state, calendar: calendar)
        switch match {
        case .planned(let sessionID):
            state = markDone(sessionID: sessionID, runID: run.id, state: state)
            state.runReview.extraRunIDs.removeAll { $0 == run.id }
        case .extra:
            if ExtraRuns.weekPosition(of: run.start, in: state, calendar: calendar) != nil, !state.runReview.extraRunIDs.contains(run.id) {
                state.runReview.extraRunIDs.append(run.id)
            }
        }
        let located = locate(run, in: state, calendar: calendar)
        let session = located?.session
        var notes: [CoachNote] = []
        if let located, run.plannedSessionID == nil {
            let offset = ExtraRuns.days(from: located.day, to: run.start, calendar: calendar)
            if abs(offset) == 1 {
                notes.append(CoachNote(.plan, "Looks like you ran \(Weekday(of: located.day, calendar: calendar).name)'s run a day \(offset < 0 ? "early" : "late")."))
            }
        }

        // AD-8: extra runs and spikes change the plan; their sentences stay with the run.
        keep(ExtraRuns.apply(run, extra: match == .extra, state: &state, runs: runs, now: now, calendar: calendar), in: &state)
        if let text = state.runReview.offer(.funRun, runID: run.id)?.text { notes.append(CoachNote(.plan, text)) }
        notes += planNotes(for: run, state: state)

        // FB-3: a tough run asks what happened before any coaching text, and shows the safety line.
        let analysis = RunAnalysis.analyse(run, session: session, check: check, state: state, calendar: calendar)
        let answer = run.checkIn?.effectiveWhatHappened
        var questions: [CoachQuestion] = []
        if analysis.tough != nil, answer == nil { questions.append(.whatHappened(runID: run.id)) }
        if run.checkIn?.answeredAt == nil { questions.append(.runCheckIn(runID: run.id)) }
        // Heat, hurt and ill answers get no coaching text: their own rule speaks (FB-3, FB-7). An unanswered check is
        // no data, so no pace advice yet (AD-17).
        let routed = answer == .unwellInHeat || answer == .somethingHurt || answer == .feltIll
        let coaching = !routed && !(analysis.tough != nil && answer == nil)

        // FB-4g and PZ-7: the Q's outcome, kept with the run, and the pace changes it makes.
        var judgement: SessionJudgement?
        if let located {
            judgement = SessionJudge.judge(run, session: located.session, week: located.week, analysis: analysis, state: state)
        }
        record(judgement, runID: run.id, state: &state)
        var changeNotes: [CoachNote] = []
        if let judgement, let session {
            if let note = PaceUpdates.cut(judgement, session: session, state: &state) { changeNotes.append(note) }
            if let note = PaceUpdates.raise(judgement, state: &state) { changeNotes.append(note) }
            let flagged = flaggedReps(judgement, state: state, runs: runs, calendar: calendar)
            if let note = PaceUpdates.repDrift(judgement, flagged: flagged, state: &state) { changeNotes.append(note) }
            syncQuality(&state)
        }

        // PZ-8: the third comfortable easy run checks the pace the runner gave.
        let reviewed = state
        if let note = PaceUpdates.checkReportedPace(run, comfortable: comfortableRuns(upTo: run, state: reviewed, runs: runs, calendar: calendar), state: &state) {
            changeNotes.append(note)
        }

        let heartRate = coachingHeartRate(run, runs: runs)
        var positives: [CoachNote] = []
        var candidates: [Insight] = []

        // FB-4c: easy runs too fast.
        if coaching {
            let easy = PaceUpdates.easyTooFast(run, recent: easyFacts(upTo: run, state: state, runs: runs, calendar: calendar), state: &state)
            if let note = easy.note {
                candidates.append(Insight(.consistency, note.text, size: easy.size))
                changeNotes.append(note)
            } else if let tip = easy.tip {
                candidates.append(Insight(.consistency, tip, size: easy.size))
            }
            if let question = easy.question { questions.append(question) }
        }

        // FB-4a to FB-4i, FB-5 and the heart-rate notes.
        if coaching {
            let pacing = self.pacing(run, session: session, analysis: analysis, judgement: judgement, state: &state, runs: runs, calendar: calendar)
            candidates += pacing.candidates
            changeNotes += pacing.notes
            if let judgement, judgement.outcome == .struggled || judgement.outcome == .failed, !pacing.carriesOutcome,
               let text = RunInsights.hardOutcome(judgement.outcome) {
                candidates.append(Insight(.consistency, text))
            }
            if heartRate, let drift = HeartRateRules.decoupling(run, state: state), drift >= decouplingLine {
                candidates.append(Insight(.pacing, RunInsights.decoupling, size: drift))
            }
            if let session, run.heartRate?.useForCoaching == true, HeartRateRules.fallback(at: run, runs: runs).coaching,
               !HeartRateRules.settlingAfterBreak(run, runs: runs) {
                switch HeartRateRules.workSignal(run, session: session, runs: runs, state: state, calendar: calendar) {
                case .overBand?: candidates.append(Insight(.pacing, RunInsights.overThresholdBand))
                case .belowBand?: candidates.append(Insight(.pacing, RunInsights.belowThresholdBand))
                case .underNinetyPercent?: candidates.append(Insight(.pacing, RunInsights.underNinetyPercent))
                case .confirmsDose?, nil: break
                }
            }
            if RunAnalysis.isEasyRun(run, state: state), let cue = cadenceCue(state: state, runs: runs, now: run.end, calendar: calendar) {
                candidates.append(Insight(.technique, cue))
            }
        }

        // FB-1's slot 1, in order: a milestone, a session done well, an even half, a faster trend or a lower heart
        // rate at the same pace, the planned run done, else a plain fact.
        let reached = Milestones.reached(by: run, runs: runs, state: state, calendar: calendar)
        positives += reached.map(\.1)
        var benchmarkText: String?
        if coaching {
            if let outcome = judgement?.outcome, let text = RunInsights.positiveOutcome(outcome) { positives.append(CoachNote(.insight, text)) }
            if check.allowsPaceAnalysis, analysis.cause == nil, let text = RunInsights.positiveFade(analysis.fade?.row) {
                positives.append(CoachNote(.insight, text))
            }
            if let gain = Benchmarks.fasterTrend(run, runs: runs, state: state) {
                benchmarkText = RunInsights.fasterTrend(gain)
            } else if heartRate, HeartRateRules.paceAtHeartRate(after: run, runs: RunDataGate.usableRuns(runs), state: state, calendar: calendar).lower {
                benchmarkText = RunInsights.lowerHeartRate
            }
        }
        let asksBenchmark = state.runReview.benchmarkAnsweredAt.map { run.start.timeIntervalSince($0) >= benchmarkGap } ?? true
        if let text = benchmarkText {
            positives.append(CoachNote(.insight, asksBenchmark ? text : String(text.dropLast(benchmarkQuestion.count))))
        }
        if let session, finished(run, session: session), let text = RunInsights.plannedDone(session) { positives.append(CoachNote(.insight, text)) }
        let plainFact = CoachNote(.insight, RunInsights.plainFact(run, number: number(of: run, state: state, runs: runs, calendar: calendar), unit: state.intake.distanceUnit))
        let insights = routed ? [] : RunInsights.choose(positives: positives, plainFact: plainFact, candidates: coaching ? candidates : [])
        if asksBenchmark, let text = benchmarkText, insights.first?.text == text {
            ask(.benchmarkSooner, kind: .benchmarkSooner, run: run, state: &state)
            questions.append(.benchmarkSooner)
        }

        // AD-8's habit offer and FB-4n's cadence cue offer, once each.
        if match == .extra {
            if let offer = state.runReview.offers.first(where: { $0.runID == run.id && ($0.kind == .extraRunSlot || $0.kind == .swapRunDay) }) {
                if offer.answeredAt == nil, let question = offer.question { questions.append(question) }
            } else if let offer = ExtraRuns.habitOffer(run, state: state, runs: runs, calendar: calendar) {
                state.runReview.offers.append(offer)
                if let question = offer.question { questions.append(question) }
            }
        }
        if let question = cadenceOffer(run, state: &state) { questions.append(question) }

        // PZ-13: the heart-rate badge, and when the coach stops or pauses using heart rate.
        var badge = run.heartRate.map { HeartRateRules.badge($0) }
        if badge == .usedForCoaching, !heartRate { badge = .shownOnly }
        if let rate = run.heartRate, rate.useForCoaching, rate.source != .earbuds {
            if HeartRateRules.fallback(at: run, runs: runs).justSwitched { changeNotes.append(CoachNote(.pace, RunInsights.heartRatePatchy)) }
            if HeartRateRules.restart(RunDataGate.usableRuns(runs).filter { $0.start <= run.start }) == run.start {
                changeNotes.append(CoachNote(.pace, RunInsights.heartRateSettling))
            }
        }

        notes += routed ? changeNotes.filter { $0.topic != .pace || $0.text == RunInsights.heartRatePatchy } : changeNotes
        let shown = Set(insights.map(\.text))
        notes = unique(notes.filter { !shown.contains($0.text) })
        let review = RunReview(
            runID: run.id,
            match: match,
            gate: check.gate,
            insights: insights,
            milestones: reached.map(\.0),
            outcome: judgement?.outcome,
            questions: unique(questions),
            notes: notes,
            showsSafetyLine: analysis.tough != nil,
            heartRate: badge
        )
        return (state, review)
    }

    // MARK: Pacing (FB-4a to FB-4i, FB-5)

    /// The pacing insights for one run, the advice they leave for the next sessions and the "because" sentences of
    /// repeated patterns. `carriesOutcome`: a Struggled or Failed outcome that came from a fade or a fast start is
    /// said through the pacing message, in place of the outcome's own line (FB-1, FB-6).
    static func pacing(
        _ run: LoggedRun,
        session: PlannedSession?,
        analysis: RunAnalysisResult,
        judgement: SessionJudgement?,
        state: inout CoachState,
        runs: [LoggedRun],
        calendar: Calendar
    ) -> (candidates: [Insight], notes: [CoachNote], carriesOutcome: Bool) {
        var candidates: [Insight] = []
        var notes: [CoachNote] = []
        var carriesOutcome = false
        let outcome = judgement.map(\.outcome).flatMap { $0 == .struggled || $0 == .failed ? $0 : nil }
        let fromFade = outcome != nil && judgement?.faded == true
        let buildDistance = state.goal.flavor == .buildDistance
        let unit = state.intake.distanceUnit
        let group = self.group(of: run, state: state)

        // FB-5: data, hills, heat and fuel explain a fade before any advice; unknown heat allows only the neutral note.
        if let cause = analysis.cause, let insight = RunInsights.causeInsight(cause) { candidates.append(insight) }

        // FB-4a and FB-4b.
        if let fade = analysis.fade {
            switch (fade.row, analysis.cause) {
            case (.marked?, .pacing?):
                let next = nextName(session?.kind)
                let easy = group == .easy
                let longEndurance = session?.kind == .long && run.movingSeconds >= RunAnalysis.fuelSeconds
                if fade.fastStart != nil {
                    candidates.append(Insight(.pacing, RunInsights.fastStartFade(
                        change: fade.change,
                        firstKilometre: fade.firstKilometre,
                        segment: fade.segment,
                        next: next,
                        outcome: outcome,
                        buildDistance: buildDistance,
                        ceiling: state.paces.easy?.fast,
                        unit: unit
                    ), size: fade.change))
                    carriesOutcome = fromFade
                    // The even-pace band, an in-run cue: the next paced run, or in Build Distance a ceiling on the
                    // next easy or long run.
                    if buildDistance {
                        advise(.evenBand, run: run, kinds: [.easy, .long], band: state.paces.easy, state: &state)
                    } else {
                        let target = RunAnalysis.targetPace(session, state: state)
                        advise(.evenBand, run: run, kinds: [.racePace, .threshold, .race], band: target.map { evenBand(for: $0) }, state: &state)
                    }
                } else if !easy, !longEndurance {
                    candidates.append(Insight(.pacing, RunInsights.plainFade(change: fade.change, next: next, outcome: outcome), size: fade.change))
                    carriesOutcome = fromFade
                }
                // 2 of the last 3 comparable runs: the plan changes.
                if let group, comparable(upTo: run, group: group, state: state, runs: runs, calendar: calendar)
                    .filter({ $0.fade?.row == .marked && $0.cause == .pacing }).count >= 2 {
                    let split = !buildDistance
                    let longRunStart = fade.fastStart != nil
                    let holdLongRun = fade.fastStart == nil && buildDistance
                    if split { advise(.splitIntoReps, run: run, kinds: [.threshold, .racePace], state: &state) }
                    if longRunStart { advise(.capLongRunStart, run: run, kinds: [.long], band: state.paces.easy, state: &state) }
                    if holdLongRun { advise(.holdLongRunStep, run: run, kinds: [.long], state: &state) }
                    if let text = RunInsights.repeatedFade(
                        runs: pluralName(group),
                        split: split,
                        sameKind: group == .racePace || group == .threshold,
                        longRunStart: longRunStart,
                        holdLongRun: holdLongRun,
                        longRunDay: state.intake.longRunDay
                    ) {
                        notes.append(CoachNote(.plan, text))
                    }
                }
            case (.marked?, .heatUnknown?), (.mild?, _):
                candidates.append(Insight(.pacing, RunInsights.neutralFade(fade.change), size: fade.change))
            default:
                break
            }
        }
        if let fast = analysis.fastStartWithTarget { candidates.append(Insight(.pacing, RunInsights.fastStart(fast), size: fast)) }

        // FB-4d and FB-4e. A fading last rep's outcome keeps its own line.
        if let flags = analysis.reps, let insight = RunInsights.reps(flags) { candidates.append(insight) }
        if analysis.fastRecoveries { candidates.append(Insight(.pacing, RunInsights.recoveries)) }

        // FB-4f: once a tip; in 2 of the last 3 tempo runs, the next tempo becomes reps, or 3% easier as reps.
        if let drop = analysis.tempoFade, analysis.cause == .pacing {
            candidates.append(Insight(.pacing, RunInsights.tempoFade(outcome: outcome), size: drop))
            carriesOutcome = carriesOutcome || fromFade
            if comparable(upTo: run, group: .threshold, state: state, runs: runs, calendar: calendar)
                .filter({ $0.tempoFade != nil && $0.cause == .pacing }).count >= 2 {
                advise(.tempoAsReps, run: run, kinds: [.threshold], state: &state)
                notes.append(CoachNote(.plan, RunInsights.repeatedTempoFade(alreadyReps: nextTempoIsReps(after: run, state: state, calendar: calendar))))
            }
        }
        // FB-4g: a Struggled session that faded repeats with the even-pace band.
        if outcome == .struggled, judgement?.faded == true, let session {
            advise(.evenBand, run: run, kinds: [session.kind], band: session.paceBand.map { evenBand(for: $0.middle) }, state: &state)
        }

        // FB-4h with FB-5's fuel line, and FB-4i.
        if let drop = analysis.durabilityDrop {
            candidates.append(Insight(.pacing, RunInsights.durability(drop, unfuelled: analysis.unfuelled), size: drop))
            if analysis.unfuelled { candidates.removeAll { $0.text == RunInsights.fuelText } }
        }
        if let wall = analysis.wall { candidates.append(Insight(.pacing, RunInsights.wall(wall, unit: unit), size: wall)) }
        return (candidates, notes, carriesOutcome)
    }

    /// FB-4a's even-pace band: target ±5%.
    static func evenBand(for target: Double) -> PaceBand {
        PaceBand(fast: target * (1 - RunDataGate.noise), slow: target * (1 + RunDataGate.noise))
    }

    /// Adds or updates a run's pacing advice; a second band for the same run adds its session kinds.
    static func advise(_ kind: PacingAdviceKind, run: LoggedRun, kinds: [SessionKind], band: PaceBand? = nil, state: inout CoachState) {
        if let index = state.runReview.advice.firstIndex(where: { $0.kind == kind && $0.runID == run.id }) {
            var advice = state.runReview.advice[index]
            for kind in kinds where !advice.sessionKinds.contains(kind) { advice.sessionKinds.append(kind) }
            advice.band = advice.band ?? band
            state.runReview.advice[index] = advice
        } else {
            state.runReview.advice.append(PacingAdvice(kind: kind, runID: run.id, date: run.start, sessionKinds: kinds, band: band))
        }
    }

    /// "your next race-pace run": the next paced run the advice is for.
    static func nextName(_ kind: SessionKind?) -> String {
        switch kind {
        case .racePace?: "race-pace run"
        case .threshold?: "tempo run"
        default: "paced run"
        }
    }

    static func pluralName(_ kind: SessionKind) -> String {
        switch kind {
        case .racePace: "race-pace runs"
        case .threshold: "tempo runs"
        case .race: "races"
        case .long: "long runs"
        case .easy: "easy runs"
        default: "runs"
        }
    }

    /// The kind a run is compared with for FB-1's patterns: its planned session's kind (a Q made easy is an easy
    /// run), or an easy run for an extra run rated easy.
    static func group(of run: LoggedRun, state: CoachState) -> SessionKind? {
        if let session = matchedSession(run, in: state) {
            if session.madeEasy != nil { return .easy }
            return [.easy, .long, .racePace, .threshold, .race].contains(session.kind) ? session.kind : nil
        }
        return RunAnalysis.isEasyRun(run, state: state) ? .easy : nil
    }

    /// FB-1's comparable runs: the last 3 of the same kind up to this one whose pace was analysed on a known cool,
    /// flat day, newest last.
    static func comparable(upTo run: LoggedRun, group: SessionKind, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> [RunAnalysisResult] {
        var results: [RunAnalysisResult] = []
        let candidates = RunDataGate.usableRuns(runs)
            .filter { $0.start <= run.start && self.group(of: $0, state: state) == group }
            .sorted { $0.start > $1.start }
        for other in candidates {
            guard RunAnalysis.heatTier(other, state: state) == 0 else { continue }
            let result = analysis(of: other, check: RunDataGate.check(other, duplicate: false), state: state, calendar: calendar)
            guard result.check.allowsPaceAnalysis else { continue }
            results.insert(result, at: 0)
            if results.count == 3 { break }
        }
        return results
    }

    static func analysis(of run: LoggedRun, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> RunAnalysisResult {
        analysis(of: run, check: RunDataGate.check(run, runs: runs), state: state, calendar: calendar)
    }

    static func analysis(of run: LoggedRun, check: DataCheck, state: CoachState, calendar: Calendar) -> RunAnalysisResult {
        RunAnalysis.analyse(run, session: matchedSession(run, in: state), check: check, state: state, calendar: calendar)
    }

    /// FB-4f repeated: whether the next tempo already planned is reps.
    static func nextTempoIsReps(after run: LoggedRun, state: CoachState, calendar: Calendar) -> Bool {
        for record in state.weeks {
            for session in record.plan.sessions where session.kind == .threshold && session.isQuality && session.status.isPlanned {
                guard state.date(of: session, in: record.plan, calendar: calendar) > run.start, let dose = session.dose else { continue }
                return !dose.continuous && dose.reps > 1
            }
        }
        return false
    }

    /// FB-4d: the runs among the type's last 3 sessions whose reps were flagged.
    static func flaggedReps(_ judgement: SessionJudgement, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> [UUID] {
        state.runReview.judgements
            .filter { $0.type == judgement.type && $0.date <= judgement.date }
            .sorted { $0.date < $1.date }
            .suffix(3)
            .compactMap { other in
                guard !other.conditions, let run = runs.first(where: { $0.id == other.runID }) else { return nil }
                return analysis(of: run, state: state, runs: runs, calendar: calendar).reps?.any == true ? run.id : nil
            }
    }

    // MARK: Easy runs (FB-4c, PZ-8)

    /// FB-4c: the last 3 easy runs up to this one that can be compared (data gate passed, not a treadmill, hot, hilly
    /// or high run), oldest first. After leg work RPE 5, not 4, is the effort sign.
    static func easyFacts(upTo run: LoggedRun, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> [EasyRunFact] {
        guard let band = state.paces.easy else { return [] }
        var recent: [LoggedRun] = []
        for other in RunDataGate.usableRuns(runs).filter({ $0.start <= run.start }).sorted(by: { $0.start < $1.start }).reversed() {
            guard other.pace != nil, RunAnalysis.isEasyRun(other, state: state), !hotOrHilly(other, state: state) else { continue }
            let check = RunDataGate.check(other, duplicate: false)
            guard check.allowsPaceAnalysis, !check.treadmill else { continue }
            recent.insert(other, at: 0)
            if recent.count == 3 { break }
        }
        return recent.map { other in
            let faster = (band.fast - (other.pace ?? band.fast)) / band.fast
            let afterLegWork = WeeklyReviewer.afterLegWork(other, state: state, calendar: calendar)
            let effort = (other.rpe ?? 0) >= (afterLegWork ? 5 : 4) || other.checkIn?.talkTest == false
            var heartRate = false
            if coachingHeartRate(other, runs: runs), let mean = HeartRateRules.decisionGradeMean(other) {
                heartRate = mean > HeartRateRules.zones(before: other, runs: runs, state: state, calendar: calendar).easyCeiling
            }
            return EasyRunFact(
                runID: other.id,
                date: other.start,
                fast: faster > PaceUpdates.easyFastLine ? faster : nil,
                effortEvidence: effort,
                heartRateEvidence: heartRate
            )
        }
    }

    /// PZ-8's first 3 comfortable easy runs from the plan's start up to this one, oldest first: only the third one
    /// checks the pace.
    static func comfortableRuns(upTo run: LoggedRun, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> [LoggedRun] {
        var comfortable: [LoggedRun] = []
        for other in RunDataGate.usableRuns(runs).filter({ $0.start >= state.startDate && $0.start <= run.start }).sorted(by: { $0.start < $1.start }) {
            guard other.pace != nil, (other.rpe ?? 99) <= 3, RunAnalysis.isEasyRun(other, state: state), !RunDataGate.isRunWalk(other),
                  !RunAnalysis.isConditionsRun(other, state: state, calendar: calendar) else { continue }
            let check = RunDataGate.check(other, duplicate: false)
            guard check.allowsPaceAnalysis, !check.treadmill else { continue }
            comfortable.append(other)
            if comfortable.count == 3 { break }
        }
        return comfortable
    }

    /// Hot (T1+), hilly, at altitude or a hill session: never compared for pace (FB-5, PZ-7).
    static func hotOrHilly(_ run: LoggedRun, state: CoachState) -> Bool {
        (RunAnalysis.heatTier(run, state: state) ?? 0) >= 1 || RunDataGate.isHilly(run)
            || (run.track?.startAltitude ?? 0) >= 800 || matchedSession(run, in: state)?.kind == .hills
    }

    // MARK: Heart rate

    /// Heart rate the coach may use on this run: decision-grade (PZ-10), with no PZ-13 fallback and not settling
    /// after a break.
    static func coachingHeartRate(_ run: LoggedRun, runs: [LoggedRun]) -> Bool {
        guard let heartRate = run.heartRate, HeartRateRules.badge(heartRate) == .usedForCoaching else { return false }
        return HeartRateRules.fallback(at: run, runs: runs).coaching && !HeartRateRules.settlingAfterBreak(run, runs: runs)
    }

    // MARK: Session outcomes (FB-4g)

    /// Keeps a run's judgement, mirrors it into `quality`, and asks for FB-4g's retest after a Failed session. A run
    /// judged by conditions only, or no longer a Q, takes back its pace changes and retest (PZ-7).
    static func record(_ judgement: SessionJudgement?, runID: UUID, state: inout CoachState) {
        state.runReview.judgements.removeAll { $0.runID == runID }
        if let judgement {
            state.runReview.judgements.append(judgement)
            state.runReview.judgements.sort { $0.date < $1.date }
        }
        if judgement?.conditions ?? true {
            revertQualityEffects(of: runID, state: &state)
            state.runReview.advice.removeAll { $0.runID == runID && $0.kind == .lengthenRecoveries }
        }
        if let judgement, judgement.outcome == .failed, !judgement.conditions {
            let request = RetestRequest(runID: runID, requestWeek: judgement.weekIndex, dueWeek: judgement.weekIndex + 2)
            if !state.runReview.retestRequests.contains(request) {
                dropRetests({ $0.runID == runID }, state: &state)
                state.runReview.retestRequests.append(request)
                state.quality.retestWeek = min(state.quality.retestWeek ?? .max, request.dueWeek)
            }
        } else {
            dropRetests({ $0.runID == runID }, state: &state)
        }
        syncQuality(&state)
    }

    /// Removes retest requests; a `quality.retestWeek` that only they asked for goes back to nil.
    static func dropRetests(_ remove: (RetestRequest) -> Bool, state: inout CoachState) {
        let removed = state.runReview.retestRequests.filter(remove)
        guard !removed.isEmpty else { return }
        state.runReview.retestRequests.removeAll(where: remove)
        for request in removed where state.quality.retestWeek == request.dueWeek
            && !state.runReview.retestRequests.contains(where: { $0.dueWeek == request.dueWeek }) {
            state.quality.retestWeek = nil
        }
    }

    /// `quality.outcomes` and `quality.evenStreak` mirror the judgements, which a plan baseline never holds.
    static func syncQuality(_ state: inout CoachState) {
        let judgements = state.runReview.judgements.sorted { $0.date < $1.date }
        var outcomes: [QualityOutcomeRecord] = []
        for type in QualityType.allCases {
            outcomes += judgements
                .filter { $0.type == type }
                .suffix(outcomeHistory)
                .map { QualityOutcomeRecord(date: $0.date, type: $0.type, outcome: $0.outcome, runID: $0.runID) }
        }
        state.quality.outcomes = outcomes.sorted { $0.date < $1.date }
        let used = Set(state.runReview.effects.filter { $0.kind == .qualityRaise }.flatMap(\.runIDs))
        var streak = 0
        for judgement in judgements.reversed() {
            guard judgement.outcome == .evenAndOnTarget, !used.contains(judgement.runID) else { break }
            streak += 1
        }
        state.quality.evenStreak = streak
    }

    /// Takes back a run's quality pace changes.
    static func revertQualityEffects(of runID: UUID, state: inout CoachState) {
        let kinds: [RunEffectKind] = [.qualityCut, .repsCut, .qualityRaise]
        let reverted = state.runReview.effects.filter { $0.runID == runID && kinds.contains($0.kind) }
        guard !reverted.isEmpty else { return }
        for effect in reverted { invert(effect.kind, changed: effect.changed, paces: &state.paces) }
        state.runReview.effects.removeAll { $0.runID == runID && kinds.contains($0.kind) }
        if reverted.contains(where: { $0.kind == .qualityRaise }) { resetLastRaise(&state) }
    }

    /// The opposite of `PaceUpdates.change`. PZ-8's band stays: the logged pace is still the runner's.
    static func invert(_ kind: RunEffectKind, changed: Bool, paces: inout TrainingPaces) {
        guard changed else { return }
        switch kind {
        case .qualityCut, .repsCut: paces.qualityFactor /= PaceUpdates.cutFactor
        case .qualityRaise: paces.qualityFactor /= PaceUpdates.raiseFactor
        case .easySlowed: paces.easy = paces.easy?.shifted(by: -PaceUpdates.easyShift)
        case .easyChecked: break
        }
    }

    static func resetLastRaise(_ state: inout CoachState) {
        state.paces.lastRaise = state.runReview.effects.filter { $0.kind == .qualityRaise && $0.changed }.map(\.date).max()
    }

    // MARK: Review helpers

    /// The planned run done in full: no cut-short mark, and for a Q all its work.
    static func finished(_ run: LoggedRun, session: PlannedSession) -> Bool {
        guard run.checkIn?.cutShort == nil else { return false }
        guard session.isQuality, let dose = session.dose else { return true }
        let work = RunAnalysis.workSteps(run)
        if work.contains(where: \.cut) { return false }
        if !dose.continuous, dose.reps > 1, !work.isEmpty, work.count < dose.reps { return false }
        return SessionJudge.completion(run, session: session, dose: dose, work: work) >= 0.95
    }

    /// Which run of its plan week this is, counting runs less than 15 minutes apart as one.
    static func number(of run: LoggedRun, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> Int {
        let start = state.weekStart(max(0, state.weekIndex(on: run.start, calendar: calendar)), calendar: calendar)
        let sessions = LoadMetrics.sessions(from: RunDataGate.usableRuns(runs))
        guard let own = sessions.first(where: { $0.runIDs.contains(run.id) }) else { return 1 }
        return max(1, sessions.filter { $0.start >= start && $0.start <= own.start }.count)
    }

    /// AD-8's sentences for the run in step order, each after the run's greeting when it has one.
    static func planNotes(for run: LoggedRun, state: CoachState) -> [CoachNote] {
        let order: [RunChangeKind] = [.quality, .longRun, .rest, .total]
        return order.compactMap { kind in
            guard let record = state.runReview.runNotes.first(where: { $0.runID == run.id && $0.kind == kind }) else { return nil }
            return record.greets ? CoachNote(record.note.topic, ExtraRuns.greeting(run) + " " + record.note.text) : record.note
        }
    }

    /// Keeps the sentences a run's plan changes produced now, one per kind; a kind with no new sentence keeps its last.
    static func keep(_ records: [RunNoteRecord], in state: inout CoachState) {
        for record in records {
            state.runReview.runNotes.removeAll { $0.runID == record.runID && $0.kind == record.kind }
            state.runReview.runNotes.append(record)
        }
    }

    /// Records an offer's question with its run, once.
    static func ask(_ question: CoachQuestion, kind: RunOfferKind, run: LoggedRun, state: inout CoachState) {
        guard state.runReview.offer(kind, runID: run.id) == nil else { return }
        state.runReview.offers.append(RunOffer(kind: kind, runID: run.id, date: run.start, question: question))
    }

    /// FB-4n: the cadence cue is offered once, after an easy run with step-rate data, while a Mild or Intense knee or
    /// shin report is open and no thigh or hamstring report is.
    static func cadenceOffer(_ run: LoggedRun, state: inout CoachState) -> CoachQuestion? {
        if let offer = state.runReview.offer(.cadenceCue, runID: run.id) { return offer.answeredAt == nil ? offer.question : nil }
        guard state.runReview.cadence == nil, !state.runReview.offers.contains(where: { $0.kind == .cadenceCue }),
              run.cadence != nil, RunAnalysis.isEasyRun(run, state: state), cadenceReport(state) != nil else { return nil }
        ask(.cadenceCue, kind: .cadenceCue, run: run, state: &state)
        return .cadenceCue
    }

    /// The open Mild or Intense knee or shin report the cadence cue serves, when no thigh or hamstring report is open.
    static func cadenceReport(_ state: CoachState) -> InjuryReport? {
        let open = state.openInjuries
        guard !open.contains(where: { $0.area == .thighHamstring }) else { return nil }
        return open.last { $0.level <= .intense && $0.area?.offersCadenceCue == true }
    }

    static func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }

    // MARK: Matching (AD-8)

    /// The planned session a run completes, or extra. A run started from a planned session matches it.
    /// Otherwise: the same day or one day either side, with a duration within ±25%; the nearer date wins,
    /// then the closer duration. A planned run can be matched once, and a run found extra stays extra.
    static func match(_ run: LoggedRun, state: CoachState, calendar: Calendar) -> RunMatch {
        // Already matched.
        for record in state.weeks {
            if let session = record.plan.sessions.first(where: { $0.status == .done(runID: run.id) }) {
                return .planned(sessionID: session.id)
            }
        }
        if let id = run.plannedSessionID,
           let session = state.weeks.lazy.flatMap(\.plan.sessions).first(where: { $0.id == id }),
           session.status.isPlanned || session.status == .missed {
            return .planned(sessionID: id)
        }
        if state.runReview.extraRunIDs.contains(run.id) { return .extra }
        let runDay = calendar.startOfDay(for: run.start)
        var best: (id: UUID, days: Int, difference: Double)?
        for record in state.weeks {
            for session in record.plan.sessions where session.kind.isRun && (session.status.isPlanned || session.status == .missed) {
                let day = state.date(of: session, in: record.plan, calendar: calendar)
                let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: runDay).day ?? 99)
                guard days <= 1 else { continue }
                guard let difference = relativeDifference(run, session) else { continue }
                guard difference <= matchTolerance + 1e-9 else { continue }
                if best == nil || days < best!.days || (days == best!.days && difference < best!.difference) {
                    best = (session.id, days, difference)
                }
            }
        }
        return best.map { .planned(sessionID: $0.id) } ?? .extra
    }

    /// |run − planned| ÷ planned, by duration when the session has one, else by distance.
    static func relativeDifference(_ run: LoggedRun, _ session: PlannedSession) -> Double? {
        if session.target.seconds > 0 {
            return abs(run.movingSeconds - session.target.seconds) / session.target.seconds
        }
        if session.target.meters > 0, run.meters > 0 {
            return abs(run.meters - session.target.meters) / session.target.meters
        }
        return nil
    }

    /// The planned session a run completed, once matched.
    static func matchedSession(_ run: LoggedRun, in state: CoachState) -> PlannedSession? {
        for record in state.weeks {
            if let session = record.plan.sessions.first(where: { $0.status == .done(runID: run.id) }) { return session }
        }
        return nil
    }

    /// The planned session a run completed, with its plan week and day.
    static func locate(_ run: LoggedRun, in state: CoachState, calendar: Calendar) -> (session: PlannedSession, week: Int, day: Date)? {
        for record in state.weeks {
            if let session = record.plan.sessions.first(where: { $0.status == .done(runID: run.id) }) {
                return (session, record.plan.index, state.date(of: session, in: record.plan, calendar: calendar))
            }
        }
        return nil
    }

    static func markDone(sessionID: UUID, runID: UUID, state: CoachState) -> CoachState {
        var state = state
        for weekIndex in state.weeks.indices {
            for sessionIndex in state.weeks[weekIndex].plan.sessions.indices where state.weeks[weekIndex].plan.sessions[sessionIndex].id == sessionID {
                state.weeks[weekIndex].plan.sessions[sessionIndex].status = .done(runID: runID)
            }
        }
        return state
    }

    /// Done sessions whose run was deleted, or is now dropped by the data gate, go back to planned (or missed, once
    /// their day has passed), and what those runs did is taken back (`forget`).
    static func syncMatches(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachState {
        let all = Set(runs.map(\.id))
        let usable = Set(RunDataGate.usableRuns(runs).map(\.id))
        var gone = Set<UUID>()
        for record in state.weeks {
            for session in record.plan.sessions {
                if case .done(let runID) = session.status, !usable.contains(runID) { gone.insert(runID) }
            }
        }
        let review = state.runReview
        let kept = review.reviewedRunIDs + review.extraRunIDs + review.spikes.map(\.runID) + review.judgements.map(\.runID)
            + review.effects.map(\.runID) + review.advice.map(\.runID) + review.offers.map(\.runID) + review.runNotes.map(\.runID)
        for id in kept where !all.contains(id) { gone.insert(id) }
        var state = gone.isEmpty ? state : forget(gone, state: state, now: now, calendar: calendar)
        state.runReview.reviewedRunIDs.removeAll { !all.contains($0) }
        return state
    }

    /// Takes back what deleted or dropped runs did: their matches, spikes, judgements, pace changes, advice, offers
    /// and notes (FB-2, AD-8).
    static func forget(_ ids: Set<UUID>, state: CoachState, now: Date, calendar: Calendar) -> CoachState {
        var state = state
        let today = calendar.startOfDay(for: now)
        for weekIndex in state.weeks.indices {
            let week = state.weeks[weekIndex].plan
            for sessionIndex in week.sessions.indices {
                let session = week.sessions[sessionIndex]
                if case .done(let runID) = session.status, ids.contains(runID) {
                    let day = state.date(of: session, in: week, calendar: calendar)
                    state.weeks[weekIndex].plan.sessions[sessionIndex].status = day < today ? .missed : .planned
                }
            }
        }
        let effects = state.runReview.effects.filter { ids.contains($0.runID) }
        for effect in effects { invert(effect.kind, changed: effect.changed, paces: &state.paces) }
        state.runReview.effects.removeAll { ids.contains($0.runID) }
        if effects.contains(where: { $0.kind == .qualityRaise }) { resetLastRaise(&state) }
        state.runReview.extraRunIDs.removeAll { ids.contains($0) }
        state.runReview.spikes.removeAll { ids.contains($0.runID) }
        state.runReview.judgements.removeAll { ids.contains($0.runID) }
        state.runReview.advice.removeAll { ids.contains($0.runID) }
        state.runReview.offers.removeAll { ids.contains($0.runID) }
        dropRetests({ $0.runID.map(ids.contains) ?? false }, state: &state)
        state.runReview.runNotes.removeAll { ids.contains($0.runID) }
        syncQuality(&state)
        return state
    }
}
