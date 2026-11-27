import Foundation
import UIKit

/// Decides whether tagging workouts with places may go on right now. It's background work, so it waits
/// while a run is being recorded and the battery is at or below half, and while the iPhone is in Low Power
/// Mode or running hot.
@MainActor
enum PlaceTaggingGate {
    static let lowBattery: Float = 0.5

    /// Why tagging is waiting, or nil when it may go on.
    enum Wait: Equatable {
        case runOnLowBattery, lowPowerMode, hot
    }

    static func wait(runUnderWay: Bool = LiveRunLink.shared.isRunUnderWay,
                     batteryLevel: Float = currentBatteryLevel(),
                     lowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
                     thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) -> Wait? {
        // The battery level is -1 when unknown, such as in the simulator.
        if runUnderWay, batteryLevel >= 0, batteryLevel <= lowBattery { return .runOnLowBattery }
        if lowPowerMode { return .lowPowerMode }
        if thermal == .serious || thermal == .critical { return .hot }
        return nil
    }

    static func currentBatteryLevel() -> Float {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        return device.batteryLevel
    }
}
