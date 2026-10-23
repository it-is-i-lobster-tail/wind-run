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
    /// Called on every tap, including a tap on the option that's already selected.
    var onTap: (Option) -> Void = { _ in }

    @Namespace private var animation

    var body: some View {
        MirroredHStack(spacing: 4) {
            ForEach(options) { option in
                Button {
                    withAnimation(.snappy) {
                        selection = option
                    }
                    onTap(option)
                } label: {
                    Text(title(option))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        // Fills the width the row gives it, so a short name's pill matches its mirror.
                        .frame(maxWidth: .infinity, minHeight: 44)
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
        .padding(4)
        .windRunGlassSelection()
    }
}

/// A row that gives each mirrored pair (first and last, second and second-to-last, ...) the
/// wider of their two widths, so the middle item lands exactly at the row's center.
private struct MirroredHStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = mirroredWidths(subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: widths.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, mirroredWidths(subviews)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func mirroredWidths(_ subviews: Subviews) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        return ideal.indices.map { max(ideal[$0], ideal[ideal.count - 1 - $0]) }
    }
}
