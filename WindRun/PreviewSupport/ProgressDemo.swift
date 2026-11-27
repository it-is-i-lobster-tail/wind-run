#if DEBUG
import Foundation
import SwiftData

/// A disposable, repeatable history for the simulator. Launch with -progressDemo.
enum ProgressDemo {
    static let testsSearch = ProcessInfo.processInfo.arguments.contains("-searchUITests")

    static let isRequested: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-historyDemo") || arguments.contains("-progressDemo") { return true }
        #if targetEnvironment(simulator)
        // A dedicated demo simulator can also open the sample history from its Home Screen.
        // Ordinary simulators keep their own store unless explicitly enrolled.
        let key = "showProgressDemoOnLaunch"
        if arguments.contains("-endProgressDemo") { UserDefaults.standard.removeObject(forKey: key) }
        if arguments.contains("-rememberProgressDemo") { UserDefaults.standard.set(true, forKey: key) }
        return UserDefaults.standard.bool(forKey: key) && !WindRunSchema.runsInMemory && !WindRunSeed.isRequested
        #else
        return false
        #endif
    }()

    static func populate(_ context: ModelContext) {
        let plan = WorkoutDraft(name: "4 × 400 m", warmup: .time(300),
                                main: .intervals(.init(work: .distance(meters: 400), recovery: .time(90), repeats: 4)),
                                cooldown: .time(300)).save(replacing: nil, in: context)
        let repeats = [[119, 120, 120, 121], [114, 118, 122, 126], [115, 116, 116, 117], [120, 123, 124, 125]]
        for index in repeats.indices {
            let week = index * 7
            let reps = repeats[index]
            let intervals = plan.timeline.map { step -> Leg in
                switch step.kind {
                case .work: return Leg(seconds: Double(reps[step.repetition - 1]), meters: 400, work: true)
                case .recovery: return Leg(seconds: 90, meters: 185)
                default: return Leg(seconds: 300, meters: 805)
                }
            }
            makeRun(context, daysAgo: week + 1, variant: index, legs: intervals, plan: plan)
            let distanceSeconds: [Double] = [1545, 1590, 1512, 1625]
            makeRun(context, daysAgo: week + 3, variant: index + 3,
                    legs: [Leg(seconds: distanceSeconds[index], meters: 5000)], goal: .distance(meters: 5000))
            let timedMeters: [Double] = [5470, 5320, 5550, 5200]
            makeRun(context, daysAgo: week + 5, variant: index + 5,
                    legs: [Leg(seconds: 1800, meters: timedMeters[index])], goal: .time(seconds: 1800))
        }
        for (index, distance) in [3200.0, 7400, 4600, 6300, 3950, 8350, 5600, 4100].enumerated() {
            makeRun(context, daysAgo: [2, 7, 11, 14, 20, 27, 31, 36][index], variant: index + 9,
                    legs: [Leg(seconds: distance * (0.33 + 0.01 * Double(index % 4)), meters: distance)])
        }
        context.saveQuietly()
    }

    private struct Leg {
        var seconds: Double
        var meters: Double
        var work = false
    }

    private static func makeRun(_ context: ModelContext, daysAgo: Int, variant: Int, legs: [Leg],
                                plan: IntervalPlan? = nil, goal: RunGoal? = nil) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now))!
        let start = day.addingTimeInterval(Double(7 + variant % 4) * 3600 + 900)
        let run = Run(kind: plan == nil ? .free : .intervals, startDate: start)
        run.goal = goal
        run.intervalPlanValue = plan
        let phase = Double(variant)
        // Repeat workouts share a start. Free runs visit other spots around Golden Gate Park.
        let starts = [(37.7695, -122.4545), (37.7680, -122.4675), (37.7724, -122.4605),
                      (37.7708, -122.4760), (37.7660, -122.4800), (37.7742, -122.4505),
                      (37.7644, -122.4552), (37.7750, -122.4700)]
        let spot = starts[plan != nil ? 0 : variant % starts.count]
        var fixes: [RouteSample] = []
        var beats: [HeartRateSample] = []
        var counts: [StepCountSample] = []
        var log: [RecordedStep] = []
        var elapsed = 0.0
        var distance = 0.0
        var pulse = 104.0
        for (index, leg) in legs.enumerated() {
            let ticks = Int(ceil(leg.seconds / 10))
            let dt = leg.seconds / Double(ticks)
            let startMeters = distance
            let startTime = elapsed
            for tick in (index == 0 ? 0 : 1)...ticks {
                let fraction = Double(tick) / Double(ticks)
                // Small, smooth pacing changes that integrate to exactly the prescribed distance.
                let local = leg.meters * (fraction + 0.004 * (sin(2 * .pi * fraction + phase) - sin(phase)))
                let meters = startMeters + local
                let speed = tick == 0 ? 0 : (meters - distance) / dt
                elapsed = startTime + leg.seconds * fraction
                let date = start.addingTimeInterval(elapsed)
                let theta = meters / 530
                // Drawn a hair wider than the 530 m the angle steps by, so the straight lines between fixes
                // 10 s apart, which cut the curve a little, still add up to the distance each run records.
                let drawnRadius = 530.5
                let loopLatitude = drawnRadius / 111_195
                let loopLongitude = drawnRadius / (111_195 * cos(spot.0 * .pi / 180))
                fixes.append(RouteSample(timestamp: date, latitude: spot.0 + loopLatitude * sin(theta),
                                         longitude: spot.1 + loopLongitude * (cos(theta) - 1),
                                         altitude: 35 + 7 * sin(theta + phase / 5) + 2 * sin(3 * theta),
                                         horizontalAccuracy: 3, verticalAccuracy: 2, speed: speed))
                let target = (leg.work ? 168.0 : 120 + speed * 9) + 4 * sin(theta + phase)
                pulse += (target - pulse) * 0.22
                beats.append(HeartRateSample(timestamp: date, beatsPerMinute: pulse))
                if tick > 0 {
                    let cadence = 151 + 6 * speed + 3 * sin(theta + phase)
                    counts.append(StepCountSample(start: date.addingTimeInterval(-dt), end: date, count: cadence * dt / 60))
                }
                distance = meters
            }
            log.append(RecordedStep(index: index, startElapsed: startTime, endElapsed: elapsed,
                                    startMeters: startMeters, endMeters: distance, cut: false))
        }
        run.routeSamplesValue = fixes
        run.heartRateSamplesValue = beats
        run.distanceMetersValue = distance
        run.saveStepCounts(counts)
        if plan != nil { run.saveStepLog(log) }
        run.activeCaloriesValue = (distance * 0.066).rounded()
        run.finish(at: start.addingTimeInterval(elapsed))
        context.insert(run)
    }
}
#endif
