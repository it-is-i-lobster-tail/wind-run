//
//  DisplayReadings.swift
//  Wind Run
//

import Foundation

/// A run's numbers at one moment, everything a display screen can show. The recorder makes these, so
/// every screen reads the run the same way.
struct RunSnapshot {
    var sport: WorkoutSport = .running
    var isPaused = false
    /// Running time, leaving out pauses.
    var elapsed: TimeInterval
    var meters: Double
    var unit: DistanceUnit
    /// Seconds per kilometer over the last 30 seconds, or nil with nothing to show.
    var currentPace: TimeInterval?
    /// Seconds per kilometer over the whole run, or nil until there's enough to say.
    var averagePace: TimeInterval?
    /// The newest reading, or nil when there is none.
    var beatsPerMinute: Double?
    /// Meters above the start, negative below, or nil with no height yet.
    var heightFromStart: Double?
    /// Steps a minute, or nil when step counting is off or the sensor hasn't said.
    var cadence: Double?
    /// A coach session's or a distance or timed run's distance or time to run, which the distance or time caption names.
    var goalMeters: Double?
    var goalSeconds: TimeInterval?
    /// Running time when the goal distance was reached, so the finish time holds still through a cool down.
    var goalReachedElapsed: TimeInterval?
    /// A coach session's pace range, seconds per kilometer, fastest first, which the current pace's caption names.
    var paceTarget: ClosedRange<TimeInterval>?

    /// When the snapshot was taken.
    var date: Date = .now
    /// When the runner pressed Start.
    var startDate: Date?
    /// Seconds per kilometer for the kilometer or mile under way.
    var splitPace: TimeInterval?
    /// How long the last whole kilometer or mile took.
    var lastSplit: TimeInterval?
    /// Seconds per kilometer over the last half kilometer or half mile.
    var rollingPace: TimeInterval?
    /// The interval or coach step under way, for a run with steps.
    var step: StepReading?
    /// The highest heart rate, for zones, or nil before any is known.
    var heartRateMax: Double?
    var averageHeartRate: Double?
    /// Meters climbed and dropped in total.
    var totalAscent: Double?
    var totalDescent: Double?
    /// Meters above sea level.
    var altitude: Double?
    /// Rise over run: 0.08 is 8% uphill.
    var grade: Double?
    /// Meters climbed an hour, negative dropping.
    var verticalSpeed: Double?
    /// Kilocalories so far, or nil without the runner's weight.
    var calories: Double?
    /// The next sunrise or sunset where the run started.
    var sunEvent: SunTimes.Event?
    /// Straight-line meters back to the first fix.
    var metersToStart: Double?
    /// Watts, from Apple Watch.
    var runningPower: Double?
    var cyclingCadence: Double?
    var cyclingPower: Double?

    /// The step under way.
    struct StepReading: Equatable {
        var name: String
        /// What's left of it, or `.open` for a step that runs until the runner moves on.
        var remaining: IntervalGoal?
        /// Running time spent in it so far.
        var inStep: TimeInterval
        /// True once every step is done.
        var isFinished = false
    }
}

extension DisplayScreen {
    /// The screen's six spots as they read in `snapshot`. With `clockRunsAt`, elapsed time carries the date
    /// its clock started, so a screen that isn't redrawn every second can count on its own.
    func readings(_ snapshot: RunSnapshot, clockRunsAt date: Date? = nil) -> DisplayScreenReadings {
        func reading(_ metric: DisplayMetric) -> DisplayReading {
            var reading = metric.reading(snapshot)
            if metric == .elapsed, !snapshot.isPaused, let date {
                reading.clockStart = date.addingTimeInterval(-snapshot.elapsed)
            }
            // Total time counts on through pauses.
            if metric == .totalTime, date != nil, let start = snapshot.startDate {
                reading.clockStart = start
            }
            return reading
        }
        return DisplayScreenReadings(
            primary: reading(primary),
            secondary: reading(secondary),
            tiles: tiles.map(reading)
        )
    }
}

extension DisplayMetric {
    /// How this reads in `snapshot`.
    func reading(_ snapshot: RunSnapshot) -> DisplayReading {
        let unit = snapshot.unit
        let heightUnit = unit.heightSymbol
        /// A dash with `label`, for nothing to show yet.
        func none(_ label: String, unit: String? = nil, symbol: String? = nil, tint: DisplayReading.Tint? = nil, why: String = "none yet") -> DisplayReading {
            DisplayReading(metric: self, value: "––", unit: unit, label: label, symbol: symbol, tint: tint, spoken: "\(name), \(why)")
        }
        func speed(_ pace: TimeInterval?, label: String) -> DisplayReading {
            let value = RunFormat.speedNumber(pace, unit: unit) ?? "––"
            return DisplayReading(metric: self, value: value, unit: unit == .miles ? "mph" : "km/h", label: label,
                                  spoken: "\(label), \(SpokenFormat.speed(pace, unit: unit) ?? "none yet")")
        }
        func pace(_ seconds: TimeInterval?, label: String) -> DisplayReading {
            if snapshot.sport == .cycling { return speed(seconds, label: label) }
            let value = RunFormat.pace(seconds, unit: unit, withUnit: false)
            return DisplayReading(metric: self, value: value, unit: "/\(unit.symbol)", label: label, spoken: "\(name), \(Self.spokenPace(seconds, unit: unit))")
        }
        /// Whole meters or feet, grouped as the region writes thousands: "3,281", as altitude and calories are.
        func height(_ meters: Double) -> String {
            Int(unit.height(fromMeters: meters).rounded()).formatted()
        }
        /// "KM" or "MI", for captions.
        let unitCaption = unit.symbol.uppercased()

        switch self {
        case .elapsed:
            let value = RunFormat.duration(snapshot.elapsed)
            let label = snapshot.goalSeconds.map { "OF \(RunFormat.duration($0))" } ?? "ELAPSED"
            return DisplayReading(metric: self, value: value, label: label, isDimmed: snapshot.isPaused, spoken: "Elapsed time, \(value)")
        case .distance:
            let value = RunFormat.distance(snapshot.meters, unit: unit, withUnit: false)
            // To the tenth, as the coach writes a planned run: "OF 4.6 MI".
            let label = snapshot.goalMeters.map { "OF \(RunFormat.plannedDistance($0, unit: unit).uppercased())" } ?? "DISTANCE"
            return DisplayReading(metric: self, value: value, unit: unit.symbol, label: label, spoken: "Distance, \(value) \(unit.symbol)")
        case .currentPace, .averagePace:
            let pace = self == .currentPace ? (snapshot.isPaused ? nil : snapshot.currentPace) : snapshot.averagePace
            if snapshot.sport == .cycling {
                return speed(pace, label: self == .currentPace ? "CURRENT SPEED" : "AVG SPEED")
            }
            let value = RunFormat.pace(pace, unit: unit, withUnit: false)
            var label = self == .currentPace ? "CURRENT PACE" : "AVG PACE"
            var spoken = "\(name), \(Self.spokenPace(pace, unit: unit))"
            if self == .currentPace, let target = snapshot.paceTarget {
                let fast = RunFormat.pace(target.lowerBound, unit: unit, withUnit: false)
                let slow = RunFormat.pace(target.upperBound, unit: unit, withUnit: false)
                let range = fast == slow ? fast : "\(fast)–\(slow)"
                // The big number is the pace now; the caption names the target it's aiming for.
                label = "TARGET \(range)"
                let spokenFast = SpokenFormat.pace(target.lowerBound, unit: unit)
                let spokenSlow = SpokenFormat.pace(target.upperBound, unit: unit)
                if let spokenFast, let spokenSlow {
                    spoken += fast == slow ? ", target \(spokenFast)" : ", target \(spokenFast) to \(spokenSlow)"
                }
            }
            return DisplayReading(metric: self, value: value, unit: "/\(unit.symbol)", label: label, spoken: spoken)
        case .heartRate:
            let value = RunFormat.heartRate(snapshot.beatsPerMinute, withUnit: false)
            return DisplayReading(
                metric: self,
                value: value,
                unit: "bpm",
                label: "HEART RATE",
                symbol: "heart.fill",
                tint: .heartRate,
                spoken: snapshot.beatsPerMinute == nil ? "Heart rate, no reading" : "Heart rate, \(value) beats per minute"
            )
        case .elevation:
            guard let up = snapshot.totalAscent, let down = snapshot.totalDescent else { return none("ELEVATION", unit: heightUnit) }
            let climbed = height(up)
            let dropped = height(down)
            return DisplayReading(
                metric: self,
                value: climbed,
                unit: heightUnit,
                label: "ELEVATION",
                symbol: "arrow.up",
                tint: .accent,
                then: .init(symbol: "arrow.down", value: dropped),
                spoken: "Elevation, \(climbed) \(unit.spokenHeightUnit) up, \(dropped) \(unit.spokenHeightUnit) down"
            )
        case .cadence:
            let value = RunFormat.cadence(snapshot.cadence, withUnit: false)
            return DisplayReading(
                metric: self,
                value: value,
                unit: "spm",
                label: "CADENCE",
                spoken: snapshot.cadence == nil ? "Cadence, none yet" : "Cadence, \(value) steps a minute"
            )

        case .splitPace:
            return pace(snapshot.isPaused ? nil : snapshot.splitPace, label: "THIS \(unitCaption)")
        case .lastSplit:
            guard let seconds = snapshot.lastSplit else { return none("LAST \(unitCaption)") }
            let value = RunFormat.duration(seconds)
            return DisplayReading(metric: self, value: value, label: "LAST \(unitCaption)", spoken: "Last \(unit.singularName), \(value)")
        case .rollingPace:
            return pace(snapshot.rollingPace, label: unit == .miles ? "LAST ½ MI" : "LAST 500 M")
        case .gradeAdjustedPace:
            guard snapshot.sport == .running else { return none("FLAT PACE", why: "available for running") }
            let current = snapshot.isPaused ? nil : snapshot.currentPace
            return pace(current.map { Self.gradeAdjusted($0, grade: snapshot.grade ?? 0) }, label: "FLAT PACE")

        case .stepLeft:
            guard let step = snapshot.step else { return none("STEP", why: "no steps in this run") }
            if step.isFinished {
                return DisplayReading(metric: self, value: "Done", label: "ALL STEPS", spoken: "All steps done")
            }
            let label = "\(step.name.uppercased()) LEFT"
            switch step.remaining {
            case .time(let seconds):
                // Rounded up like the 3-2-1 taps, so 0:00 shows as the step ends.
                let value = RunFormat.duration(seconds.rounded(.up))
                return DisplayReading(metric: self, value: value, label: label, spoken: "\(step.name), \(value) left")
            case .distance(let meters):
                let value = Self.shortDistance(meters, unit: unit, rounding: .up)
                return DisplayReading(metric: self, value: value.number, unit: value.unit, label: label, spoken: "\(step.name), \(value.number) \(value.unit) left")
            case .open, nil:
                let value = RunFormat.duration(step.inStep)
                return DisplayReading(metric: self, value: value, label: step.name.uppercased(), spoken: "\(step.name), \(value) so far")
            }
        case .goalLeft:
            if let goal = snapshot.goalMeters {
                let left = goal - snapshot.meters
                guard left > 0 else { return DisplayReading(metric: self, value: "Done", label: "GOAL REACHED", spoken: "Goal reached") }
                // Meters or feet over the last stretch, so it never reads 0.00 before the goal.
                let value = Self.shortDistance(left, unit: unit, rounding: .up)
                return DisplayReading(metric: self, value: value.number, unit: value.unit, label: "LEFT", spoken: "\(value.number) \(value.unit) left")
            }
            if let goal = snapshot.goalSeconds {
                let left = goal - snapshot.elapsed
                guard left > 0 else { return DisplayReading(metric: self, value: "Done", label: "GOAL REACHED", spoken: "Goal reached") }
                let value = RunFormat.duration(left.rounded(.up))
                return DisplayReading(metric: self, value: value, label: "LEFT", spoken: "\(value) left")
            }
            return none("NO GOAL", why: "no goal for this run")
        case .projectedFinish:
            if let goal = snapshot.goalMeters {
                if snapshot.meters >= goal {
                    // The time the goal was reached, not the clock running on through the cool down. A run
                    // carried on after the app was closed doesn't know it, so it's worked out from the
                    // average pace.
                    let finish = snapshot.goalReachedElapsed ?? snapshot.averagePace.map { $0 * goal / 1_000 } ?? snapshot.elapsed
                    let value = RunFormat.duration(finish)
                    return DisplayReading(metric: self, value: value, label: "FINISHED IN", spoken: "Goal reached in \(value)")
                }
                guard let pace = snapshot.averagePace else { return none("FINISH") }
                let value = RunFormat.duration(pace * goal / 1_000)
                return DisplayReading(metric: self, value: value, label: "FINISH", spoken: "Projected finish, \(value)")
            }
            if let goal = snapshot.goalSeconds {
                guard let pace = snapshot.averagePace, pace > 0 else { return none("BY THE END", unit: unit.symbol) }
                let meters = snapshot.meters + max(0, goal - snapshot.elapsed) / pace * 1_000
                let value = RunFormat.distance(meters, unit: unit, withUnit: false, rounding: .toNearestOrAwayFromZero)
                return DisplayReading(metric: self, value: value, unit: unit.symbol, label: "BY THE END", spoken: "About \(value) \(unit.symbol) by the end")
            }
            return none("NO GOAL", why: "no goal for this run")
        case .aheadBehind:
            guard let target = snapshot.paceTarget else { return none("NO TARGET", why: "no target pace for this run") }
            // Nothing to compare yet, so it doesn't claim the runner is on pace.
            guard snapshot.meters >= 50 else { return none("VS TARGET") }
            // The middle of the coach's range is the pace to run.
            let targetPace = (target.lowerBound + target.upperBound) / 2
            let ahead = targetPace * snapshot.meters / 1_000 - snapshot.elapsed
            let value = RunFormat.duration(abs(ahead))
            if abs(ahead) < 3 {
                return DisplayReading(metric: self, value: "0:00", label: "ON PACE", symbol: "equal", tint: .accent, spoken: "On pace")
            }
            return DisplayReading(
                metric: self,
                value: value,
                label: ahead > 0 ? "AHEAD" : "BEHIND",
                symbol: ahead > 0 ? "hare.fill" : "tortoise.fill",
                tint: .accent,
                spoken: "\(value) \(ahead > 0 ? "ahead of" : "behind") target pace"
            )

        case .heartRateZone:
            guard let max = snapshot.heartRateMax else { return none("HR ZONE", symbol: "heart.fill", tint: .heartRate, why: "available after your first run with heart rate") }
            guard let beats = snapshot.beatsPerMinute else { return none("HR ZONE", symbol: "heart.fill", tint: .heartRate, why: "no reading") }
            let zone = HeartRateMax.zone(beats, max: max)
            return DisplayReading(metric: self, value: "Z\(zone)", label: "HR ZONE", symbol: "heart.fill", tint: .zone(zone), spoken: "Heart rate zone \(zone)")
        case .averageHeartRate:
            let value = RunFormat.heartRate(snapshot.averageHeartRate, withUnit: false)
            return DisplayReading(
                metric: self,
                value: value,
                unit: "bpm",
                label: "AVG HR",
                symbol: "heart.fill",
                tint: .heartRate,
                spoken: snapshot.averageHeartRate == nil ? "Average heart rate, none yet" : "Average heart rate, \(value) beats per minute"
            )
        case .calories:
            guard let calories = snapshot.calories else { return none("CALORIES", unit: "kcal", why: "add your weight in Settings") }
            let value = Int(calories.rounded()).formatted()
            return DisplayReading(metric: self, value: value, unit: "kcal", label: "CALORIES", spoken: "\(value) calories")
        case .cyclingCadence, .cyclingPower:
            let isPower = self == .cyclingPower
            let label = isPower ? "BIKE POWER" : "PEDAL CADENCE"
            let sensorUnit = isPower ? "W" : "rpm"
            guard snapshot.sport == .cycling, !snapshot.isPaused,
                  let sample = isPower ? snapshot.cyclingPower : snapshot.cyclingCadence else {
                return none(label, unit: sensorUnit, why: "no cycling sensor reading")
            }
            let value = sample.formatted(.number.precision(.fractionLength(0)))
            return DisplayReading(metric: self, value: value, unit: sensorUnit, label: label,
                                  spoken: "\(name), \(value) \(isPower ? "watts" : "revolutions per minute")")
        case .runningPower:
            guard let watts = snapshot.runningPower else { return none("POWER", unit: "W", symbol: "bolt.fill", tint: .accent, why: "needs Apple Watch") }
            let value = "\(Int(watts.rounded()))"
            return DisplayReading(metric: self, value: value, unit: "W", label: "POWER", symbol: "bolt.fill", tint: .accent, spoken: "Running power, \(value) watts")

        case .altitude:
            guard let meters = snapshot.altitude else { return none("ALTITUDE", unit: heightUnit) }
            let value = height(meters)
            return DisplayReading(metric: self, value: value, unit: heightUnit, label: "ALTITUDE", spoken: "Altitude, \(value) \(unit.spokenHeightUnit)")
        case .grade:
            guard let grade = snapshot.grade, !snapshot.isPaused else { return none("GRADE", unit: "%") }
            let percent = Int((grade * 100).rounded())
            let value = percent > 0 ? "+\(percent)" : percent < 0 ? "−\(-percent)" : "0"
            return DisplayReading(metric: self, value: value, unit: "%", label: "GRADE", spoken: "Grade, \(percent) percent")
        case .verticalSpeed:
            guard let perHour = snapshot.verticalSpeed, !snapshot.isPaused else { return none("VERT SPEED", unit: "\(heightUnit)/h") }
            let amount = Int(unit.height(fromMeters: perHour).rounded())
            let value = abs(amount).formatted()
            // The barometer wobbles on flat ground, so small amounts read as level rather than flicking
            // between climbing and descending.
            if abs(amount) < (unit == .miles ? 100 : 30) {
                return DisplayReading(
                    metric: self,
                    value: value,
                    unit: "\(heightUnit)/h",
                    label: "LEVEL",
                    symbol: "arrow.left.and.right",
                    tint: .accent,
                    spoken: "Vertical speed, level"
                )
            }
            return DisplayReading(
                metric: self,
                value: value,
                unit: "\(heightUnit)/h",
                label: amount < 0 ? "DESCENDING" : "CLIMBING",
                symbol: amount < 0 ? "arrow.down" : "arrow.up",
                tint: .accent,
                spoken: "\(amount < 0 ? "Descending" : "Climbing") \(value) \(unit.spokenHeightUnit) an hour"
            )

        case .timeOfDay:
            let value = snapshot.date.formatted(date: .omitted, time: .shortened)
            return DisplayReading(metric: self, value: value, label: "TIME", spoken: "The time is \(value)")
        case .totalTime:
            let seconds = snapshot.startDate.map { snapshot.date.timeIntervalSince($0) } ?? snapshot.elapsed
            let value = RunFormat.duration(seconds)
            return DisplayReading(metric: self, value: value, label: "TOTAL TIME", spoken: "Total time, \(value)")
        case .daylight:
            guard let event = snapshot.sunEvent else {
                // With a fix, the sun just doesn't rise or set in the next two days, as near the poles.
                let why = snapshot.metersToStart == nil ? "after the first GPS fix" : "no sunrise or sunset in the next two days"
                return none("DAYLIGHT", symbol: "sun.max.fill", tint: .accent, why: why)
            }
            let value = Self.hoursAndMinutes(event.date.timeIntervalSince(snapshot.date))
            return DisplayReading(
                metric: self,
                value: value,
                label: event.isSunset ? "TO SUNSET" : "TO SUNRISE",
                symbol: event.isSunset ? "sunset.fill" : "sunrise.fill",
                tint: .accent,
                spoken: "\(value) to \(event.isSunset ? "sunset" : "sunrise")"
            )
        case .distanceToStart:
            guard let meters = snapshot.metersToStart else { return none("TO START", unit: unit.symbol) }
            let value = Self.shortDistance(meters, unit: unit)
            return DisplayReading(metric: self, value: value.number, unit: value.unit, label: "TO START", spoken: "\(value.number) \(value.unit) to the start")
        case .strideLength:
            guard !snapshot.isPaused, let pace = snapshot.currentPace, pace > 0, let cadence = snapshot.cadence, cadence > 0 else {
                return none("STRIDE", unit: heightUnit)
            }
            // Meters a second over steps a second.
            let meters = (1_000 / pace) / (cadence / 60)
            let value = unit == .miles
                ? (meters / DistanceUnit.metersPerFoot).formatted(.number.precision(.fractionLength(1)))
                : meters.formatted(.number.precision(.fractionLength(2)))
            return DisplayReading(metric: self, value: value, unit: heightUnit, label: "STRIDE", spoken: "Stride, \(value) \(unit.spokenHeightUnit)")
        }
    }

    /// "5 minutes 2 seconds per kilometer" for VoiceOver, or "none yet", rather than the screen's
    /// "5:02 per km" or a dash read out as punctuation.
    static func spokenPace(_ seconds: TimeInterval?, unit: DistanceUnit) -> String {
        SpokenFormat.pace(seconds, unit: unit) ?? "none yet"
    }

    /// The pace the same effort makes on flat ground: faster than `pace` uphill, slower on gentle downhills,
    /// from Minetti's running costs. Slopes past 30% count as 30%.
    static func gradeAdjusted(_ pace: TimeInterval, grade: Double) -> TimeInterval {
        let slope = min(0.3, max(-0.3, grade))
        return pace * EnergyCost.running(grade: 0) / EnergyCost.running(grade: slope)
    }

    /// "1h 12m" or "48m".
    static func hoursAndMinutes(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.down))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// Meters or feet up close, then kilometers or miles: "400 m", "1.25 km", "850 ft", "0.62 mi". Distance
    /// still to go passes `.up`, so it never reads 0 before it's done.
    static func shortDistance(_ meters: Double, unit: DistanceUnit, rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> (number: String, unit: String) {
        switch unit {
        case .kilometers where meters < 1_000:
            return ("\(Int(meters.rounded(rounding)))", "m")
        case .miles where meters < 0.1 * unit.meters:
            return ("\(Int((meters / DistanceUnit.metersPerFoot).rounded(rounding)))", "ft")
        default:
            return (RunFormat.distance(meters, unit: unit, withUnit: false, rounding: rounding), unit.symbol)
        }
    }
}

extension RunSnapshot {
    /// A run well under way with every number filled in, for showing what a display screen looks like.
    static func sample(unit: DistanceUnit, date: Date = .now, sport: WorkoutSport = .running) -> RunSnapshot {
        var snapshot = RunSnapshot(
            elapsed: 2_968,
            meters: 9_412,
            unit: unit,
            currentPace: 302,
            averagePace: 315,
            beatsPerMinute: 152,
            heightFromStart: 43,
            cadence: 172
        )
        snapshot.date = date
        snapshot.startDate = date.addingTimeInterval(-3_052)
        // A round goal in either unit, as a Distance Run's is.
        snapshot.goalMeters = unit == .miles ? 10 * unit.meters : 15_000
        snapshot.paceTarget = 305...325
        snapshot.splitPace = 298
        snapshot.lastSplit = unit == .miles ? 497 : 308
        snapshot.rollingPace = 300
        snapshot.step = StepReading(name: "Work", remaining: .time(157), inStep: 23)
        snapshot.heartRateMax = 188
        snapshot.averageHeartRate = 146
        snapshot.totalAscent = 186
        snapshot.totalDescent = 143
        snapshot.altitude = 312
        snapshot.grade = 0.04
        snapshot.verticalSpeed = 480
        snapshot.calories = 642
        snapshot.sunEvent = SunTimes.Event(isSunset: true, date: date.addingTimeInterval(4_330))
        snapshot.metersToStart = 3_120
        snapshot.runningPower = 248
        if sport == .cycling {
            snapshot.sport = .cycling
            snapshot.meters = 22_260
            snapshot.currentPace = 120
            snapshot.averagePace = 133.33
            snapshot.goalMeters = nil
            snapshot.paceTarget = nil
            snapshot.cadence = nil
            snapshot.runningPower = nil
            snapshot.cyclingCadence = 88
            snapshot.cyclingPower = 204
        }
        return snapshot
    }
}
