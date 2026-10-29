//
//  KeyboardDismiss.swift
//  Wind Run
//

import SwiftUI
import UIKit

extension View {
    /// Puts the keyboard away when the runner taps anywhere that isn't a text field (Brendon, 2026-10-29). The
    /// number pads have no return key, so without this nothing closes them. Set once at the root: sheets share
    /// the window, so it covers them too.
    func dismissesKeyboardOnTapOutside() -> some View {
        background(KeyboardDismissInstaller().frame(width: 0, height: 0))
    }
}

/// Adds one tap recognizer to the window. It never cancels the tap, so buttons, pickers and rows still get it.
private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private lazy var tap: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            return tap
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            tap.view?.removeGestureRecognizer(tap)
            window?.addGestureRecognizer(tap)
        }

        @objc private func tapped() {
            tap.view?.endEditing(true)
        }

        /// A tap in a text field is the runner moving to it, so the keyboard stays.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
