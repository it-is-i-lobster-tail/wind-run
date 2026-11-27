//
//  StartingPointDemo.swift
//  Wind Run
//

#if DEBUG
import SwiftUI

/// Moves Settings → Your Data → Starting Point along for simulator screenshots, which can't tap or scroll.
/// Launch with `-settingsDemo starting-point -startingPointDemo STEP`, where STEP is `list` (scrolled down to
/// the pins under the map) or `delete` (the same, asking to delete the last pin). Debug builds only.
enum StartingPointDemo {
    static var step: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-startingPointDemo"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func run(scroller: ScrollViewProxy, pins: [ExportPrivacy.Pin], askToDelete: (ExportPrivacy.Pin) -> Void) async {
        guard let step, let last = pins.last else { return }
        // Let the page and its map settle first.
        try? await Task.sleep(for: .seconds(1))
        scroller.scrollTo(last.id, anchor: .bottom)
        if step == "delete" {
            try? await Task.sleep(for: .seconds(0.5))
            askToDelete(last)
        }
    }
}
#endif
