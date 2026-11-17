//
//  WindRunRootView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

private enum Section: CaseIterable, Hashable, Identifiable {
    case run
    case workout
    case coach

    var id: Self { self }

    /// The section the app opens on: Run, or Workout for `-workoutsDemo` screenshots.
    static var initial: Section {
        #if DEBUG
        if WorkoutsDemo.page != nil { return .workout }
        #endif
        return .run
    }

    var name: String {
        switch self {
        case .run: "Run"
        case .workout: "Workout"
        case .coach: "Coach"
        }
    }
}

struct WindRunRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    // Kept out here so they survive the rebuild below.
    @State private var selection = Section.initial
    @State private var isShowingSettings = false

    var body: some View {
        WindRunScreens(selection: $selection, isShowingSettings: $isShowingSettings)
            .sendsSavedWorkoutsToWatch()
            // Switching iCloud sync replaces the container, so rebuild the screens from it.
            // Settings and the chosen section stay put.
            .id(ObjectIdentifier(modelContext.container))
            // Taps are traced by the switcher; this also catches a section opened from a button.
            .onChange(of: selection) { _, section in
                Trace.log(.screen, "Section shown", ["section": section.name])
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            // First open: ask about settings that stay off until the runner says yes, like heart rate.
            .presentsPrompts()
            // About once a month, a newer weight from Health for calories.
            .task { await HealthWeight.refreshIfDue() }
            // Heart rate turned on before Wind Run kept Apple's distance, or Save runs to Health before runs
            // carried their calories: Health asks about each once, one after the other.
            .task {
                await HeartRateMonitor.askForNewAccessIfOn()
                await HealthSync.shared.askForNewAccessIfOn()
            }
            // Runs that couldn't go to Health, such as one finished while the iPhone was locked, try again
            // whenever the app comes back.
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                HealthSync.shared.retryPending(in: modelContext)
            }
            // Runs from before heart rate zones: their highest heart rate, once.
            .task { HeartRateMax.backfill(in: modelContext) }
    }
}

private struct WindRunScreens: View {
    @Binding var selection: Section
    @Binding var isShowingSettings: Bool

    @Query private var coachPlans: [CoachPlan]

    // Measured height of the floating bar, reserved at the bottom of every section.
    @State private var bottomBarHeight: CGFloat = 0
    /// Taps on the section already showing, for each section, which take it back to its first screen.
    @State private var reselections: [Section: Int] = [:]

    var body: some View {
        // Standard tabs can't be swiped between, so only the picker below switches sections.
        TabView(selection: $selection) {
            Tab(value: Section.run) {
                RunHomeView { selection = .coach }
                    .windRunTabPage(bottomBarHeight: bottomBarHeight)
                    .environment(\.sectionReselections, reselections[.run, default: 0])
            }
            Tab(value: Section.workout) {
                WorkoutsHomeView { selection = .coach }
                    .windRunTabPage(bottomBarHeight: bottomBarHeight)
                    .environment(\.sectionReselections, reselections[.workout, default: 0])
            }
            Tab(value: Section.coach) {
                CoachHomeView()
                    .windRunTabPage(bottomBarHeight: bottomBarHeight)
                    .environment(\.sectionReselections, reselections[.coach, default: 0])
            }
        }
        // Tab pages don't inherit a safe-area inset set on the TabView,
        // so the bar floats here and each page's content stops short of it.
        .overlay(alignment: .bottom) {
            GlassEffectContainer(spacing: LayoutMetrics.compactSpacing) {
                // Settings stays at the leading edge; the switcher is centered on the screen.
                LeadingAndCenteredLayout(spacing: LayoutMetrics.compactSpacing) {
                    SettingsButton {
                        Trace.tap("Section bar", "Settings")
                        isShowingSettings = true
                    }

                    SlidingGlassPicker(
                        options: Section.allCases,
                        selection: $selection,
                        title: \.name
                    ) { section in
                        Trace.tap("Section bar", section.name, ["again": section == selection])
                        // As with the system tab bar, the section already showing goes back to its first screen.
                        if section == selection {
                            reselections[section, default: 0] += 1
                        }
                    }
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
/// on narrow screens or at large text sizes, and when even that isn't room enough it's offered only the
/// width that's left, so it narrows rather than running off the screen.
private struct LeadingAndCenteredLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        let height = sizes.map(\.height).max() ?? 0
        if let width = proposal.width, width.isFinite {
            return CGSize(width: width, height: height)
        }
        return CGSize(width: naturalWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let leading = subviews.first, let centered = subviews.dropFirst().first else { return }
        let leadingSize = leading.sizeThatFits(.unspecified)
        leading.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(leadingSize))

        let earliestX = bounds.minX + leadingSize.width + spacing
        let room = max(0, bounds.maxX - earliestX)
        var centeredSize = centered.sizeThatFits(.unspecified)
        if centeredSize.width > room {
            centeredSize = centered.sizeThatFits(ProposedViewSize(width: room, height: nil))
            centeredSize.width = min(centeredSize.width, room)
        }
        let centeredX = min(max(bounds.midX - centeredSize.width / 2, earliestX), bounds.maxX - centeredSize.width)
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
