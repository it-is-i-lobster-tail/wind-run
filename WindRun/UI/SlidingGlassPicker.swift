//
//  SlidingGlassPicker.swift
//  Wind Run
//

import SwiftUI

/// The floating section switcher, used in place of a tab bar.
/// Mirrored options share a width, so the middle option sits exactly at the switcher's center.
struct SlidingGlassPicker<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    /// Called on every tap, including a tap on the option that's already selected, before the selection
    /// changes, so it can tell the two apart.
    var onTap: (Option) -> Void = { _ in }

    @Namespace private var animation

    var body: some View {
        MirroredHStack(spacing: LayoutMetrics.sectionPillSpacing) {
            ForEach(options) { option in
                Button {
                    onTap(option)
                    withAnimation(.snappy) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        // On a narrow screen at the largest text sizes the pills narrow, so the name shrinks
                        // a little rather than breaking.
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        // Fills the width the row gives it, so a short name's pill matches its mirror.
                        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.sectionPillMinHeight)
                        // The whole pill is tappable, not just the letters.
                        .contentShape(Capsule())
                        .background {
                            if selection == option {
                                Color.clear
                                    .glassEffect(.regular, in: Capsule())
                                    .matchedGeometryEffect(id: "selection", in: animation)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(LayoutMetrics.sectionBarInset)
        .windRunGlassSelection()
    }
}

/// A row that gives each mirrored pair (first and last, second and second-to-last, ...) the
/// wider of their two widths, so the middle item lands exactly at the row's center.
private struct MirroredHStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = fittedWidths(subviews, in: proposal.width)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: widths.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, fittedWidths(subviews, in: bounds.width)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    /// The mirrored widths, all narrowed by the same share when they'd be wider than `available`.
    private func fittedWidths(_ subviews: Subviews, in available: CGFloat?) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        return MirroredWidths.fitted(MirroredWidths.mirrored(ideal), spacing: spacing, available: available)
    }
}

/// The width math for `MirroredHStack`, apart from its subviews so it can be tested.
nonisolated enum MirroredWidths {
    /// Each mirrored pair (first and last, second and second-to-last, ...) gets the wider of its two widths.
    static func mirrored(_ ideal: [CGFloat]) -> [CGFloat] {
        ideal.indices.map { max(ideal[$0], ideal[ideal.count - 1 - $0]) }
    }

    /// `widths` as they are when they fit in `available` with `spacing` between them, or all narrowed by
    /// the same share when they don't.
    static func fitted(_ widths: [CGFloat], spacing: CGFloat, available: CGFloat?) -> [CGFloat] {
        let gaps = spacing * CGFloat(max(widths.count - 1, 0))
        let total = widths.reduce(0, +)
        guard let available, available.isFinite, total + gaps > available, total > 0 else { return widths }
        let scale = max(0, available - gaps) / total
        return widths.map { $0 * scale }
    }
}
