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

    var body: some View {
        WindRunScreens(selection: $selection, isShowingSettings: $isShowingSettings)
            // Switching iCloud sync replaces the container, so rebuild the screens from it.
            // Settings and the chosen section stay put.
            .id(ObjectIdentifier(modelContext.container))
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
    }
}

private struct WindRunScreens: View {
    @Binding var selection: Section
    @Binding var isShowingSettings: Bool

    // Measured height of the floating bar, reserved at the bottom of every section.
    @State private var bottomBarHeight: CGFloat = 0

    var body: some View {
        // Standard tabs can't be swiped between, so only the picker below switches sections.
        TabView(selection: $selection) {
            Tab(value: Section.run) {
                RunHomeView()
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
        // so the bar floats here and each page stops short of it.
        .overlay(alignment: .bottom) {
            GlassEffectContainer(spacing: LayoutMetrics.compactSpacing) {
                HStack(spacing: LayoutMetrics.compactSpacing * 1.5) {
                    SettingsButton { isShowingSettings = true }

                    SlidingGlassPicker(
                        options: Section.allCases,
                        selection: $selection,
                        title: \.name
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            }
            .padding(.top, LayoutMetrics.compactSpacing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                bottomBarHeight = height
            }
        }
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
    /// Hides the system tab bar and keeps content clear of the floating switcher.
    func windRunTabPage(bottomBarHeight: CGFloat) -> some View {
        toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomBarHeight)
            }
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
