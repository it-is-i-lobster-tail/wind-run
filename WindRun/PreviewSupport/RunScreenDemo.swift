//
//  RunScreenDemo.swift
//  Wind Run
//

#if DEBUG
import SwiftUI

/// The iPhone's display screen with made-up numbers, for simulator screenshots, which have no run to show.
/// Launch with `-runScreenDemo`. Debug builds only.
struct RunScreenDemo: View {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-runScreenDemo")
    }

    var body: some View {
        let snapshot = RunSnapshot(
            elapsed: 32 * 60 + 48,
            meters: 6_400,
            unit: .kilometers,
            currentPace: 312,
            averagePace: 307,
            beatsPerMinute: 148,
            heightFromStart: -43,
            cadence: 172
        )
        VStack {
            Spacer()
            RunDisplayScreenView(readings: DisplayScreen.current.readings(snapshot))
            Spacer()
        }
        .padding()
    }
}
#endif
