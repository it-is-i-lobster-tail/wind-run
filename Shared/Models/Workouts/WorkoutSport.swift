import Foundation

/// The activity performed, independent of how the workout is structured or started.
nonisolated enum WorkoutSport: String, CaseIterable, Identifiable, Codable {
    case running
    case cycling
    case hiking

    var id: Self { self }

    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .running
    }

    var name: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .hiking: "Hike"
        }
    }

    var noun: String {
        switch self {
        case .running: "run"
        case .cycling: "ride"
        case .hiking: "hike"
        }
    }

    var openDisplayKind: DisplayRunKind {
        switch self {
        case .running: .free
        case .cycling: .cycling
        case .hiking: .hike
        }
    }

    static func isHikeName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Hike") == .orderedSame
    }

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .hiking: "figure.hiking"
        }
    }
}
