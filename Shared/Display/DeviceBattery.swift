//
//  DeviceBattery.swift
//  Wind Run
//

import Foundation
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// The battery of the device recording the run, for the run screen.
enum DeviceBattery {
    /// Asks the system to report the battery level. Call it when a run starts.
    static func startMonitoring() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #elseif os(watchOS)
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        #endif
    }

    /// From 0 to 1, or nil when the system doesn't say, as in the simulator.
    static var level: Double? {
        #if os(iOS)
        let level = Double(UIDevice.current.batteryLevel)
        #elseif os(watchOS)
        let level = Double(WKInterfaceDevice.current().batteryLevel)
        #else
        let level = -1.0
        #endif
        return level >= 0 ? level : nil
    }
}
