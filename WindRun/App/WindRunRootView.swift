//
//  WindRunRootView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

private enum AppTab: String, Hashable {
    case run = "Run"
    case workout = "Workout"
    case coach = "Coach"
    case progress = "Progress"
    case settings = "Settings"

    static var initial: Self {
        #if DEBUG
        if ProgressDemo.isRequested { return .progress }
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

    private var containerID: ObjectIdentifier {
        ObjectIdentifier(modelContext.container)
    }

    private var settingsRole: TabRole? {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { return .prominent }
        #endif
        return nil
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Run", systemImage: "figure.run", value: AppTab.run) {
                RunHomeView { selection = .coach }
                    .id(containerID)
            }
            Tab("Workout", systemImage: "repeat", value: AppTab.workout) {
                WorkoutsHomeView { selection = .coach }
                    .id(containerID)
            }
            Tab("Coach", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.coach) {
                CoachHomeView()
                    .id(containerID)
            }
            Tab("Progress", systemImage: "chart.bar.xaxis", value: AppTab.progress) {
                ProgressHomeView()
                    .id(containerID)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings, role: settingsRole) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Refresh model-backed screens and observers when iCloud sync swaps the store.
        // Settings keeps its progress and alerts throughout the switch.
        .background {
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

private struct WorkoutObservers: View {
    @Query private var coachPlans: [CoachPlan]

    var body: some View {
        Color.clear
            .sendsSavedWorkoutsToWatch()
            .refreshesCoach(TermsAcceptance.isCurrent() ? coachPlans.active : nil)
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
