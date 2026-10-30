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
        ProcessInfo.processInfo.arguments.contains("-seedSampleRuns") || plansRequested
    }

    /// Launch with `-seedCoachPlan` for the sample runs and a Build Distance plan toward a trail half marathon, with
    /// the terms accepted, for screenshots of the coach.
    static var plansRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedCoachPlan")
    }

    /// A Build Distance plan from 30 km a week toward a hilly half marathon 14 weeks out, on Tuesdays, Thursdays,
    /// Saturdays and Sundays.
    static func addSamplePlan(to context: ModelContext) {
        TermsAcceptance.accept()
        let date = Calendar.current.date(byAdding: .weekOfYear, value: 14, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let settings = BuildSettings(
            currentWeeklyMeters: 30_000,
            currentWeeklyClimbMeters: 400,
            goal: BuildGoal(event: .halfMarathon, climbMeters: 600, date: date),
            runDays: [.tuesday, .thursday, .saturday, .sunday]
        )
        BuildService(context: context).start(settings)
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
    /// around a park loop with one hill, with heart rate that climbs in each rep and settles in each recovery,
    /// steps counted all the way, and a stop at a light in the warm up and in the cool down.
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

        // Seconds, pace in seconds per km, the heart rate the step settles toward, and steps a minute.
        let steps: [(seconds: TimeInterval, pace: Double, heartRate: Double, cadence: Double)] = [
            (600, 372, 138, 164),
            (240, 252, 168, 178), (90, 410, 146, 158),
            (240, 247, 171, 180), (90, 418, 149, 157),
            (240, 255, 173, 177), (90, 405, 151, 159),
            (240, 262, 175, 175), (90, 425, 153, 156),
            (480, 380, 145, 162),
        ]
        // Stops at lights: running time they start at, and how long they last.
        let stops: [(at: TimeInterval, seconds: TimeInterval)] = [(330, 40), (2_200, 55)]

        // A loop around a park, about 6.5 km, walked by distance so faster steps cover more of it.
        let center = (latitude: 37.7694, longitude: -122.4662)
        let radii = (east: 1_400.0, north: 650.0)
        func offset(atAngle angle: Double) -> (east: Double, north: Double) {
            (radii.east * cos(angle) + 30 * sin(angle * 7), radii.north * sin(angle))
        }
        // Distance around the loop at each of many angles, so a meter run is a meter along the loop
        // wherever it falls, on the long sides or round the ends.
        let angleSteps = 2_000
        var loopMeters = [0.0]
        for step in 1...angleSteps {
            let a = offset(atAngle: 2 * Double.pi * Double(step - 1) / Double(angleSteps))
            let b = offset(atAngle: 2 * Double.pi * Double(step) / Double(angleSteps))
            loopMeters.append(loopMeters[step - 1] + hypot(b.east - a.east, b.north - a.north))
        }
        let perimeter = loopMeters[angleSteps]
        func angle(atMeters meters: Double) -> Double {
            let along = meters.truncatingRemainder(dividingBy: perimeter)
            var low = 0
            var high = angleSteps
            while high - low > 1 {
                let middle = (low + high) / 2
                if loopMeters[middle] <= along { low = middle } else { high = middle }
            }
            let fraction = (along - loopMeters[low]) / max(loopMeters[high] - loopMeters[low], 0.001)
            return 2 * Double.pi * (Double(low) + fraction) / Double(angleSteps)
        }
        // One climb of about 18 m on the far side of the loop.
        func altitude(atMeters meters: Double) -> Double {
            64 + 9 * sin(angle(atMeters: meters))
        }
        func coordinate(atMeters meters: Double) -> (latitude: Double, longitude: Double) {
            let point = offset(atAngle: angle(atMeters: meters))
            return (center.latitude + point.north / 111_111, center.longitude + point.east / (111_111 * cos(center.latitude * .pi / 180)))
        }

        var elapsed: TimeInterval = 0
        var paused: TimeInterval = 0
        var meters = 0.0
        var heartRate = 112.0
        var recorded: [RecordedStep] = []
        var barometer: [AltitudeSample] = []
        var footsteps: [StepCountSample] = []
        let tick: TimeInterval = 5
        for (index, step) in steps.enumerated() {
            let stepStart = (elapsed: elapsed, meters: run.distanceMeters)
            var inStep: TimeInterval = 0
            while inStep < step.seconds {
                if let stop = stops.first(where: { $0.at == elapsed }) {
                    let date = start.addingTimeInterval(elapsed + paused)
                    run.pause(at: date)
                    run.resume(at: date.addingTimeInterval(stop.seconds))
                    paused += stop.seconds
                }
                inStep += tick
                elapsed += tick
                // A little wobble, so the pace line looks like a real run.
                let pace = step.pace * (1 + 0.03 * sin(elapsed / 23))
                meters += 1_000 / pace * tick
                heartRate += (step.heartRate - heartRate) * 0.12
                let point = coordinate(atMeters: meters)
                let date = start.addingTimeInterval(elapsed + paused)
                // Steps in 15-second stretches, as the motion sensor keeps them.
                let count = (step.cadence + 2 * sin(elapsed / 17)) * tick / 60
                if var last = footsteps.last, last.end == date.addingTimeInterval(-tick), date.timeIntervalSince(last.start) <= 15 {
                    last.end = date
                    last.count += count
                    footsteps[footsteps.count - 1] = last
                } else {
                    footsteps.append(StepCountSample(start: date.addingTimeInterval(-tick), end: date, count: count))
                }
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
                // The barometer's climb from the start, with its few centimeters of jitter.
                barometer.append(AltitudeSample(timestamp: date, relativeMeters: altitude(atMeters: meters) - altitude(atMeters: 0) + 0.1 * sin(elapsed / 7)))
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
        run.saveBarometricAltitude(barometer)
        run.saveStepCounts(footsteps)
        run.finish(at: start.addingTimeInterval(elapsed + paused))
        return run
    }
}
