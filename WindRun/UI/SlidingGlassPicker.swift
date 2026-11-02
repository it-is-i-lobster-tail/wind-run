//
//  SlidingGlassPicker.swift
//  Wind Run
//

import SwiftUI

/// The floating section switcher, used in place of a tab bar.
struct SlidingGlassPicker<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    /// Called on every tap, including a tap on the option that's already selected.
    var onTap: (Option) -> Void = { _ in }

    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
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
                        .frame(minHeight: 44)
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
