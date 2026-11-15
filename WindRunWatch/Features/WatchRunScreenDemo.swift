//
//  WatchRunScreenDemo.swift
//  Wind Run Watch
//

#if DEBUG
import SwiftUI

/// The run screen with made-up numbers, for screenshots in the simulator, which has no run to show.
/// Launch with `-watchRunScreenDemo free`, `open`, `timed`, `paused` or `coach`. Debug builds only.
struct WatchRunScreenDemo: View {
    enum Kind: String {
        case free, open, timed, paused, coach
    }

    let kind: Kind

    /// The demo the launch arguments ask for, or nil for the app as usual.
    static var requested: Kind? {
        UserDefaults.standard.string(forKey: "watchRunScreenDemo").flatMap(Kind.init(rawValue:))
    }

    var body: some View {
        TabView {
            WatchRunScreen(display: display, heartRate: heartRate) {}
                .watchRunBackground()
        }
        .tabViewStyle(.verticalPage)
    }

    private var display: WatchRunDisplay {
        var input = WatchRunDisplay.Input(
            status: .active,
            elapsed: 32 * 60 + 48,
            meters: 6_400,
            unit: .kilometers,
            currentPace: 312,
            heightFromStart: -43
        )
        switch kind {
        case .free:
            break
        case .paused:
            input.status = .paused
        case .open:
            // Warm up, then Work 3:00 and an open Recover five times, then an open cool down: 12 steps.
            var steps = Self.intervals
            _ = steps.update(elapsed: 600, meters: 1_900)
            _ = steps.update(elapsed: 780, meters: 2_600)
            input.steps = steps
        case .timed:
            var steps = Self.intervals
            _ = steps.update(elapsed: 600, meters: 1_900)
            input.steps = steps
            input.elapsed = 623
            input.meters = 1_990
            input.currentPace = 248
        case .coach:
            input.coach = CoachWorkoutTarget(
                title: "Easy run", detail: "", notes: "", meters: 8_000, seconds: nil,
                pace: 290...305, effort: nil, runWalk: nil, isKeySession: false, isQuality: false
            )
        }
        return WatchRunDisplay(input)
    }

    private static var intervals: StepTracker {
        let reps = 5
        let middle = (1...reps).flatMap { repetition in
            [
                PlannedIntervalStep(kind: .work, goal: .time(180), repetition: repetition, repeatCount: reps),
                PlannedIntervalStep(kind: .recovery, goal: .open, repetition: repetition, repeatCount: reps),
            ]
        }
        return StepTracker(timeline:
            [PlannedIntervalStep(kind: .warmup, goal: .time(600), repetition: 1, repeatCount: 1)]
            + middle
            + [PlannedIntervalStep(kind: .cooldown, goal: .open, repetition: 1, repeatCount: 1)]
        )
    }

    /// Fifteen minutes climbing from the low 130s to about 148, with a little wander.
    private var heartRate: WatchRunScreen.HeartRate {
        let end = Date.now
        let points = stride(from: 0, through: 900, by: 5).map { second in
            let t = Double(second) / 900
            let bpm = 130 + 18 * t + 3 * sin(Double(second) / 23) + 1.5 * sin(Double(second) / 7)
            return HeartRateHistory.Point(date: end.addingTimeInterval(Double(second) - 900), beatsPerMinute: bpm)
        }
        return WatchRunScreen.HeartRate(points: points, beatsPerMinute: 148)
    }
}
#endif
