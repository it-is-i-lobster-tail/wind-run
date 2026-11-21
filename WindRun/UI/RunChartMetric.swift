import Foundation

enum RunChartMetric: String, CaseIterable {
    case pace = "Pace", heart = "Heart rate", cadence = "Cadence", elevation = "Elevation"

    var distributionExplanation: String {
        switch self {
        case .pace: "Pick a pace to see the percentage of readings that were that fast or faster. A steep rise means many readings fell in a narrow pace range."
        case .heart: "Pick a heart rate to see what percentage of readings were at that rate or lower."
        case .cadence: "The 50% line marks the median step rate. A steep rise means many readings clustered around the same cadence."
        case .elevation: "Pick a height to see the percentage of elevation readings taken at that height or lower."
        }
    }

    func unit(_ distance: DistanceUnit) -> String {
        switch self {
        case .pace: "min/\(distance.symbol)"
        case .heart: "bpm"
        case .cadence: "spm"
        case .elevation: distance.heightSymbol
        }
    }

    func measuredValue(_ raw: Double, unit: DistanceUnit) -> Double {
        switch self {
        case .pace: unit.perUnit(raw)
        case .elevation: unit.height(fromMeters: raw)
        default: raw
        }
    }

    /// Faster pace is higher on a run timeline. Distribution thresholds use the measured value.
    func value(_ raw: Double, unit: DistanceUnit) -> Double {
        let measured = measuredValue(raw, unit: unit)
        return self == .pace ? -measured : measured
    }

    func label(_ plotted: Double) -> String {
        self == .pace ? RunFormat.duration(abs(plotted)) : Int(plotted.rounded()).formatted()
    }
}
