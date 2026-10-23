//
//  StepTracker.swift
//  Wind Run
//

import Foundation

/// One step of a structured run as it was actually run: where it started and ended in running
/// time and distance. Kept with the run so the coach reads the real steps, not the planned ones.
struct RecordedStep: Codable, Equatable {
    /// The step's place in the workout's timeline.
    var index: Int
    var startElapsed: TimeInterval
    var endElapsed: TimeInterval
    var startMeters: Double
    var endMeters: Double
    /// Ended before its goal by the runner or the run finishing, or skipped.
    var cut: Bool

    var seconds: TimeInterval { max(0, endElapsed - startElapsed) }
    var meters: Double { max(0, endMeters - startMeters) }
}

/// Follows a structured run through its steps. Timed and distance steps end on their own; open
/// steps, such as walk breaks, end when the runner taps on, with a reminder after 90 seconds.
///
/// Feed it the run's active time and distance about once a second.
struct StepTracker {
    let timeline: [PlannedIntervalStep]
    private(set) var index = 0
    private(set) var recorded: [RecordedStep] = []
    private var start = (elapsed: TimeInterval(0), meters: 0.0)
    private var reminded = false

    /// An open step reminds the runner after this long (BD-2a).
    static let openReminder: TimeInterval = 90

    init(timeline: [PlannedIntervalStep]) {
        self.timeline = timeline
    }

    var current: PlannedIntervalStep? { timeline.indices.contains(index) ? timeline[index] : nil }
    var isFinished: Bool { index >= timeline.count }

    /// What happened on this update.
    enum Event: Equatable {
        /// The next step started, after the last one reached its goal.
        case started(PlannedIntervalStep)
        /// An open step has run long enough for a reminder.
        case openReminder
        /// The last step reached its goal.
        case finished
    }

    /// Ends every step that reached its goal and reports what changed.
    mutating func update(elapsed: TimeInterval, meters: Double) -> Event? {
        var event: Event?
        while let step = current, reached(step.goal, elapsed: elapsed, meters: meters) {
            close(elapsed: elapsed, meters: meters, cut: false)
            event = current.map(Event.started) ?? .finished
        }
        if event == nil, case .open = current?.goal, !reminded, elapsed - start.elapsed >= Self.openReminder {
            reminded = true
            return .openReminder
        }
        return event
    }

    /// The runner ended the step: an open step ends as planned, any other step is cut short.
    mutating func endCurrentStep(elapsed: TimeInterval, meters: Double) -> PlannedIntervalStep? {
        guard let step = current else { return nil }
        let cut: Bool = if case .open = step.goal { false } else { !reached(step.goal, elapsed: elapsed, meters: meters) }
        close(elapsed: elapsed, meters: meters, cut: cut)
        return current
    }

    /// The run ended: the step under way is cut short and any steps left count as skipped.
    mutating func finish(elapsed: TimeInterval, meters: Double) {
        if let step = current {
            let cut: Bool = if case .open = step.goal { false } else { !reached(step.goal, elapsed: elapsed, meters: meters) }
            close(elapsed: elapsed, meters: meters, cut: cut)
        }
        while !isFinished {
            close(elapsed: elapsed, meters: meters, cut: true)
        }
    }

    /// How much of the current step is left: seconds for a timed step, meters for a distance step.
    func remaining(elapsed: TimeInterval, meters: Double) -> IntervalGoal? {
        switch current?.goal {
        case .time(let seconds): .time(max(0, seconds - (elapsed - start.elapsed)))
        case .distance(let length): .distance(meters: max(0, length - (meters - start.meters)))
        case .open: .open
        case nil: nil
        }
    }

    /// Running time in the current step so far.
    func elapsedInStep(_ elapsed: TimeInterval) -> TimeInterval { max(0, elapsed - start.elapsed) }

    /// A timed step counts down its last few seconds, so the runner feels the change coming.
    static let countdownSeconds = 3

    /// The whole seconds left, 3, 2 or 1, while a timed step is in its countdown; nil otherwise.
    func countdown(elapsed: TimeInterval) -> Int? {
        guard case .time(let seconds) = current?.goal else { return nil }
        let left = seconds - (elapsed - start.elapsed)
        guard left > 0 else { return nil }
        let whole = Int(left.rounded(.up))
        return whole <= Self.countdownSeconds ? whole : nil
    }

    private func reached(_ goal: IntervalGoal, elapsed: TimeInterval, meters: Double) -> Bool {
        switch goal {
        case .time(let seconds): elapsed - start.elapsed >= seconds
        case .distance(let length): meters - start.meters >= length
        case .open: false
        }
    }

    private mutating func close(elapsed: TimeInterval, meters: Double, cut: Bool) {
        recorded.append(RecordedStep(
            index: index,
            startElapsed: start.elapsed,
            endElapsed: elapsed,
            startMeters: start.meters,
            endMeters: meters,
            cut: cut
        ))
        index += 1
        start = (elapsed, meters)
        reminded = false
    }
}
