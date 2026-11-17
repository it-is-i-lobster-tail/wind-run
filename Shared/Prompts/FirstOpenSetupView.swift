//
//  FirstOpenSetupView.swift
//  Wind Run
//

import SwiftUI

/// The first-open setup page: every first-open choice on one screen, with Continue and Not Now.
struct FirstOpenSetupView: View {
    @Bindable var setup: FirstOpenSetup
    let queue: PromptQueue

    #if os(iOS)
    @FocusState private var isTypingWeight: Bool
    #endif

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Wind Run")
                        .font(Self.titleFont)
                    Text("A few choices before your first run. You can change any of them in Settings.")
                        .font(Self.introFont)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
            }

            #if os(iOS)
            Section("Units") {
                Picker("Units", selection: $setup.unit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text("\(unit.systemName) (\(unit.shortExamples))").tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            #endif

            if setup.offersHealth {
                Section {
                    Toggle(isOn: $setup.heartRate) {
                        row("Heart rate during runs", detail: Self.heartRateDetail, systemImage: "heart.fill", color: .red)
                    }
                    Toggle(isOn: $setup.saveRuns) {
                        row("Save runs to Health", detail: "With each run's route and calories, so Fitness counts it.", systemImage: "heart.text.square.fill", color: .pink)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Apple asks once for everything you turn on here. Your health data stays on your devices, and is never sent to us.")
                }
            }

            Section {
                Toggle(isOn: $setup.motion) {
                    if setup.countsSteps {
                        row("Steps, cadence and auto-pause", detail: Self.motionDetail, systemImage: "figure.run", color: .green)
                    } else {
                        row("Auto-pause", detail: "Stops the clock when you stand still, using GPS.", systemImage: "pause.circle.fill", color: .green)
                    }
                }
            } header: {
                Text(Self.deviceHeader)
            } footer: {
                Text(setup.countsSteps
                    ? "Apple asks about Motion & Fitness and your location when you start your first run."
                    : "Apple asks about your location when you start your first run.")
            }

            #if os(iOS)
            Section {
                HStack(spacing: 12) {
                    icon("scalemass.fill", color: .indigo)
                    Text("Weight")
                    Spacer()
                    TextField(setup.usesHealth ? "From Health" : "Optional", text: $setup.weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($isTypingWeight)
                        .frame(maxWidth: 120)
                        .accessibilityLabel(setup.unit == .miles ? "Weight in pounds" : "Weight in kilograms")
                    Text(setup.unit == .miles ? "lb" : "kg")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            } header: {
                Text("For calories")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    // Says why Continue is greyed out, such as a weight typed in stone.
                    if let problem = setup.weightProblem {
                        Text(problem)
                            .foregroundStyle(.red)
                    }
                    Text(setup.usesHealth
                        ? "Wind Run works out the calories each run burns from your weight. Leave it empty to use the one in Health."
                        : "Wind Run works out the calories each run burns from your weight. You can add it later in Settings.")
                }
            }
            #endif

            #if os(watchOS)
            // The watch has no room below the form, so the buttons scroll with it.
            Section {
                buttons
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            #endif
        }
        #if os(iOS)
        .safeAreaInset(edge: .bottom) {
            buttons
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(.bar)
        }
        .toolbar {
            // A number pad has no return key, so this puts it away.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isTypingWeight = false }
            }
        }
        #endif
        .disabled(queue.isAccepting)
    }

    private var buttons: some View {
        VStack(spacing: Self.buttonSpacing) {
            Button {
                Task { await queue.accept(FirstOpenSetup.id) }
            } label: {
                ZStack {
                    // Keeps the button's size while the spinner shows, such as while Apple's Health sheet is up.
                    Text("Continue")
                        .opacity(queue.isAccepting ? 0 : 1)
                    if queue.isAccepting {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.onAccent)
            }
            .buttonStyle(.borderedProminent)
            #if os(iOS)
            .controlSize(.large)
            #endif
            .disabled(!setup.canContinue)

            Button {
                queue.decline(FirstOpenSetup.id)
            } label: {
                Text("Not Now")
                    .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .buttonStyle(.borderless)
            .controlSize(.large)
            #endif
        }
    }

    private func row(_ title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            #if os(iOS)
            icon(systemImage, color: color)
            #endif
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func icon(_ systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: .rect(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    #if os(watchOS)
    private static let titleFont = Font.headline
    private static let introFont = Font.footnote
    private static let buttonSpacing: CGFloat = 6
    private static let deviceHeader: LocalizedStringKey = "This watch"
    private static let heartRateDetail: LocalizedStringKey = "Kept with each run."
    private static let motionDetail: LocalizedStringKey = "Uses Motion & Fitness."
    #else
    private static let titleFont = Font.largeTitle.bold()
    private static let introFont = Font.subheadline
    private static let buttonSpacing: CGFloat = 4
    private static let deviceHeader: LocalizedStringKey = "This iPhone"
    private static let heartRateDetail: LocalizedStringKey = "From Apple Watch, AirPods Pro 3, Powerbeats Pro 2 or a Bluetooth strap, kept with each run."
    private static let motionDetail: LocalizedStringKey = "Uses Motion & Fitness, and the barometer to measure hills for climb and calories."
    #endif
}

private extension DistanceUnit {
    /// "km, kg" or "mi, lb", short enough for a segmented control.
    var shortExamples: String {
        switch self {
        case .kilometers: "km, kg"
        case .miles: "mi, lb"
        }
    }
}

#Preview("First-open setup") {
    let setup = FirstOpenSetup(offersHealth: true, countsSteps: true)
    FirstOpenSetupView(setup: setup, queue: PromptQueue(prompts: [.settingUp(setup)]))
}
