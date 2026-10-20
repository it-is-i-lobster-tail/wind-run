//
//  RunHeartRate+Run.swift
//  Wind Run
//

import Foundation

/// A run's heart rate in running time, ready for the coach's checks (PZ-10). Worked out on the
/// device each time the coach is called and never stored with the plan (PZ-13).
struct RunHeartRateReading {
    struct Sample: Equatable {
        /// Running time since the start, pauses left out.
        var elapsed: TimeInterval
        var beatsPerMinute: Double
        var date: Date
    }

    /// A stretch of the run whose heart rate is decision-grade, in running time.
    struct Span: Equatable {
        var start: TimeInterval
        var end: TimeInterval
    }

    let samples: [Sample]
    let movingSeconds: TimeInterval

    /// Values outside this range are implausible (check 5).
    static let plausible = 30.0...210.0
    /// A jump this big within 5 s is implausible (check 5).
    static let implausibleJump = 30.0
    /// Coverage counts 10-second slots with at least one sample (check 2).
    static let slot: TimeInterval = 10
    /// Heart rate settles in the first 5 minutes, so it counts from then (check 3).
    static let settle: TimeInterval = 5 * 60
    /// An Apple Watch is only decision-grade in steady stretches this long (check 3).
    static let watchSegment: TimeInterval = 5 * 60

    init(samples: [Sample], movingSeconds: TimeInterval) {
        self.samples = samples.sorted { $0.elapsed < $1.elapsed }
        self.movingSeconds = movingSeconds
    }

    init(_ run: Run) {
        self.init(
            samples: run.heartRateSamples.map { Sample(elapsed: run.activeTime(at: $0.timestamp), beatsPerMinute: $0.beatsPerMinute, date: $0.timestamp) },
            movingSeconds: run.activeDuration()
        )
    }

    /// Share of a stretch's 10-second slots that have a sample.
    func coverage(from start: TimeInterval, to end: TimeInterval) -> Double {
        let slots = Int(((end - start) / Self.slot).rounded(.up))
        guard slots > 0 else { return 0 }
        let filled = Set(samples.filter { $0.elapsed >= start && $0.elapsed < end }.map { Int(($0.elapsed - start) / Self.slot) })
        return Double(filled.count) / Double(slots)
    }

    var isImplausible: Bool {
        if samples.contains(where: { !Self.plausible.contains($0.beatsPerMinute) }) { return true }
        for (a, b) in zip(samples, samples.dropFirst()) where b.date.timeIntervalSince(a.date) <= 5 {
            if abs(b.beatsPerMinute - a.beatsPerMinute) >= Self.implausibleJump { return true }
        }
        return false
    }

    func mean(in spans: [Span]) -> Double? {
        let values = samples.filter { sample in spans.contains { sample.elapsed >= $0.start && sample.elapsed <= $0.end } }.map(\.beatsPerMinute)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    func mean(from start: TimeInterval, to end: TimeInterval) -> Double? {
        mean(in: [Span(start: start, end: end)])
    }

    /// The highest 30-second average that lies wholly inside the spans.
    func peak30s(in spans: [Span]) -> Double? {
        var best: Double?
        for span in spans {
            let inside = samples.filter { $0.elapsed >= span.start && $0.elapsed <= span.end }
            for (index, first) in inside.enumerated() where first.elapsed + 30 <= span.end {
                let window = inside[index...].prefix { $0.elapsed <= first.elapsed + 30 }.map(\.beatsPerMinute)
                guard !window.isEmpty else { continue }
                let average = window.reduce(0, +) / Double(window.count)
                best = max(best ?? average, average)
            }
        }
        return best
    }

    /// The decision-grade part of the run (check 3): everything after minute 5 with a chest strap; with
    /// an Apple Watch, only steady stretches of 5 minutes or more that start after minute 5.
    func decisionGradeSpans(device: HeartRateDevice, steadyStretches: [Span]) -> [Span] {
        switch device {
        case .chestStrap:
            return movingSeconds > Self.settle ? [Span(start: Self.settle, end: movingSeconds)] : []
        case .appleWatch:
            return steadyStretches.compactMap { stretch in
                let start = max(stretch.start, Self.settle)
                return stretch.end - start >= Self.watchSegment ? Span(start: start, end: stretch.end) : nil
            }
        default:
            return []
        }
    }
}

extension RunHeartRate {
    /// The coach's reading of a run's heart rate, or nil when the run has none.
    ///
    /// - Parameters:
    ///   - steps: the structured steps as run, with which are work, for rep grading.
    ///   - track: the run's track, for the distance and climb of each window.
    ///   - steadyStretches: the stretches of steady running; an Apple Watch is only decision-grade in these.
    ///   - cadenceLock: PZ-10 check 4 from the run's step counts, or nil when they can't tell.
    init?(
        reading: RunHeartRateReading,
        settings: HeartRateSettings,
        steps: [(step: RecordedStep, isWork: Bool)],
        track: RunTrack?,
        steadyStretches: [RunHeartRateReading.Span],
        cadenceLock: Bool?
    ) {
        guard !reading.samples.isEmpty, reading.movingSeconds > 0 else { return nil }
        let device = settings.device
        let spans = reading.decisionGradeSpans(device: device, steadyStretches: steadyStretches)

        func window(_ start: TimeInterval, _ end: TimeInterval) -> RunHeartRateWindow? {
            guard end > start, let mean = reading.mean(from: start, to: end) else { return nil }
            let from = track?.position(at: start), to = track?.position(at: end)
            let meters = (to?.meters ?? 0) - (from?.meters ?? 0)
            guard meters > 0 else { return nil }
            return RunHeartRateWindow(seconds: end - start, meters: meters, mean: mean, climbMeters: track.map { _ in (to?.climb ?? 0) - (from?.climb ?? 0) })
        }

        // Halves after the first km and minute 5, for decoupling (FB-4k).
        let firstKilometer = track.flatMap { track in track.points.first { $0.meters >= 1_000 }?.elapsed } ?? RunHeartRateReading.settle
        let halvesStart = max(RunHeartRateReading.settle, firstKilometer)
        let middle = halvesStart + (reading.movingSeconds - halvesStart) / 2

        let workSteps: [StepHeartRate] = steps.filter(\.isWork).map { entry in
            // Each rep from its 2nd minute (PZ-10's rep grading).
            let start = entry.step.startElapsed + 60, end = entry.step.endElapsed
            guard end > start else { return StepHeartRate(mean: nil, lastMinutePeak: nil, coverage: 0) }
            let lastMinute = reading.samples.filter { $0.elapsed >= max(start, end - 60) && $0.elapsed <= end }.map(\.beatsPerMinute)
            return StepHeartRate(mean: reading.mean(from: start, to: end), lastMinutePeak: lastMinute.max(), coverage: reading.coverage(from: start, to: end))
        }

        let fromTen = spans.compactMap { span -> RunHeartRateReading.Span? in
            let start = max(span.start, 10 * 60)
            return span.end > start ? RunHeartRateReading.Span(start: start, end: span.end) : nil
        }

        self.init(
            source: device,
            useForCoaching: settings.useForCoaching,
            // Recorded by this app's own workout session from one sensor.
            mixedOrThirdParty: false,
            coverage: reading.coverage(from: 0, to: reading.movingSeconds),
            // Unknown without step counts fine enough to compare, which keeps the run shown only.
            cadenceLock: cadenceLock,
            implausible: reading.isImplausible,
            // Air temperature isn't known.
            coldDropouts: nil,
            mean: reading.mean(in: spans),
            minutes5to10: reading.movingSeconds >= 10 * 60 ? window(5 * 60, 10 * 60) : nil,
            firstHalf: middle > halvesStart ? window(halvesStart, middle) : nil,
            secondHalf: middle > halvesStart ? window(middle, reading.movingSeconds) : nil,
            workSteps: workSteps,
            peak30s: reading.peak30s(in: spans),
            fromMinute10: reading.mean(in: fromTen),
            labMax: settings.labMax
        )
    }
}
