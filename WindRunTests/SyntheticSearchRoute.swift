import Foundation
@testable import WindRun

enum SyntheticSearchRoute: String, Decodable, CaseIterable {
    case flat, noisyFlat, rolling, climb, descent, outBack, unknown

    // Use real timestamped GPS fixes for a recorded segment of each fictional workout.
    func record(on run: Run, meters: Double, seconds: Double) {
        guard self != .unknown, meters > 0 else { return }
        let length = min(meters, 1000)
        let steps = max(2, 2 * Int(ceil(length / 40)))
        for i in 0...steps {
            let travel = Double(i) * length / Double(steps)
            let north = self == .outBack ? min(travel, length - travel) : travel
            let height: Double
            switch self {
            case .flat, .unknown: height = 0
            case .noisyFlat: height = i.isMultiple(of: 2) ? 3 : -3
            case .rolling: height = 2 * sin(travel / 100)
            case .climb, .outBack: height = north * 0.09
            case .descent: height = -travel * 0.09
            }
            run.record(RouteSample(timestamp: run.startDate.addingTimeInterval(travel / meters * seconds),
                                   latitude: 42 + north / 111_100, longitude: -72,
                                   altitude: 150 + height, horizontalAccuracy: 3, verticalAccuracy: 4))
        }
    }
}
