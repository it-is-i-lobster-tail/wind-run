//
//  SystemSideMargin.swift
//  Wind Run
//

import SwiftUI
import UIKit

extension View {
    /// Reports how far UIKit insets its own bar buttons, like Back, from the side of the screen: 16 points on most
    /// iPhones and 20 on the widest. Lets a custom button line up in the same column as the system's.
    func onSystemSideMarginChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(SystemSideMarginReader(action: action))
    }
}

private struct SystemSideMarginReader: UIViewControllerRepresentable {
    let action: (CGFloat) -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.action = action
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.action = action
    }

    final class Controller: UIViewController {
        var action: (CGFloat) -> Void = { _ in }
        private var reported: CGFloat?

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            report()
        }

        override func viewLayoutMarginsDidChange() {
            super.viewLayoutMarginsDidChange()
            report()
        }

        private func report() {
            // The window's root controller carries the device's standard margins; one nested in SwiftUI may not.
            let source = view.window?.rootViewController ?? self
            let margin = source.systemMinimumLayoutMargins.leading
            guard margin > 0, margin != reported else { return }
            reported = margin
            // Out of the layout pass, so the SwiftUI state change doesn't land mid-update.
            let action = action
            Task { @MainActor in action(margin) }
        }
    }
}
