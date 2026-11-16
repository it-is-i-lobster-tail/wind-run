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
        }
    }
}

/// What a run screen shows, wherever it's shown: two headline numbers, the biggest first, and four
/// smaller ones in a 2×2 grid. The Watch, the iPhone run screen and the Lock Screen each lay it out to
/// fit, but always show the same six things.
///
/// Every runner has `standard` for now. Screens are values that can be stored, so a runner can later edit
/// one, or keep several and switch between them.
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
        primary = try container.decode(DisplayMetric.self, forKey: .primary)
        secondary = try container.decode(DisplayMetric.self, forKey: .secondary)
        tiles = Self.filled(try container.decode([DisplayMetric].self, forKey: .tiles))
    }

    /// Every spot in order: the two headlines, then the grid.
    var metrics: [DisplayMetric] { [primary, secondary] + tiles }

    /// The screen every runner starts with: time and distance, then pace, heart rate, elevation and cadence.
    static let standard = DisplayScreen(
        id: UUID(uuidString: "6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F")!,
        name: "Standard",
        primary: .elapsed,
        secondary: .distance,
        tiles: [.currentPace, .heartRate, .heightFromStart, .cadence]
    )

    /// The screen the run shows. Always `standard` until runners can pick their own.
    static var current: DisplayScreen { standard }

    /// Exactly `tileCount` tiles: extra ones dropped, missing ones filled from the standard grid.
    private static func filled(_ tiles: [DisplayMetric]) -> [DisplayMetric] {
        let fallback: [DisplayMetric] = [.currentPace, .heartRate, .heightFromStart, .cadence]
        return (0..<tileCount).map { tiles.indices.contains($0) ? tiles[$0] : fallback[$0] }
    }
}

/// One spot on the screen as it reads right now, already worded, so every device lays out the same words.
/// The app and the Watch write these; the Live Activity only lays them out.
nonisolated struct DisplayReading: Codable, Hashable, Sendable {
    /// Which colour a reading's symbol takes. Red is only for heart rate.
    enum Tint: String, Codable, Sendable {
        case accent
        case heartRate
    }

    var metric: DisplayMetric
    /// "32:48", "6.40", "5:12", "148", or a dash with nothing to show.
    var value: String
    /// "km", "min/km", "bpm", "m", "spm".
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
