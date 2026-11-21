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

@Observable
final class MetricChartPages {
    private(set) var selection = 0

    func advance(_ offset: Int) {
        selection = ChartPageSwipe.step(selection, by: offset, count: 2)
    }
}
