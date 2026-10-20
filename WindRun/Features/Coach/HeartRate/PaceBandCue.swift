//
//  PaceBandCue.swift
//  Wind Run
//

import Foundation

/// The in-run even-pace cue from the coach's pacing advice (FB-2, `PacingAdviceKind.evenBand`): while
/// the runner is in a paced part of the session, it speaks when their pace has been outside the band
/// for a minute. In Build Distance the band is only a ceiling, so it never asks for more speed.
struct PaceBandCueTracker {
    enum Cue: Equatable {
        case tooFast
        case tooSlow

        var text: String {
            switch self {
            case .tooFast: "A little quicker than your even pace. Ease back a touch."
            case .tooSlow: "A little slower than your even pace."
            }
        }
    }

    /// The session's parts in order; a part with a ceiling is paced (the ceiling's value isn't used).
    let parts: [HeartRateCue.Part]
    /// Seconds per km, the faster end first.
    let band: PaceBand
    /// A ceiling only: no cue for running slower.
    let ceilingOnly: Bool

    static let hold: TimeInterval = 60
    static let minimumGap: TimeInterval = 3 * 60
    /// Pace is read over this much running.
    static let window: TimeInterval = 30

    private var index = 0
    private var partStart = (elapsed: TimeInterval(0), meters: 0.0)
    private var history: [(elapsed: TimeInterval, meters: Double)] = []
    private var outSince: (TimeInterval, Cue)?
    private var armed = true
    private var lastCue: TimeInterval?

    init(parts: [HeartRateCue.Part], band: PaceBand, ceilingOnly: Bool) {
        self.parts = parts
        self.band = band
        self.ceilingOnly = ceilingOnly
    }

    mutating func update(elapsed: TimeInterval, meters: Double) -> Cue? {
        advance(elapsed: elapsed, meters: meters)
        history.append((elapsed, meters))
        history.removeAll { $0.elapsed < elapsed - Self.window }
        guard index < parts.count, parts[index].ceiling != nil,
              elapsed - partStart.elapsed >= max(parts[index].delay, Self.window),
              let first = history.first, elapsed - first.elapsed >= Self.window * 0.9, meters > first.meters
        else {
            outSince = nil
            return nil
        }
        let pace = (elapsed - first.elapsed) / (meters - first.meters) * 1_000
        let cue: Cue? = pace < band.fast ? .tooFast : (pace > band.slow && !ceilingOnly ? .tooSlow : nil)
        guard let cue else {
            outSince = nil
            armed = true
            return nil
        }
        if outSince?.1 != cue { outSince = (elapsed, cue) }
        guard armed, let since = outSince?.0, elapsed - since >= Self.hold,
              lastCue.map({ elapsed - $0 >= Self.minimumGap }) ?? true
        else { return nil }
        armed = false
        lastCue = elapsed
        return cue
    }

    /// The paced parts of a session: its running work steps, or all of a continuous run. Warm-ups,
    /// cool-downs, recoveries and walks aren't paced.
    static func parts(for session: PlannedSession) -> [HeartRateCue.Part] {
        guard !session.blocks.isEmpty else { return [HeartRateCue.Part(span: .toEnd, ceiling: 1)] }
        return session.blocks.flatMap { block in
            (0..<block.repeats).flatMap { _ in
                block.steps.map { step in
                    let span: HeartRateCue.Part.Span = switch step.goal {
                    case .time(let seconds): .seconds(seconds)
                    case .distance(let meters): .meters(meters)
                    case .open: .seconds(90)
                    }
                    return HeartRateCue.Part(span: span, ceiling: step.kind == .work && !step.walk ? 1 : nil)
                }
            }
        }
    }

    private mutating func advance(elapsed: TimeInterval, meters: Double) {
        while index < parts.count {
            let done: Bool = switch parts[index].span {
            case .seconds(let seconds): elapsed - partStart.elapsed >= seconds
            case .meters(let length): meters - partStart.meters >= length
            case .toEnd: false
            }
            guard done else { return }
            index += 1
            partStart = (elapsed, meters)
            outSince = nil
            history.removeAll()
        }
    }
}

extension PacingAdvice {
    /// What the advice asks of the next session, for the session screen.
    func text(unit: DistanceUnit, ceilingOnly: Bool) -> String {
        switch kind {
        case .evenBand:
            guard let band else { return "Aim for an even pace from start to finish." }
            return ceilingOnly
                ? "Keep this run no quicker than \(CoachFormat.pace(band.fast, unit: unit)), so it stays easy."
                : "Hold an even pace, between \(CoachFormat.pace(band.fast, unit: unit)) and \(CoachFormat.pace(band.slow, unit: unit))."
        case .splitIntoReps: return "This session runs as 5-minute reps with short recoveries: the same minutes, easier to hold."
        case .capLongRunStart: return "Keep the first third of this long run at your easy pace."
        case .holdLongRunStep: return "Your long run stays at its current length this week."
        case .tempoAsReps: return "This tempo runs as reps this time, so the pace is easier to hold."
        case .lengthenRecoveries: return "Take longer recoveries between reps before cutting any."
        }
    }
}
