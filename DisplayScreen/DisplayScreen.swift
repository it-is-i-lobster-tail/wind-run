//
//  DisplayScreen.swift
//  Wind Run
//
//  Shared by the iPhone app, the Watch app and the Live Activity, so all three show the same numbers.
//

import Foundation

/// One thing a run screen can show in one of its spots.
nonisolated enum DisplayMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Time running, leaving out pauses.
    case elapsed
    case distance
    /// The last 30 seconds of running.
    case currentPace
    /// The whole run so far.
    case averagePace
    case heartRate
    /// How far above or below the start the runner is now.
    case heightFromStart
    /// Steps a minute.
    case cadence
    /// The pace of the kilometer or mile under way.
    case splitPace
    /// How long the last whole kilometer or mile took.
    case lastSplit
    /// The pace over the last half kilometer or half mile.
    case rollingPace
    /// What's left of the interval or coach step under way.
    case stepLeft
    /// What's left of the run's goal distance or time.
    case goalLeft
    /// The finish time at the average pace so far, or the distance by the end of a timed run.
    case projectedFinish
    /// How far ahead of or behind the target pace's clock the runner is.
    case aheadBehind
    /// Which of five heart rate zones the runner is in.
    case heartRateZone
    case averageHeartRate
    /// All the climbing so far.
    case totalAscent
    /// All the dropping so far.
    case totalDescent
    /// Height above sea level.
    case altitude
    /// How steep the ground is now, as a percent.
    case grade
    /// How fast the runner is climbing or dropping, per hour.
    case verticalSpeed
    /// The pace the same effort would make on flat ground.
    case gradeAdjustedPace
    case timeOfDay
    /// Time since Start, pauses and all.
    case totalTime
    case calories
    /// The battery of the device running the run.
    case battery
    /// Time to sunset, or to sunrise in the dark.
    case daylight
    /// Straight-line distance back to where the run started.
    case distanceToStart
    case strideLength
    /// Watts, from Apple Watch.
    case runningPower

    var id: Self { self }

    /// The name a runner picks it by: "Current pace".
    var name: String {
        switch self {
        case .elapsed: "Elapsed time"
        case .distance: "Distance"
        case .currentPace: "Current pace"
        case .averagePace: "Average pace"
        case .heartRate: "Heart rate"
        case .heightFromStart: "Elevation from start"
        case .cadence: "Cadence"
        case .splitPace: "Split pace"
        case .lastSplit: "Last split"
        case .rollingPace: "Rolling pace"
        case .stepLeft: "Left in step"
        case .goalLeft: "Left to goal"
        case .projectedFinish: "Projected finish"
        case .aheadBehind: "Ahead or behind"
        case .heartRateZone: "Heart rate zone"
        case .averageHeartRate: "Average heart rate"
        case .totalAscent: "Total ascent"
        case .totalDescent: "Total descent"
        case .altitude: "Altitude"
        case .grade: "Grade"
        case .verticalSpeed: "Vertical speed"
        case .gradeAdjustedPace: "Grade-adjusted pace"
        case .timeOfDay: "Time of day"
        case .totalTime: "Total time"
        case .calories: "Calories"
        case .battery: "Battery"
        case .daylight: "Daylight left"
        case .distanceToStart: "Distance to start"
        case .strideLength: "Stride length"
        case .runningPower: "Running power"
        }
    }

    /// One line on what it shows, for picking it.
    var summary: String {
        switch self {
        case .elapsed: "Time running, leaving out pauses."
        case .distance: "How far you've run."
        case .currentPace: "Your pace over the last 30 seconds."
        case .averagePace: "Your pace over the whole run."
        case .heartRate: "Your heart rate right now."
        case .heightFromStart: "How far above or below the start you are."
        case .cadence: "Steps a minute. Needs Steps and cadence on in Settings."
        case .splitPace: "Your pace for the kilometer or mile you're in. Steadier than current pace."
        case .lastSplit: "How long the last whole kilometer or mile took."
        case .rollingPace: "Your pace over the last half kilometer or half mile."
        case .stepLeft: "What's left of the interval or coach step you're on."
        case .goalLeft: "What's left of today's distance or time."
        case .projectedFinish: "Your finish time at your average pace, or how far you'll get on a timed run."
        case .aheadBehind: "How far ahead of or behind the coach's target pace you are."
        case .heartRateZone: "Which of five zones your heart rate is in, from your highest heart rate. Needs a run with heart rate first."
        case .averageHeartRate: "Your average heart rate for the run."
        case .totalAscent: "All the climbing since the start."
        case .totalDescent: "All the dropping since the start."
        case .altitude: "Your height above sea level."
        case .grade: "How steep the ground is right now."
        case .verticalSpeed: "How fast you're climbing or dropping, per hour."
        case .gradeAdjustedPace: "Your pace as if the ground were flat, so climbs don't read as slow."
        case .timeOfDay: "The time on the clock."
        case .totalTime: "Time since you pressed Start, pauses and all."
        case .calories: "Calories burned so far, counting the hills. Needs your weight in Settings."
        case .battery: "Battery left on the device you're running with."
        case .daylight: "Time until sunset, or until sunrise when it's dark. Worked out on your device."
        case .distanceToStart: "Straight-line distance back to where you started."
        case .strideLength: "How far each step carries you. Needs Steps and cadence on in Settings."
        case .runningPower: "Your running power in watts, from Apple Watch."
        }
    }

    /// The group it's listed under when picking.
    var category: DisplayMetricCategory {
        switch self {
        case .elapsed, .totalTime, .timeOfDay, .daylight: .time
        case .distance, .currentPace, .averagePace, .splitPace, .lastSplit, .rollingPace, .distanceToStart: .distanceAndPace
        case .stepLeft, .goalLeft, .projectedFinish, .aheadBehind: .goal
        case .heartRate, .averageHeartRate, .heartRateZone, .calories, .runningPower: .effort
        case .heightFromStart, .altitude, .totalAscent, .totalDescent, .grade, .verticalSpeed, .gradeAdjustedPace: .hills
        case .cadence, .strideLength: .form
        case .battery: .device
        }
    }
}

/// The groups the metrics are listed in, in order.
nonisolated enum DisplayMetricCategory: String, CaseIterable, Identifiable, Sendable {
    case time
    case distanceAndPace
    case goal
    case effort
    case hills
    case form
    case device

    var id: Self { self }

    var name: String {
        switch self {
        case .time: "Time"
        case .distanceAndPace: "Distance and pace"
        case .goal: "Goal and workout"
        case .effort: "Heart and effort"
        case .hills: "Hills"
        case .form: "Form"
        case .device: "Device"
        }
    }

    var metrics: [DisplayMetric] { DisplayMetric.allCases.filter { $0.category == self } }
}

/// What a run screen shows, wherever it's shown: two headline numbers, the biggest first, and four
/// smaller ones in a 2×2 grid. The Watch, the iPhone run screen and the Lock Screen each lay it out to
/// fit, but always show the same six things.
///
/// Screens are values that can be stored: the runner keeps several in `DisplayLibrary`, edits each one, and
/// picks which one a run shows. Every runner starts with `standard`.
nonisolated struct DisplayScreen: Codable, Hashable, Identifiable, Sendable {
    /// The grid holds this many.
    static let tileCount = 4

    var id: UUID
    var name: String
    /// The biggest number on the screen.
    var primary: DisplayMetric
    /// The second biggest.
    var secondary: DisplayMetric
    /// The 2×2 grid, left to right, then top to bottom. Always `tileCount` long.
    var tiles: [DisplayMetric] {
        didSet { tiles = Self.filled(tiles) }
    }

    init(id: UUID = UUID(), name: String, primary: DisplayMetric, secondary: DisplayMetric, tiles: [DisplayMetric]) {
        self.id = id
        self.name = name
        self.primary = primary
        self.secondary = secondary
        self.tiles = Self.filled(tiles)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let primaryName = try container.decode(String.self, forKey: .primary)
        let secondaryName = try container.decode(String.self, forKey: .secondary)
        let tileNames = try container.decode([String].self, forKey: .tiles)
        let names = [primaryName, secondaryName] + (0..<Self.tileCount).map { tileNames.indices.contains($0) ? tileNames[$0] : nil }
        let metrics = Self.unique(names.map { $0.flatMap(DisplayMetric.init(rawValue:)) })
        primary = metrics[0]
        secondary = metrics[1]
        tiles = Array(metrics.dropFirst(2))
    }

    /// The six spots with each one different. A metric from a newer version of the app, synced from another
    /// device, or one that's already in an earlier spot, takes the standard screen's metric for that spot,
    /// or else the first one not on the screen yet, rather than losing the whole screen.
    static func unique(_ spots: [DisplayMetric?]) -> [DisplayMetric] {
        var spots = spots
        var shown = Set<DisplayMetric>()
        for index in spots.indices {
            guard let metric = spots[index] else { continue }
            if shown.contains(metric) {
                spots[index] = nil
            } else {
                shown.insert(metric)
            }
        }
        let standard = Self.standard.metrics
        return spots.indices.map { index in
            if let metric = spots[index] { return metric }
            let candidates = (standard.indices.contains(index) ? [standard[index]] : []) + standard + DisplayMetric.allCases
            let pick = candidates.first { !shown.contains($0) } ?? .elapsed
            shown.insert(pick)
            return pick
        }
    }

    /// How many of `names` this version of the app doesn't know, for the trace.
    static func unknownMetrics(in data: Data) -> Int {
        struct Names: Decodable {
            let primary: String
            let secondary: String
            let tiles: [String]
        }
        guard let names = try? JSONDecoder().decode(Names.self, from: data) else { return 0 }
        return ([names.primary, names.secondary] + names.tiles.prefix(tileCount)).filter { DisplayMetric(rawValue: $0) == nil }.count
    }

    /// Every spot in order: the two headlines, then the grid.
    var metrics: [DisplayMetric] { [primary, secondary] + tiles }

    /// The screen every runner starts with: time and distance, then pace, heart rate, elevation and cadence.
    static let standard = DisplayScreen(
        id: UUID(uuidString: "6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F")!,
        name: "Standard",
        primary: .elapsed,
        secondary: .distance,
        tiles: standardTiles
    )

    /// Standard's grid, kept apart from `standard` so `filled(_:)`, which `standard`'s own init calls, can
    /// read it.
    private static let standardTiles: [DisplayMetric] = [.currentPace, .heartRate, .heightFromStart, .cadence]

    /// Where the one display screen was kept as JSON text before saved displays (`DisplayLibrary`). The library
    /// still writes its default here for older versions, and reads it until its own list is first saved.
    /// Reading and saving it are in Shared, where the app and the Watch can trace a problem.
    static let storageKey = "displayScreen"

    /// The metric in `slot`.
    subscript(slot: DisplaySlot) -> DisplayMetric {
        get {
            switch slot {
            case .primary: primary
            case .secondary: secondary
            case .tile(let index): tiles[index]
            }
        }
        set {
            switch slot {
            case .primary: primary = newValue
            case .secondary: secondary = newValue
            case .tile(let index): tiles[index] = newValue
            }
        }
    }

    /// Puts `metric` in `slot`. When it's already in another spot, the two swap, so nothing shows twice.
    mutating func place(_ metric: DisplayMetric, in slot: DisplaySlot) {
        let old = self[slot]
        if let other = self.slot(showing: metric, otherThan: slot) {
            self[other] = old
        }
        self[slot] = metric
    }

    /// The spot other than `slot` that shows `metric`, or nil when none does. Placing `metric` in `slot`
    /// swaps the two.
    func slot(showing metric: DisplayMetric, otherThan slot: DisplaySlot) -> DisplaySlot? {
        DisplaySlot.all.first { $0 != slot && self[$0] == metric }
    }

    /// Puts Standard's six back, keeping the display's name and id.
    mutating func reset() {
        primary = DisplayScreen.standard.primary
        secondary = DisplayScreen.standard.secondary
        tiles = DisplayScreen.standard.tiles
    }

    /// Whether the six spots are Standard's.
    var hasStandardSpots: Bool { metrics == Self.standard.metrics }

    /// Exactly `tileCount` tiles: extra ones dropped, missing ones filled from the standard grid.
    private static func filled(_ tiles: [DisplayMetric]) -> [DisplayMetric] {
        (0..<tileCount).map { tiles.indices.contains($0) ? tiles[$0] : standardTiles[$0] }
    }
}

/// One of the six spots on a display screen.
nonisolated enum DisplaySlot: Hashable, Identifiable, Sendable {
    case primary
    case secondary
    /// The grid, 0 to 3: left to right, then top to bottom.
    case tile(Int)

    static let all: [DisplaySlot] = [.primary, .secondary] + (0..<DisplayScreen.tileCount).map { .tile($0) }

    var id: String {
        switch self {
        case .primary: "primary"
        case .secondary: "secondary"
        case .tile(let index): "tile\(index)"
        }
    }

    /// "Main number", "Second number", "Top left"…
    var name: String {
        switch self {
        case .primary: "Main number"
        case .secondary: "Second number"
        case .tile(0): "Top left"
        case .tile(1): "Top right"
        case .tile(2): "Bottom left"
        case .tile(_): "Bottom right"
        }
    }

    /// The spot in a sentence: "the main number", "the top left spot".
    var phrase: String {
        switch self {
        case .primary, .secondary: "the \(name.lowercased())"
        case .tile: "the \(name.lowercased()) spot"
        }
    }
}

/// One spot on the screen as it reads right now, already worded, so every device lays out the same words.
/// The app and the Watch write these; the Live Activity only lays them out.
nonisolated struct DisplayReading: Codable, Hashable, Sendable {
    /// Which colour a reading's symbol takes. Red is only for heart rate.
    enum Tint: String, Codable, Sendable {
        case accent
        case heartRate
        /// Heart rate zones 1 to 5, each its own colour.
        case zone1, zone2, zone3, zone4, zone5

        static func zone(_ number: Int) -> Tint {
            switch number {
            case ...1: .zone1
            case 2: .zone2
            case 3: .zone3
            case 4: .zone4
            default: .zone5
            }
        }
    }

    var metric: DisplayMetric
    /// "32:48", "6.40", "5:12", "148", or a dash with nothing to show.
    var value: String
    /// "km", "/km", "bpm", "m", "spm".
    var unit: String?
    /// The caption: "ELAPSED", "PACE", "BELOW START".
    var label: String
    /// An SF Symbol before the value, such as the heart for heart rate.
    var symbol: String?
    var tint: Tint?
    /// For elapsed time while the run is going: when its clock started, so a screen that isn't redrawn every
    /// second, like the Lock Screen, can count on its own.
    var clockStart: Date?
    /// Shown quieter, such as the time while paused.
    var isDimmed = false
    /// What VoiceOver says: "Heart rate, 148 beats per minute".
    var spoken: String
}

/// A whole screen as it reads right now.
nonisolated struct DisplayScreenReadings: Codable, Hashable, Sendable {
    var primary: DisplayReading
    var secondary: DisplayReading
    var tiles: [DisplayReading]
}
