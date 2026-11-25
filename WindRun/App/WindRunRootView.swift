//
//  WindRunRootView.swift
//  Wind Run
//

import SwiftData
import SwiftUI
import UIKit

private enum AppTab: String, Hashable {
    case run = "Run"
    case workout = "Workout"
    case coach = "Coach"
    case history = "Map"
    case settings = "Settings"

    static var initial: Self {
        #if DEBUG
        if ProgressDemo.isRequested { return .history }
        if SettingsDemo.page != nil { return .settings }
        if WorkoutsDemo.page != nil { return .workout }
        #endif
        return .run
    }
}

struct WindRunRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @State private var selection = AppTab.initial
    @State private var searchingHistory = false
    @State private var isTabBarMinimized = false

    private var containerID: ObjectIdentifier {
        ObjectIdentifier(modelContext.container)
    }

    private var settingsRole: TabRole? {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { return .prominent }
        #endif
        return nil
    }

    private func appTab<Content: View>(
        _ title: LocalizedStringKey, systemImage: String, value: AppTab, role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) -> some TabContent<AppTab> {
        let symbol = isTabBarMinimized && role == nil && value != .settings ? "figure.run" : systemImage
        return Tab(title, systemImage: symbol, value: value, role: role) {
            content()
                .background {
                    TabBarMinimizationReader(isMinimized: $isTabBarMinimized)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
        }
    }

    var body: some View {
        TabView(selection: Binding(get: { selection }, set: { tab in
            if selection == .history && tab == .settings {
                searchingHistory = true
            } else {
                selection = tab
            }
        })) {
            appTab("Run", systemImage: "figure.run", value: AppTab.run) {
                RunHomeView { selection = .coach }
                    .id(containerID)
            }
            appTab("Workout", systemImage: "stopwatch", value: AppTab.workout) {
                WorkoutsHomeView { selection = .coach }
                    .id(containerID)
            }
            appTab("Coach", systemImage: "list.clipboard", value: AppTab.coach) {
                CoachHomeView()
                    .id(containerID)
            }
            appTab("Map", systemImage: "map", value: AppTab.history) {
                HistoryMapView { searchingHistory = true }
                    .id(containerID)
            }
            appTab(selection == .history ? "Search" : "Settings", systemImage: selection == .history ? "magnifyingglass" : "gearshape", value: AppTab.settings, role: settingsRole) {
                SettingsView()
            }
        }
        .sheet(isPresented: $searchingHistory) { HistorySearchView().id(containerID) }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Refresh model-backed screens and observers when iCloud sync swaps the store.
        // Settings keeps its progress and alerts throughout the switch.
        .background {
            RouteTagObserver().id(containerID)
            WorkoutObservers()
                .id(containerID)
        }
        .onChange(of: selection) { _, tab in
            Trace.log(.screen, "Section shown", ["section": tab.rawValue])
        }
        .presentsPrompts()
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

/// Reads the native bar inside the visible tab, including pushed screens.
private struct TabBarMinimizationReader: UIViewControllerRepresentable {
    @Binding var isMinimized: Bool

    func makeUIViewController(context: Context) -> Observer { Observer() }

    func updateUIViewController(_ observer: Observer, context: Context) {
        observer.isMinimized = $isMinimized
    }

    final class Observer: UIViewController {
        var isMinimized: Binding<Bool> = .constant(false)
        // A passive link runs only when UIKit is already updating the screen.
        private lazy var updates = UIUpdateLink(view: view) { [weak self] _, _ in
            self?.readLayout()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            updates.isEnabled = true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            updates.isEnabled = false
        }

        private func readLayout() {
            guard let bar = tabBarController?.tabBar, !bar.isHidden,
                  let items = bar.items, items.count >= 2,
                  let first = items[0].frame(in: bar), let second = items[1].frame(in: bar),
                  !first.isEmpty, !second.isEmpty else { return }
            // Run and Workout share the leading button's frame only while the bar is minimized.
            let minimized = first == second
            if isMinimized.wrappedValue != minimized {
                isMinimized.wrappedValue = minimized
            }
        }
    }
}

private struct WorkoutObservers: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var coachPlans: [CoachPlan]
    @State private var now = Date.now

    private var coachPlan: CoachPlan? {
        TermsAcceptance.isCurrent() ? coachPlans.active : nil
    }

    private var watchSessions: [WatchCoachSession] {
        guard let coachPlan, coachPlan.status == .active,
              let state = BuildService(context: modelContext).state(of: coachPlan),
              !state.isPaused else { return [] }
        return CoachToday.workouts(coachPlan, build: state, now: now, calendar: .current)
            .compactMap { WatchCoachSession($0) }
    }

    var body: some View {
        let sessions = watchSessions
        Color.clear
            .sendsSavedWorkoutsToWatch()
            .refreshesCoach(coachPlan)
            .task(id: sessions) { SettingsSync.shared.sendCoachToday(sessions) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = .now }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in now = .now }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
