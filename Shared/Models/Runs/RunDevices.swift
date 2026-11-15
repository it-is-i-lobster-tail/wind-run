//
//  RunDevices.swift
//  Wind Run
//

import Foundation
import HealthKit

/// One device that took part in a run: what kind it is, its hardware model and its software versions.
///
/// Only the model identifier ("iPhone17,1", "Watch7,1") and version numbers are kept, never the name the
/// owner gave the device or anything else that could identify them.
nonisolated struct DeviceInfo: Codable, Hashable {
    enum Kind: String, Codable {
        case iPhone
        case appleWatch
        /// A Bluetooth chest strap or another sensor paired in Settings.
        case strapOrSensor
        /// AirPods Pro 3 or Powerbeats Pro 2.
        case earbuds
        case other

        var name: String {
            switch self {
            case .iPhone: "iPhone"
            case .appleWatch: "Apple Watch"
            case .strapOrSensor: "strap or sensor"
            case .earbuds: "earbuds"
            case .other: "other device"
            }
        }
    }

    var kind: Kind
    /// The hardware model identifier, such as "iPhone17,1", or a sensor's model.
    var model: String?
    /// The operating system and its version, such as "iOS 26.1.0".
    var system: String?
    /// Wind Run's version and build for an iPhone or watch running it, such as "0.2.0 (57)".
    var app: String?
    /// A sensor's maker, when it isn't Apple's.
    var manufacturer: String?
    /// A sensor's firmware or software version.
    var firmware: String?

    /// This device, running this copy of Wind Run.
    @MainActor static var current: DeviceInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(watchOS)
        let kind = Kind.appleWatch
        let systemName = "watchOS"
        #else
        let kind = Kind.iPhone
        let systemName = "iOS"
        #endif
        return DeviceInfo(
            kind: kind,
            model: modelIdentifier,
            system: "\(systemName) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            app: AppVersion.current
        )
    }

    /// The hardware model, such as "iPhone17,1". In the simulator it's the simulated device's.
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        if machine == "arm64" || machine == "x86_64" {
            return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
        }
        return machine
    }

    /// The device that measured a heart rate reading, from Health's record of it. The device's own
    /// name is left out: it's often the owner's name.
    init?(heartRateSample sample: HKSample) {
        guard let source = HeartRateSource(sample) else { return nil }
        let device = sample.device
        let revision = sample.sourceRevision
        let kind: Kind = switch source {
        case .appleWatch: .appleWatch
        case .strapOrSensor: .strapOrSensor
        case .earbuds: .earbuds
        }
        let maker = device?.manufacturer
        let isApple = maker?.lowercased().contains("apple") ?? true
        var system: String?
        if let productType = revision.productType, kind == .appleWatch {
            let version = revision.operatingSystemVersion
            let name = productType.hasPrefix("Watch") ? "watchOS" : "iOS"
            system = "\(name) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
        self.init(
            kind: kind,
            model: kind == .appleWatch ? (revision.productType ?? device?.model) : device?.model,
            system: system,
            app: nil,
            manufacturer: isApple ? nil : maker,
            // A watch's software is its watchOS, already in `system`.
            firmware: kind == .appleWatch ? nil : (device?.firmwareVersion ?? device?.softwareVersion)
        )
    }

    init(kind: Kind, model: String? = nil, system: String? = nil, app: String? = nil, manufacturer: String? = nil, firmware: String? = nil) {
        self.kind = kind
        self.model = model
        self.system = system
        self.app = app
        self.manufacturer = manufacturer
        self.firmware = firmware
    }

    /// "Apple Watch Watch7,1 watchOS 26.1.0", "iPhone iPhone17,1 iOS 26.1.0 Wind Run 0.2.0 (57)".
    var details: String {
        var parts = [kind.name]
        if let manufacturer { parts.append(manufacturer) }
        if let model { parts.append(model) }
        if let system { parts.append(system) }
        if let firmware { parts.append("firmware \(firmware)") }
        if let app { parts.append("Wind Run \(app)") }
        return parts.joined(separator: " ")
    }
}

/// The devices behind a run: the one that recorded it, the ones that measured its heart rate, and for a
/// run recorded on the watch, the iPhone that took it in.
nonisolated struct RunDevices: Codable, Hashable {
    /// The iPhone or watch that recorded the run's GPS and time.
    var recorder: DeviceInfo
    /// What measured heart rate, in the order each was first seen.
    var heartRate: [DeviceInfo] = []
    /// For a run recorded on the watch, the iPhone it was sent to.
    var receivedBy: DeviceInfo?

    /// Where the run's data came from: "iPhone", "Apple Watch", or "iPhone + Apple Watch" when the
    /// iPhone recorded it with heart rate from a watch.
    var dataFrom: String {
        var kinds: [DeviceInfo.Kind] = [recorder.kind]
        for device in heartRate where (device.kind == .iPhone || device.kind == .appleWatch) && !kinds.contains(device.kind) {
            kinds.append(device.kind)
        }
        return kinds.map(\.name).joined(separator: " + ")
    }

    /// Adds a heart rate device the first time it's seen.
    mutating func addHeartRate(_ device: DeviceInfo) {
        guard !heartRate.contains(device) else { return }
        heartRate.append(device)
    }
}
