//
//  FloatingBarInset.swift
//  Wind Run
//

import SwiftUI

extension EnvironmentValues {
    /// Height of the floating section switcher at the bottom of the screen.
    @Entry var floatingBarHeight: CGFloat = 0
}

extension View {
    /// Keeps a scrolling screen's content clear of the floating section switcher. Each screen
    /// inside a section's NavigationStack needs it, pushed ones included.
    func clearsFloatingBar() -> some View {
        modifier(FloatingBarInset())
    }
}

private struct FloatingBarInset: ViewModifier {
    @Environment(\.floatingBarHeight) private var height

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: height)
        }
    }
}
