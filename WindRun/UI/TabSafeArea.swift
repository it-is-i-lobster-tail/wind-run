//
//  TabSafeArea.swift
//  Wind Run
//

import SwiftUI
import UIKit

extension View {
    /// Adds the floating section switcher to the safe area of the TabView this page is in. UIKit hands that safe
    /// area down to every section and every screen pushed inside one, which SwiftUI's safe-area modifiers on a
    /// tab page don't reach. Scrolling content runs under the switcher's glass but comes to rest above it.
    func reservesTabBottom(_ height: CGFloat) -> some View {
        background(TabSafeArea(bottom: height))
    }
}

private struct TabSafeArea: UIViewControllerRepresentable {
    let bottom: CGFloat

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.bottom = bottom
    }

    final class Controller: UIViewController {
        var bottom: CGFloat = 0 {
            didSet { apply() }
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        private func apply() {
            guard let tabBarController, tabBarController.additionalSafeAreaInsets.bottom != bottom else { return }
            tabBarController.additionalSafeAreaInsets.bottom = bottom
        }
    }
}
