//
//  WindRunRootView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

private enum Section: CaseIterable, Hashable, Identifiable {
    case run
    case intervals
    case coach

    var id: Self { self }

    var name: String {
        switch self {
        case .run: "Run"
        case .intervals: "Intervals"
        case .coach: "Coach"
        }
    }
}

struct WindRunRootView: View {
    @Environment(\.modelContext) private var modelContext

    // Kept out here so they survive the rebuild below.
    @State private var selection = Section.run
    @State private var isShowingSettings = false
    /// What the coach last said, shared by every section.
    @State private var coachInbox = CoachInbox()

    var body: some View {
        WindRunScreens(selection: $selection, isShowingSettings: $isShowingSettings)
            // Switching iCloud sync replaces the container, so rebuild the screens from it.
            // Settings and the chosen section stay put.
            .id(ObjectIdentifier(modelContext.container))
            .environment(coachInbox)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            // First open: ask about settings that stay off until the runner says yes, like heart rate.
            .presentsPrompts()
    }
}

private struct WindRunScreens: View {
    @Binding var selection: Section
    @Binding var isShowingSettings: Bool

    @Query private var coachPlans: [CoachPlan]

    // Measured height of the floating bar, reserved at the bottom of every section.
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        // Standard tabs can't be swiped between, so only the picker below switches sections.
        TabView(selection: $selection) {
            Tab(value: Section.run) {
                RunHomeView { selection = .coach }
                    .windRunTabPage(bottomBarHeight: bottomBarHeight)
            }
            Tab(value: Section.intervals) {
                IntervalsHomeView()
                    .windRunTabPage(bottomBarHeight: bottomBarHeight)
            }
            Tab(value: Section.coach) {
                CoachHomeView()
                    .windRunTabPage(bottomBarHeight: bottomBarHeight)
            }
        }
        // Tab pages don't inherit a safe-area inset set on the TabView,
        // so the bar floats here and each page's content stops short of it.
        .overlay(alignment: .bottom) {
            GlassEffectContainer(spacing: LayoutMetrics.compactSpacing) {
                // Settings stays at the leading edge; the switcher is centered on the screen.
                LeadingAndCenteredLayout(spacing: LayoutMetrics.compactSpacing * 1.5) {
                    SettingsButton { isShowingSettings = true }

                    SlidingGlassPicker(
                        options: Section.allCases,
                        selection: $selection,
                        title: \.name
                    )
                }
                .padding(.horizontal)
            }
            // Like the system tab bar, the switcher stops growing at the largest standard size, so
            // section names never break mid-word. Its buttons keep their full VoiceOver names.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.top, LayoutMetrics.compactSpacing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                bottomBarHeight = height
            }
        }
        // Here rather than in Coach, so today's workout on the Run screen is current too.
        .refreshesCoach(TermsAcceptance.isCurrent() ? coachPlans.active : nil)
    }
}

/// Pins the first view to the leading edge and centers the second across the full width.
/// The second slides toward the trailing edge only when centering it would run it into the first,
/// on narrow screens or at large text sizes.
private struct LeadingAndCenteredLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        let height = sizes.map(\.height).max() ?? 0
        if let width = proposal.width, width.isFinite {
            return CGSize(width: max(width, naturalWidth), height: height)
        }
        return CGSize(width: naturalWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let leading = subviews.first, let centered = subviews.dropFirst().first else { return }
        let leadingSize = leading.sizeThatFits(.unspecified)
        let centeredSize = centered.sizeThatFits(.unspecified)

        leading.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(leadingSize))

        let centeredX = max(bounds.midX - centeredSize.width / 2, bounds.minX + leadingSize.width + spacing)
        centered.place(at: CGPoint(x: centeredX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(centeredSize))
    }
}

private struct SettingsButton: View {
    // Matches the switcher's height: a 44pt pill plus its 4pt padding.
    private static let size: CGFloat = 52

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.title3)
                .frame(width: Self.size, height: Self.size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .windRunGlassCircle(interactive: true)
        .accessibilityLabel("Settings")
    }
}

private extension View {
    /// Hides the system tab bar and tells the page how much room the floating switcher needs.
    func windRunTabPage(bottomBarHeight: CGFloat) -> some View {
        toolbar(.hidden, for: .tabBar)
            // A safe-area inset here wouldn't reach the scroll views inside each page's
            // NavigationStack, so they make room themselves with clearsFloatingBar().
            .environment(\.floatingBarHeight, bottomBarHeight)
    }
}

#Preview("Root - With runs") {
    WindRunRootView()
        .modelContainer(WindRunSeed.containerWithRuns())
        .environment(WindRunStore(inMemory: true))
}

#Preview("Root - Empty") {
    WindRunRootView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
        .environment(WindRunStore(inMemory: true))
}
