//
//  AdaptiveRow.swift
//  Wind Run
//

import SwiftUI

/// Side by side normally, stacked at accessibility text sizes so neither side gets squeezed.
struct AdaptiveRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var spacing: CGFloat = LayoutMetrics.compactSpacing
    @ViewBuilder let content: () -> Content

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: spacing))
        layout(content)
    }
}
