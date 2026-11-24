import Foundation

/// The activity performed, independent of how the workout is structured or started.
nonisolated enum WorkoutSport: String, CaseIterable, Identifiable, Codable {
    case running
    case cycling

    var id: Self { self }

    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .running
    }

    var name: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        }
    }

    var noun: String { self == .cycling ? "ride" : "run" }

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        }
    }
}
