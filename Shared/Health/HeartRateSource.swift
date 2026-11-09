//
//  HeartRateSource.swift
//  Wind Run
//

import Foundation
import HealthKit

/// What measured a heart-rate reading, found from the reading itself so the runner never has to say.
///
/// When more than one is worn, the best one wins: a strap or other sensor, then Apple Watch, then
/// AirPods or Powerbeats. The raw values match the coach's `HeartRateDevice`.
nonisolated enum HeartRateSource: String, Codable, CaseIterable {
    /// A Bluetooth chest strap or another sensor paired in Settings.
    case strapOrSensor = "chestStrap"
    case appleWatch
    /// AirPods Pro 3 or Powerbeats Pro 2.
    case earbuds

    /// Higher is better.
    var rank: Int {
        switch self {
        case .strapOrSensor: 3
        case .appleWatch: 2
        case .earbuds: 1
        }
    }

    /// The best of some sources, or nil when there are none.
    static func best(_ sources: some Sequence<HeartRateSource>) -> HeartRateSource? {
        sources.max { $0.rank < $1.rank }
    }

    /// What a HealthKit reading came from, or nil when it can't tell.
    ///
    /// Earbuds are named in the device. A device from another maker is a strap or sensor, even when an
    /// Apple Watch passed it on. Otherwise a reading from a watch, or saved by one, is the watch's own.
    init?(_ sample: HKSample) {
        let device = sample.device
        self.init(
            deviceName: device?.name,
            deviceModel: device?.model,
            manufacturer: device?.manufacturer,
            productType: sample.sourceRevision.productType
        )
    }

    init?(deviceName: String?, deviceModel: String?, manufacturer: String?, productType: String?) {
        let names = [deviceName, deviceModel].compactMap { $0?.lowercased() }
        let maker = manufacturer?.lowercased() ?? ""
        if names.contains(where: { $0.contains("airpods") || $0.contains("beats") }) || maker.contains("beats") {
            self = .earbuds
        } else if !maker.isEmpty, !maker.contains("apple") {
            self = .strapOrSensor
        } else if names.contains(where: { $0.contains("watch") }) || productType?.hasPrefix("Watch") == true {
            self = .appleWatch
        } else {
            return nil
        }
    }
}
