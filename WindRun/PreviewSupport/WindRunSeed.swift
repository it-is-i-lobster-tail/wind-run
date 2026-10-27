//
//  WindRunSeed.swift
//  Wind Run
//

import Foundation
import SwiftData

/// Sample data for previews.
enum WindRunSeed {
    #if DEBUG
    /// Launch with `-seedSampleRuns` to open an in-memory store holding the sample runs, for screenshots.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedSampleRuns")
    }
    #endif

    /// An in-memory store with the sample runs.
    static func containerWithRuns() -> ModelContainer {
        let container = WindRunSchema.makeContainer(inMemory: true)
        addSampleRuns(to: container.mainContext)
        return container
    }

    /// Three plain runs, each with a short straight route and heart rate, an interval run, and a saved
    /// interval workout.
    static func addSampleRuns(to context: ModelContext) {
        let runs: [(daysAgo: Double, kilometers: Double, paceSeconds: Double)] = [
            (1, 5.02, 312),
            (3, 10.4, 335),
            (6, 21.1, 348),
        ]
        for entry in runs {
            let start = Date.now.addingTimeInterval(-entry.daysAgo * 86_400)
            let run = Run(startDate: start)
            context.insert(run)

            // Walk north from a point; 0.009° of latitude is about a kilometer.
            let duration = entry.kilometers * entry.paceSeconds
            let steps = 20
            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                run.record(RouteSample(
                    timestamp: start.addingTimeInterval(duration * fraction),
                    latitude: 37.7749 + 0.009 * entry.kilometers * fraction,
                    longitude: -122.4194 + 0.002 * sin(fraction * .pi * 4),
                    horizontalAccuracy: 5
                ))
                run.record(HeartRateSample(
                    timestamp: start.addingTimeInterval(duration * fraction),
                    beatsPerMinute: 138 + 22 * fraction + 5 * sin(fraction * .pi * 6)
                ))
            }
            run.finish(at: start.addingTimeInterval(duration))
        }

        context.insert(IntervalPlan.classicFiveByThree())
        intervalRun(in: context, start: Date.now.addingTimeInterval(-3_600))
        context.saveQuietly()
    }

    /// A finished interval run: open warm up, 4 × (4 min work, 1:30 recover), open cool down,
    /// around a park loop with one hill, with heart rate that climbs in each rep and settles in each recovery.
    @discardableResult
    static func intervalRun(in context: ModelContext, start: Date = .now.addingTimeInterval(-3_600)) -> Run {
        let plan = IntervalPlan(name: "4 × 4 min", isCustom: true)
        plan.addBlock().addStep(.warmup, goal: .open)
        let repeats = plan.addBlock(repeatCount: 4)
        repeats.addStep(.work, goal: .time(4 * 60))
        repeats.addStep(.recovery, goal: .time(90))
        plan.addBlock().addStep(.cooldown, goal: .open)
        context.insert(plan)

        let run = Run(kind: .intervals, startDate: start)
        run.intervalPlanValue = plan
        context.insert(run)

        // Seconds, pace in seconds per km, and the heart rate the step settles toward.
        let steps: [(seconds: TimeInterval, pace: Double, heartRate: Double)] = [
            (600, 372, 138),
            (240, 252, 168), (90, 410, 146),
            (240, 247, 171), (90, 418, 149),
            (240, 255, 173), (90, 405, 151),
            (240, 262, 175), (90, 425, 153),
            (480, 380, 145),
        ]

        // A loop around a park, about 6.5 km, walked by distance so faster steps cover more of it.
        let center = (latitude: 37.7694, longitude: -122.4662)
        let radii = (east: 1_400.0, north: 650.0)
        // One climb of about 18 m on the far side of the loop.
        func altitude(atMeters meters: Double) -> Double {
            let perimeter = 2 * Double.pi * sqrt((radii.east * radii.east + radii.north * radii.north) / 2)
            return 64 + 9 * sin(2 * Double.pi * meters / perimeter)
        }
        func coordinate(atMeters meters: Double) -> (latitude: Double, longitude: Double) {
            let perimeter = 2 * Double.pi * sqrt((radii.east * radii.east + radii.north * radii.north) / 2)
            let angle = 2 * Double.pi * meters / perimeter
            let east = radii.east * cos(angle) + 30 * sin(angle * 7)
            let north = radii.north * sin(angle)
            return (center.latitude + north / 111_111, center.longitude + east / (111_111 * cos(center.latitude * .pi / 180)))
        }

        var elapsed: TimeInterval = 0
        var meters = 0.0
        var heartRate = 112.0
        var recorded: [RecordedStep] = []
        let tick: TimeInterval = 5
        for (index, step) in steps.enumerated() {
            let stepStart = (elapsed: elapsed, meters: run.distanceMeters)
            var inStep: TimeInterval = 0
            while inStep < step.seconds {
                inStep += tick
                elapsed += tick
                // A little wobble, so the pace line looks like a real run.
                let pace = step.pace * (1 + 0.03 * sin(elapsed / 23))
                meters += 1_000 / pace * tick
                heartRate += (step.heartRate - heartRate) * 0.12
                let point = coordinate(atMeters: meters)
                let date = start.addingTimeInterval(elapsed)
                run.record(RouteSample(
                    timestamp: date,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitude: altitude(atMeters: meters),
                    horizontalAccuracy: 5,
                    verticalAccuracy: 3,
                    speed: 1_000 / pace
                ))
                run.record(HeartRateSample(timestamp: date, beatsPerMinute: heartRate + 1.5 * sin(elapsed / 11)))
            }
            recorded.append(RecordedStep(
                index: index,
                startElapsed: stepStart.elapsed,
                endElapsed: elapsed,
                startMeters: stepStart.meters,
                endMeters: run.distanceMeters,
                cut: false
            ))
        }
        run.saveStepLog(recorded)
        run.finish(at: start.addingTimeInterval(elapsed))
        return run
    }
}
