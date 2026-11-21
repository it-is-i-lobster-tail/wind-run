import SwiftUI

/// Horizontal paging that can coexist with vertical scrolling.
enum ChartPageSwipe {
    /// A drag that ends mostly sideways: 1 for a swipe to the left (the next page), -1 to the right.
    static func gesture(_ swiped: @escaping (Int) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 20).onEnded { value in
            if let offset = offset(for: value.translation) { swiped(offset) }
        }
    }

    static func offset(for translation: CGSize) -> Int? {
        let across = translation.width
        guard abs(across) >= 40, abs(across) > 1.5 * abs(translation.height) else { return nil }
        return across < 0 ? 1 : -1
    }

    /// Advance by an offset, wrapping at either end.
    static func step(_ selection: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((selection + offset) % count + count) % count
    }

    /// The step a VoiceOver swipe up or down takes: up to the next page, down to the one before.
    static func offset(for direction: AccessibilityAdjustmentDirection) -> Int {
        direction == .increment ? 1 : -1
    }
}

/// One dot per page, with the selected page filled.
struct ChartPageDots: View {
    let count: Int
    let selection: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(Color.primary.opacity(index == selection ? 1 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// A magnified plot owns horizontal drags until the runner restores its full range.
struct ChartZoomed: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Both plots travel with the finger. Each card sizes itself to the selected page's caption and readout.
struct MetricChartPager<Page: View>: View {
    @Binding var selection: Int
    let expanded: Bool
    @ViewBuilder let page: (Int) -> Page
    @State private var heights: [Int: CGFloat] = [:]
    @State private var zoomed: Set<Int> = []

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<2, id: \.self) { index in
                        page(index)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 2)
                            .containerRelativeFrame(.horizontal)
                            .fixedSize(horizontal: false, vertical: !expanded)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if !expanded { heights[index] = height }
                            }
                            .onPreferenceChange(ChartZoomed.self) { isZoomed in
                                if isZoomed { zoomed.insert(index) } else { zoomed.remove(index) }
                            }
                            .clipped()
                            .accessibilityHidden(index != selection)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .defaultScrollAnchor(selection == 0 ? .leading : .trailing, for: .initialOffset)
            .scrollPosition(id: Binding<Int?>(get: { selection }, set: { if let index = $0 { selection = index } }), anchor: .center)
            .scrollDisabled(zoomed.contains(selection))
            .frame(height: expanded ? nil : heights[selection])
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { oldWidth, newWidth in
                if oldWidth != newWidth { reader.scrollTo(selection, anchor: .center) }
            }
        }
    }
}
