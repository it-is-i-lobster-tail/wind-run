import Foundation

enum RunChartMetric: String, CaseIterable {
    case pace = "Pace", heart = "Heart rate", cadence = "Cadence", elevation = "Elevation"

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
