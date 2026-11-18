//
//  WindRunRootView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

private enum AppSection: CaseIterable, Hashable, Identifiable {
    case run
    case workout
    case coach

    var id: Self { self }

    /// The section the app opens on: Run, or Workout for `-workoutsDemo` screenshots.
    static var initial: AppSection {
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
    @State private var selection = AppSection.initial
    @State private var isShowingSettings = {
        #if DEBUG
        SettingsDemo.page != nil
        #else
        false
        #endif
    }()

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
    @Binding var selection: AppSection
    @Binding var isShowingSettings: Bool

    @Query private var coachPlans: [CoachPlan]
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // Measured height of the floating bar, added to the safe area of every section.
    @State private var bottomBarHeight: CGFloat = 0
    /// Taps on the section already showing, for each section, which take it back to its first screen.
    @State private var reselections: [AppSection: Int] = [:]

    /// Sideways, which only the run's charts turn to, the switcher steps aside so the charts get the screen's
    /// little height. Turning back upright brings it back.
    private var isSideways: Bool { verticalSizeClass == .compact }

    /// The room each section keeps for the switcher.
    private var reservedBottom: CGFloat { isSideways ? 0 : bottomBarHeight }

    var body: some View {
        // Standard tabs can't be swiped between, so only the picker below switches sections.
        TabView(selection: $selection) {
            Tab(value: AppSection.run) {
                RunHomeView { selection = .coach }
                    .windRunTabPage(bottomBarHeight: reservedBottom)
                    .environment(\.sectionReselections, reselections[.run, default: 0])
            }
            Tab(value: AppSection.workout) {
                WorkoutsHomeView { selection = .coach }
                    .windRunTabPage(bottomBarHeight: reservedBottom)
                    .environment(\.sectionReselections, reselections[.workout, default: 0])
            }
            Tab(value: AppSection.coach) {
                CoachHomeView()
                    .windRunTabPage(bottomBarHeight: reservedBottom)
                    .environment(\.sectionReselections, reselections[.coach, default: 0])
            }
        }
        // The bar floats over the sections. Each page adds it to the tab view's safe area,
        // so content scrolls under the glass but comes to rest above it.
        .overlay(alignment: .bottom) {
            if !isSideways { switcher }
        }
        // Here rather than in Coach, so today's workout on the Run screen is current too.
        .refreshesCoach(TermsAcceptance.isCurrent() ? coachPlans.active : nil)
    }

    private var switcher: some View {
        GlassEffectContainer(spacing: LayoutMetrics.compactSpacing) {
            // Settings sits in the same column as the back button above it; the switcher is centered on the screen.
            LeadingAndCenteredLayout(spacing: LayoutMetrics.compactSpacing) {
                SettingsButton {
                    Trace.tap("Section bar", "Settings")
                    isShowingSettings = true
                }

                SlidingGlassPicker(
                    options: AppSection.allCases,
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
            .padding(.horizontal, LayoutMetrics.navigationButtonInset)
        }
        // Like the system tab bar, the switcher stops growing at the largest standard size, so
        // section names never break mid-word. Its buttons keep their full VoiceOver names.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.top, LayoutMetrics.compactSpacing)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            bottomBarHeight = height
        }
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
        let height = sizes.map(\.height).max() ?? 0
        if let width = proposal.width, width.isFinite {
            return CGSize(width: width, height: height)
        }
        let naturalWidth = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        return CGSize(width: naturalWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let leading = subviews.first, let centered = subviews.dropFirst().first else { return }
        let leadingSize = leading.sizeThatFits(.unspecified)
        leading.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(leadingSize))

        var centeredSize = centered.sizeThatFits(.unspecified)
        let frame = LeadingAndCentered.centeredFrame(
            in: bounds.minX...bounds.maxX,
            leadingWidth: leadingSize.width,
            spacing: spacing,
            centeredWidth: centeredSize.width
        )
        if frame.width < centeredSize.width {
            centeredSize = centered.sizeThatFits(ProposedViewSize(width: frame.width, height: nil))
            centeredSize.width = min(centeredSize.width, frame.width)
        }
        centered.place(at: CGPoint(x: frame.x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(centeredSize))
    }
}

/// The math for `LeadingAndCenteredLayout`, apart from its subviews so it can be tested.
nonisolated enum LeadingAndCentered {
    /// Where the centered view starts and how wide it may be: centered across `span` when that clears the
    /// leading view and the gap after it, otherwise as close to center as it can get, and no wider than the room left.
    static func centeredFrame(
        in span: ClosedRange<CGFloat>,
        leadingWidth: CGFloat,
        spacing: CGFloat,
        centeredWidth: CGFloat
    ) -> (x: CGFloat, width: CGFloat) {
        let earliestX = span.lowerBound + leadingWidth + spacing
        let width = min(centeredWidth, max(0, span.upperBound - earliestX))
        let midX = (span.lowerBound + span.upperBound) / 2
        let x = min(max(midX - width / 2, earliestX), span.upperBound - width)
        return (x, width)
    }
}

private struct SettingsButton: View {
    // The same size as the system back button it lines up with.
    private static let size: CGFloat = LayoutMetrics.navigationButtonSize

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
    /// Hides the system tab bar and makes room for the floating switcher on every screen in the section, pushed
    /// ones too. Content scrolls under the switcher's glass, fading softly as it does under the title, and comes
    /// to rest above it.
    func windRunTabPage(bottomBarHeight: CGFloat) -> some View {
        toolbar(.hidden, for: .tabBar)
            // The room: UIKit hands the tab view's safe area to every screen in the section, pushed ones too.
            .reservesTabBottom(bottomBarHeight)
            // The fade: a hairline bar at the top of that room marks where the switcher's glass starts, so content
            // fades softly from there to the bottom edge as it does under the title. It reserves no room of its
            // own, and a clear bar draws no scroll edge effect, so it's all but clear.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                Color.black.opacity(0.001)
                    .frame(height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
