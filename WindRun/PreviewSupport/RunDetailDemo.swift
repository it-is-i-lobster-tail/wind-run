//
//  RunDetailDemo.swift
//  Wind Run
//

#if DEBUG
import Foundation

/// Opens a sample run's page, for simulator screenshots, which can't tap or turn. Launch with
/// `-seedSampleRuns -runDetailDemo` for the interval run, add a chart's name (pace, elevation, cadence or
/// heart rate, as one word: `heartrate`) to open it full screen, and `-landscape` to turn the screen
/// sideways, and `-chartZoom 3` to open it zoomed in. `-runDetailDemo recording` scrolls Recording details to
/// the foot of the screen and opens it. Debug builds only.
enum RunDetailDemo {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-runDetailDemo")
    }

    /// The chart to open full screen, lowercased with no spaces, if one was named.
    static var chart: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-runDetailDemo"), arguments.indices.contains(index + 1) else { return nil }
        let name = arguments[index + 1]
        return name.hasPrefix("-") ? nil : name.lowercased()
    }

    static func opens(chart title: String) -> Bool {
        chart == title.lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// How far a full screen chart opens zoomed in: `-chartZoom 3` shows a third of the run.
    static var zoom: Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-chartZoom"), arguments.indices.contains(index + 1) else { return nil }
        return Double(arguments[index + 1])
    }

    /// Turns the screen sideways once a page that may turn is showing.
    static var turnsSideways: Bool {
        ProcessInfo.processInfo.arguments.contains("-landscape")
    }
}
#endif
