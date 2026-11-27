//
//  WindRunApp.swift
//  Wind Run
//

import SwiftData
import SwiftUI

@main
struct WindRunApp: App {
    /// Only for which way the screen may turn.
    @UIApplicationDelegateAdaptor(WindRunAppDelegate.self) private var appDelegate

    #if DEBUG
    static let store: WindRunStore = {
        if ProgressDemo.isRequested {
            UserDefaults.standard.register(defaults: [PromptQueue.answeredKey: Prompt.all.map(\.id)])
            let store = WindRunStore(inMemory: true)
            ProgressDemo.populate(store.container.mainContext)
            return store
        }
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
        // Each watch run joins the current phone store, including the coach link when it matches a session.
        SettingsSync.shared.runReceived = { data in
            let store = Self.store
            guard store.openFailure == nil,
                  !store.container.configurations.contains(where: \.isStoredInMemoryOnly) else { return nil }
            guard let record = WatchRunRecord.decode(data) else {
                Trace.log(.watch, "Watch run unreadable", ["bytes": data.count])
                return nil
            }
            // An isolated context keeps a failed import from becoming an unsaved run on screen.
            do {
                _ = try record.save(into: ModelContext(store.container))
                return record.runID
            } catch {
                Trace.error("Couldn't save a run from the watch", error)
                return nil
            }
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
        if !WindRunSeed.isRequested && !ProgressDemo.isRequested { WorkoutMigration.runIfNeeded(in: Self.store.container.mainContext) }
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
        // Older runs get their routes packed a few seconds after the app comes to the front, one at a time.
        .task(id: scenePhase == .active && store.openFailure == nil) {
            guard scenePhase == .active, store.openFailure == nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await RouteMigration.packOldRuns(in: store.container.mainContext)
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
