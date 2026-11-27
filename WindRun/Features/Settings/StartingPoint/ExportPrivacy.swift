//
//  ExportPrivacy.swift
//  Wind Run
//
//  What Export Runs hides from `gps_points.csv`, set in Settings → Your Data → Starting Point.
//

import CoreLocation
import Foundation

/// Which GPS points an export leaves out: those near where each run started and finished, or those near
/// places the runner pinned on a map, such as home or work. Runs often start and finish at home, and the
/// gaps and pauses near it could help someone who knows the area find it.
///
/// Kept as three settings, synced to iCloud with the rest (`CloudSettings`). Pins are places the runner
/// chose, kept like their routes: on this iPhone, and in their private iCloud when iCloud Sync is on. They
/// never go in an export or a trace.
nonisolated struct ExportPrivacy: Equatable, Sendable {
    nonisolated enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// Around the first and last GPS point of each run.
        case startAndFinish = "ends"
        /// Around each pin.
        case pins

        var id: Self { self }

        var title: String {
            switch self {
            case .startAndFinish: "Start and Finish"
            case .pins: "Pinned Places"
            }
        }

        var detail: String {
            switch self {
            case .startAndFinish: "Hides the first and last stretch of every run."
            case .pins: "Hides the area around places you pin, such as home or work."
            }
        }

        var systemImage: String {
            switch self {
            case .startAndFinish: "flag.pattern.checkered"
            case .pins: "mappin.and.ellipse"
            }
        }
    }

    /// A place the runner pinned. Its id only tells pins apart on this screen.
    nonisolated struct Pin: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var latitude: Double
        var longitude: Double

        init(id: UUID = UUID(), _ coordinate: CLLocationCoordinate2D) {
            self.id = id
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var location: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }
    }

    static let modeKey = "exportPrivacy.mode"
    static let metersKey = "exportPrivacy.meters"
    static let pinsKey = "exportPrivacy.pins"
    static let syncedKeys = [modeKey, metersKey, pinsKey]

    static let defaultMeters: CLLocationDistance = 250
    /// The slider's ends. Never less than 100 m, so a start or a pin is always hidden by some margin.
    static let meterRange: ClosedRange<CLLocationDistance> = 100...1_000
    static let meterStep: CLLocationDistance = 50
    /// Plenty for home, work and a few friends, and small enough for iCloud's settings store.
    static let pinLimit = 20

    var mode: Mode = .startAndFinish
    /// How far around each start, finish or pin points are hidden. Tests set it below the slider's range.
    var meters: CLLocationDistance = ExportPrivacy.defaultMeters
    var pins: [Pin] = []

    /// The built-in setting: 250 m around each start and finish.
    static let standard = ExportPrivacy()

    /// Hides `meters` around each start and finish.
    static func startAndFinish(_ meters: CLLocationDistance) -> ExportPrivacy {
        ExportPrivacy(mode: .startAndFinish, meters: meters)
    }

    /// Whether pins are what's hidden. With no pins yet the start and finish still are, so picking Pinned
    /// Places never leaves a run's ends in an export.
    var usesPins: Bool {
        mode == .pins && !pins.isEmpty
    }

    /// The places to hide points around, for a run that started at `first` and finished at `last`.
    func centers(first: CLLocation?, last: CLLocation?) -> [CLLocation] {
        usesPins ? pins.map(\.location) : [first, last].compactMap { $0 }
    }

    /// Whether `location` is far enough from every center to go in an export.
    func shows(_ location: CLLocation, centers: [CLLocation]) -> Bool {
        centers.allSatisfy { location.distance(from: $0) >= meters }
    }

    // MARK: Stored

    static func load(from defaults: UserDefaults = .standard) -> ExportPrivacy {
        var privacy = ExportPrivacy()
        if let mode = defaults.string(forKey: modeKey).flatMap(Mode.init(rawValue:)) {
            privacy.mode = mode
        }
        if let meters = defaults.object(forKey: metersKey) as? Double, meters.isFinite {
            privacy.meters = clamped(meters)
        }
        if let data = defaults.data(forKey: pinsKey),
           let pins = try? JSONDecoder().decode([Pin].self, from: data) {
            privacy.pins = Array(pins.filter { CLLocationCoordinate2DIsValid($0.coordinate) }.prefix(pinLimit))
        }
        return privacy
    }

    /// Saves only what changed, so iCloud isn't sent the same values again.
    func save(to defaults: UserDefaults = .standard) {
        let saved = Self.load(from: defaults)
        if saved.mode != mode || defaults.object(forKey: Self.modeKey) == nil {
            defaults.set(mode.rawValue, forKey: Self.modeKey)
        }
        if saved.meters != meters || defaults.object(forKey: Self.metersKey) == nil {
            defaults.set(Self.clamped(meters), forKey: Self.metersKey)
        }
        if saved.pins != pins {
            if pins.isEmpty {
                defaults.removeObject(forKey: Self.pinsKey)
            } else if let data = try? JSONEncoder().encode(Array(pins.prefix(Self.pinLimit))) {
                defaults.set(data, forKey: Self.pinsKey)
            }
        }
    }

    /// `meters` on the slider's range and steps.
    static func clamped(_ meters: CLLocationDistance) -> CLLocationDistance {
        let stepped = (meters / meterStep).rounded() * meterStep
        return min(max(stepped, meterRange.lowerBound), meterRange.upperBound)
    }

    // MARK: Text

    /// "250 m", or "820 ft" for a runner using miles, to the nearest 10 ft.
    @MainActor static func text(_ meters: CLLocationDistance, unit: DistanceUnit) -> String {
        switch unit {
        case .kilometers:
            "\(Int(meters.rounded()).formatted()) m"
        case .miles:
            "\((Int((meters / 0.3048 / 10).rounded()) * 10).formatted()) ft"
        }
    }

    /// What `gps_points.csv` leaves out, for the export's choices.
    @MainActor func leftOutText(unit: DistanceUnit) -> String {
        let distance = Self.text(meters, unit: unit)
        if usesPins {
            return "skip readings within \(distance) of your pinned places"
        }
        return "skip readings within \(distance) of your start or finish"
    }
}
