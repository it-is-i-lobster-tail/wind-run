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
            WatchRunScreen(display: display, readings: readings) {}
                .watchRunBackground()
        }
        .tabViewStyle(.verticalPage)
    }

    /// The demo's run: 32:48 and 6.40 km in, unless the kind says otherwise.
    private var input: WatchRunDisplay.Input {
        var input = WatchRunDisplay.Input(status: .active, elapsed: 32 * 60 + 48, meters: 6_400, unit: .kilometers)
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
        case .coach:
            input.coach = Self.coach
        }
        return input
    }

    private var display: WatchRunDisplay { WatchRunDisplay(input) }

    private var readings: DisplayScreenReadings {
        let input = self.input
        let snapshot = RunSnapshot(
            isPaused: input.status == .paused,
            elapsed: input.elapsed,
            meters: input.meters,
            unit: input.unit,
            currentPace: kind == .timed ? 248 : 312,
            averagePace: 307,
            beatsPerMinute: 148,
            heightFromStart: -43,
            cadence: 172,
            goalMeters: input.coach?.meters,
            paceTarget: input.coach?.pace
        )
        return DisplayScreen.current.readings(snapshot)
    }

    private static let coach = CoachWorkoutTarget(
        title: "Easy run", detail: "", notes: "", meters: 8_000, seconds: nil,
        pace: 290...305, effort: nil, runWalk: nil, isKeySession: false, isQuality: false
    )

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
}
#endif
