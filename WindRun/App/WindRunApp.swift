//
//  WindRunApp.swift
//  Wind Run
//

import SwiftData
import SwiftUI

@main
struct WindRunApp: App {
    #if DEBUG
    static let store: WindRunStore = {
        guard WindRunSeed.isRequested else { return WindRunStore(inMemory: WindRunSchema.runsInMemory) }
        let store = WindRunStore(inMemory: true)
        WindRunSeed.addSampleRuns(to: store.container.mainContext)
        if WindRunSeed.plansRequested { WindRunSeed.addSamplePlan(to: store.container.mainContext) }
        return store
    }()
    #else
    static let store = WindRunStore(inMemory: WindRunSchema.runsInMemory)
    #endif

    init() {
        // Before anything else, so the trace starts with the launch.
        Trace.log(.app, "Launched")
        TraceHooks.installIfOn()
        TraceZip.deleteMadeZips()
        // A coached run done on the watch joins the runs here, linked to its session, for the coach. Decoding
        // and adding it trace what came, or why it didn't.
        SettingsSync.shared.runReceived = { data in
            guard let record = WatchRunRecord.decode(data) else {
                Trace.log(.watch, "Watch run unreadable", ["bytes": data.count])
                return
            }
            record.insert(into: Self.store.container.mainContext)
        }
        // Taps on the Lock Screen's buttons, and whether a run was there to take them.
        ActiveRunControl.tapped = { control, handled in
            Trace.tap("Live Activity", control, ["handled": handled])
        }
        SettingsSync.shared.start()
        // A run can't outlive the app, so a run still going, and its heart rate Live Activity,
        // are left over from a run the app was closed in the middle of.
        RunRecovery.finishLeftoverRuns(in: Self.store.container.mainContext)
        // Workouts made before they were a warm-up, a main part and a cooldown go, once per device. Not over
        // the sample data, which is made fresh for screenshots.
        #if DEBUG
        if !WindRunSeed.isRequested { WorkoutMigration.runIfNeeded(in: Self.store.container.mainContext) }
        #else
        WorkoutMigration.runIfNeeded(in: Self.store.container.mainContext)
        #endif
        HeartRateActivityController.endLeftoverActivities()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if RunScreenDemo.isRequested {
                RunScreenDemo()
            } else {
                WindRunAppContent()
                    .environment(Self.store)
            }
            #else
            WindRunAppContent()
                .environment(Self.store)
            #endif
        }
    }
}

/// The app's screens on the store's current container, which changes with iCloud sync.
struct WindRunAppContent: View {
    @Environment(WindRunStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    var body: some View {
        Group {
            if store.openFailure != nil {
                StoreProblemView()
            } else {
                WindRunRootView()
                    .modelContainer(store.container)
                    .dismissesKeyboardOnTapOutside()
                    // Content fades softly under the bars instead of stopping at a hard line. Sheets don't
                    // inherit this, so each one with a navigation bar or a scroll view sets it too.
                    .scrollEdgeEffectStyle(.soft, for: .all)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            appearance.apply()
        }
        // Also follows a pick made on another iPhone, which arrives through iCloud.
        .onChange(of: appearance, initial: true) { _, appearance in
            appearance.apply()
        }
    }
}

/// Shown in place of the app when the runs on this iPhone couldn't be opened, rather than an empty store that
/// wouldn't be kept, so nothing is recorded into it.
private struct StoreProblemView: View {
    @Environment(WindRunStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Open Your Runs", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Wind Run couldn't open the runs saved on this iPhone, so it can't show or record any right now. Nothing has been deleted. Try again, or restart your iPhone. An update to Wind Run may be needed.")
        } actions: {
            Button("Try Again") {
                Trace.tap("Store problem", "Try Again")
                store.retryOpening()
            }
            .buttonStyle(.borderedProminent)
        }
        .traceScreen("Store problem")
    }
}
