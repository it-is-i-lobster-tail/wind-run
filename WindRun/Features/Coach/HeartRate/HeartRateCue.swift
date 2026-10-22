//
//  HeartRateCue.swift
//  Wind Run
//

import Foundation

/// The in-run heart-rate cue for a coached session (PZ-12). While the runner is in a part of the
/// session that has a heart-rate ceiling, the cue plays when heart rate stays above the ceiling,
/// plus a margin for the device, for a minute. It only ever says to ease off.
enum HeartRateCue {
    static let text = "Heart rate is above your ceiling. Ease off a little."

    /// How long heart rate has to stay over before the cue plays.
    static let hold: TimeInterval = 60
    /// The cue plays at most this often.
    static let minimumGap: TimeInterval = 3 * 60
    /// An Apple Watch reading settles slowly, so nothing cues in a watch run's first 5 minutes.
    static let watchQuietStart: TimeInterval = 5 * 60

    /// One part of the session in order: how long it lasts, and its ceiling if it has one.
    struct Part: Equatable {
        enum Span: Equatable {
            case seconds(TimeInterval)
            case meters(Double)
            /// The rest of the run.
            case toEnd
        }

        var span: Span
        /// Beats per minute, or nil for parts that never cue.
        var ceiling: Double?
        /// Seconds into the part before the cue may count.
        var delay: TimeInterval = 0
    }

    /// The parts of a planned session with their ceilings. Empty when nothing in it cues.
    ///
    /// Easy, long and run-walk running hold the easy ceiling, steady (half or marathon pace) work the
    /// steady ceiling, and threshold work the top of the threshold band from its second minute, when
    /// it's continuous or in reps of 3 minutes or more (4 with an Apple Watch). Nothing else cues:
    /// VO2max and shorter reps, hills, strides, tests, goal attempts, warm-ups, cool-downs, recoveries
    /// and walks.
    static func parts(for session: PlannedSession, zones: HeartRateZones, device: HeartRateDevice, thresholdPace: Double?) -> [Part] {
        guard session.kind.isRun, session.appTest == nil else { return [] }
        switch session.kind {
        case .test, .race, .hills, .shortReps: return []
        default: break
        }
        let isEasyKind = session.kind == .easy || session.kind == .long || session.kind == .runWalk
        guard !session.blocks.isEmpty else {
            let effort: Effort = isEasyKind ? .easy : session.effort
            let ceiling = ceiling(for: effort, zones: zones)
            guard let ceiling else { return [] }
            return [Part(span: .toEnd, ceiling: ceiling, delay: delay(for: effort, device: device))]
        }

        let minimumRep: TimeInterval = device == .appleWatch ? 4 * 60 : 3 * 60
        var parts: [Part] = []
        for block in session.blocks {
            for _ in 0..<block.repeats {
                for step in block.steps {
                    let span: Part.Span = switch step.goal {
                    case .time(let seconds): .seconds(seconds)
                    case .distance(let meters): .meters(meters)
                    // Open steps are ladder walk breaks, which prompt at 1.5 minutes.
                    case .open: .seconds(90)
                    }
                    guard step.kind == .work, !step.walk else {
                        parts.append(Part(span: span, ceiling: nil))
                        continue
                    }
                    let effort: Effort = isEasyKind ? .easy : step.effort
                    var ceiling = ceiling(for: effort, zones: zones)
                    if effort == .threshold, block.repeats > 1 {
                        let seconds = estimatedSeconds(step, thresholdPace: thresholdPace)
                        if (seconds ?? 0) < minimumRep { ceiling = nil }
                    }
                    parts.append(Part(span: span, ceiling: ceiling, delay: delay(for: effort, device: device)))
                }
            }
        }
        return parts.contains { $0.ceiling != nil } ? parts : []
    }

    private static func ceiling(for effort: Effort, zones: HeartRateZones) -> Double? {
        switch effort {
        case .easy: zones.easyCeiling
        case .steady: zones.steadyCeiling
        case .threshold: zones.thresholdBand.upperBound
        case .interval, .race: nil
        }
    }

    private static func delay(for effort: Effort, device: HeartRateDevice) -> TimeInterval {
        switch effort {
        case .threshold: 60
        case .steady: device == .appleWatch ? watchQuietStart : 0
        default: 0
        }
    }

    /// A step's length in seconds: its time, or its distance at the middle of its pace band.
    private static func estimatedSeconds(_ step: SessionStep, thresholdPace: Double?) -> TimeInterval? {
        switch step.goal {
        case .time(let seconds): return seconds
        case .distance(let meters):
            guard let pace = step.pace.map({ ($0.fast + $0.slow) / 2 }) ?? thresholdPace else { return nil }
            return meters / 1_000 * pace
        case .open: return nil
        }
    }
}

/// Follows a coached run through its parts and says when the heart-rate cue should play.
///
/// Feed it about once a second with the run's active time, distance and the latest heart rate
/// (nil when there's no recent reading), with `device` set to what's measuring it now.
struct HeartRateCueTracker {
    let parts: [HeartRateCue.Part]
    /// What's measuring heart rate now. Only a strap or Apple Watch can cue; nil means not found yet.
    var device: HeartRateDevice?

    private(set) var index = 0
    private var partStart = (elapsed: TimeInterval(0), meters: 0.0)
    /// When heart rate went over the ceiling plus the margin, in active time.
    private var overSince: TimeInterval?
    /// Off after a cue, until heart rate comes back under the ceiling.
    private var armed = true
    private var lastCue: TimeInterval?

    init(parts: [HeartRateCue.Part], device: HeartRateDevice?) {
        self.parts = parts
        self.device = device
    }

    /// True when the cue should play now.
    mutating func update(elapsed: TimeInterval, meters: Double, beatsPerMinute: Double?) -> Bool {
        advance(elapsed: elapsed, meters: meters)
        guard index < parts.count, let ceiling = parts[index].ceiling,
              let device, device == .chestStrap || device == .appleWatch,
              elapsed - partStart.elapsed >= parts[index].delay,
              device != .appleWatch || elapsed >= HeartRateCue.watchQuietStart,
              let beatsPerMinute
        else {
            overSince = nil
            return false
        }
        guard beatsPerMinute > ceiling + HeartRateZones.cueMargin(for: device) else {
            overSince = nil
            if beatsPerMinute <= ceiling { armed = true }
            return false
        }
        let since = overSince ?? elapsed
        overSince = since
        guard armed, elapsed - since >= HeartRateCue.hold,
              lastCue.map({ elapsed - $0 >= HeartRateCue.minimumGap }) ?? true
        else { return false }
        armed = false
        lastCue = elapsed
        return true
    }

    /// Moves past every part that has ended. A new part starts its own hold.
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
            overSince = nil
        }
    }
}
