//
//  MotionSection.swift
//  Wind Run
//

import SwiftUI

/// The step counting and auto-pause switches, shared by the iPhone and watch settings.
///
/// Turning either on asks for Motion & Fitness. Steps need it and go back off without it. Auto-pause
/// works from GPS alone when motion isn't allowed, just a little slower to notice a stop.
struct MotionSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(MotionMonitor.stepsKey) private var countsSteps = false
    @AppStorage(AutoPause.storageKey) private var autoPauses = false
    @State private var isDenied = MotionMonitor.isDenied

    var body: some View {
        Section {
            Toggle("Steps and cadence", isOn: $countsSteps)
                .disabled(!MotionMonitor.isAvailable)
            Toggle("Auto-pause", isOn: $autoPauses)
        } header: {
            Text("Motion")
        } footer: {
            Text(footer)
        }
        .onChange(of: countsSteps) { _, isOn in
            guard isOn else { return }
            Task {
                let allowed = await MotionMonitor.requestAccess()
                if !allowed { countsSteps = false }
                isDenied = MotionMonitor.isDenied
            }
        }
        .onChange(of: autoPauses) { _, isOn in
            guard isOn else { return }
            Task {
                _ = await MotionMonitor.requestAccess()
                isDenied = MotionMonitor.isDenied
            }
        }
        // Permission can change in the Settings app while Wind Run is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                isDenied = MotionMonitor.isDenied
            }
        }
    }

    private var footer: LocalizedStringKey {
        if !MotionMonitor.isAvailable {
            return "This device can't count steps. Auto-pause uses GPS alone."
        }
        if isDenied {
            #if os(watchOS)
            return "Steps need Motion & Fitness allowed for Wind Run in the Watch app's privacy settings. Auto-pause still works from GPS."
            #else
            return "Steps need Motion & Fitness allowed in Settings > Privacy & Security > Motion & Fitness. Auto-pause still works from GPS."
            #endif
        }
        #if os(watchOS)
        return "Counts your steps, and pauses the clock when you stand still. Recovery steps never pause."
        #else
        return "Counts your steps and shows your cadence. Auto-pause stops the clock when you stand still and starts it when you run again, using motion and GPS together. Recovery steps never pause, so rests still count down."
        #endif
    }
}
