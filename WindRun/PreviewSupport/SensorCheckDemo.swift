//
//  SensorCheckDemo.swift
//  Wind Run
//

#if DEBUG
import Foundation

/// Sample checkup states for simulator screenshots, which have no heart rate, steps or real GPS. Debug
/// builds only.
///
/// - `-settingsDemo sensors -sensorCheckDemo setup`: Check Sensors with heart rate off and Motion & Fitness off.
/// - `-settingsDemo sensors -sensorCheckDemo live`: the live test part way, with readings from AirPods.
/// - `-readyChipsDemo`: the Run tab's chips with no heart rate coming in.
/// - `-runNoticeDemo` with `-activeRunDemo`: the run screen's heart rate notice tapped open.
/// - `-runDetailDemo sensors`: a run recorded with heart rate off, scrolled to its Sensors section.
enum SensorCheckDemo {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// The variant after `-sensorCheckDemo`, if it was given.
    static var variant: String? {
        guard let index = arguments.firstIndex(of: "-sensorCheckDemo") else { return nil }
        return arguments.indices.contains(index + 1) ? arguments[index + 1] : "setup"
    }

    /// Everything set up on an iPhone with AirPods in and the watch app.
    static var allGood: SensorSetup {
        SensorSetup(
            heartRateOn: true,
            health: .allowed,
            location: .allowed,
            preciseLocation: true,
            stepsOn: true,
            motionAvailable: true,
            motionAllowed: true,
            motionDenied: false,
            barometerAvailable: true,
            watch: .installed,
            earbudsConnected: true
        )
    }

    /// The Check Sensors page's sample, or nil when none was asked for.
    static var check: SensorCheck? {
        switch variant {
        case "setup"?:
            var setup = allGood
            setup.heartRateOn = false
            setup.motionAllowed = false
            setup.motionDenied = true
            return SensorCheck(demo: setup)
        case "live"?:
            let live = SensorLiveReadings(
                heartRate: .listening,
                beatsPerMinute: 88,
                source: .earbuds,
                readingCount: 14,
                gpsStarted: true,
                gpsAccuracy: 4,
                stepsStarted: true
            )
            return SensorCheck(demo: allGood, live: live, elapsed: 22)
        default:
            return nil
        }
    }

    /// The Run tab's chips: GPS and steps fine, and heart rate listening with nothing in after 40 seconds.
    static var readyCheck: SensorCheck? {
        guard arguments.contains("-readyChipsDemo") else { return nil }
        let live = SensorLiveReadings(heartRate: .listening, gpsStarted: true, gpsAccuracy: 4, stepsStarted: true, steps: 6)
        return SensorCheck(demo: allGood, live: live, mode: .ready, elapsed: 40)
    }

    /// Opens the run screen's heart rate notice as if tapped.
    static var opensRunNotice: Bool {
        arguments.contains("-runNoticeDemo")
    }

    /// The sample run's Sensors section: the run page opens scrolled to it.
    static var showsRunSensors: Bool {
        RunDetailDemo.chart == "sensors"
    }

    /// A run recorded with heart rate off and AirPods connected, steps counted and a barometer.
    static let heartRateOffReport = RunSensorReport(
        heartRateOn: false,
        health: .allowed,
        heartRateSession: .off,
        workoutSessionStarted: true,
        stepsOn: true,
        motionAllowed: true,
        barometerUsed: true,
        locationAllowed: true,
        preciseLocation: true,
        earbudsConnected: true
    )
}
#endif
