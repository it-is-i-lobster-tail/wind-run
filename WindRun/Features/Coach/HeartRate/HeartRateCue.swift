//
//  HeartRateCue.swift
//  Wind Run
//

import Foundation

/// The in-run heart-rate cue for a coached run (PZ-12). While the runner is in a part of the run
/// that has a heart-rate ceiling, the cue plays when heart rate stays above the ceiling,
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
