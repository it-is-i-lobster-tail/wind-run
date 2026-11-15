//
//  HeartRateSettingsSections.swift
//  Wind Run
//

import SwiftUI

/// The heart-rate switch (IN-17) in plan settings: one yes or no, since the app finds the source on its own, then the
/// Show only choice and a lab-tested maximum. "Use heart rate" is the Heart rate switch in Settings, so turning it on
/// or off in either place changes both. Setup doesn't ask.
struct HeartRateSettingsSections: View {
    @Binding var settings: HeartRateSettings

    var body: some View {
        Section {
            Toggle("Use heart rate", isOn: $settings.enabled)
        } footer: {
            Text("\(HeartRateSettings.question) \(HeartRateSettings.sourceNote) \(HeartRateSettings.sameSwitchNote)")
        }
        if settings.enabled {
            Section {
                Picker("Use heart rate for coaching", selection: $settings.useForCoaching) {
                    Text("On").tag(true)
                    Text("Show only").tag(false)
                }
                if settings.useForCoaching {
                    OptionalNumberField(title: "Lab-tested maximum (bpm)", value: $settings.labMax)
                }
            } footer: {
                Text("\(HeartRateSettings.showOnlyHint) A lab-tested maximum lowers the ceiling for easy runs. \(HeartRateSettings.privacyNote)")
            }
        }
    }
}
