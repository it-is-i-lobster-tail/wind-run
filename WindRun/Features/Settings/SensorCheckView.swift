//
//  SensorCheckView.swift
//  Wind Run
//
//  Check Sensors: what's set up for heart rate, GPS, steps and Health, with a fix beside each problem, and a
//  one-minute live test that shows readings as they come in.
//

import SwiftUI

struct SensorCheckView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var check: SensorCheck

    /// Off while a run is going: the run's own workout session is using heart rate, and only one can run.
    private let allowsLiveTest: Bool
    /// Shown in a sheet over the run screen, with its own Done button.
    private let showsDone: Bool

    init(check: SensorCheck? = nil, allowsLiveTest: Bool = true, showsDone: Bool = false) {
        #if DEBUG
        _check = State(initialValue: check ?? SensorCheckDemo.check ?? SensorCheck())
        #else
        _check = State(initialValue: check ?? SensorCheck())
        #endif
        self.allowsLiveTest = allowsLiveTest
        self.showsDone = showsDone
    }

    var body: some View {
        ScrollViewReader { proxy in
            form
                #if DEBUG
                // `-sensorCheckDemo live` scrolls down to the live test.
                .task {
                    guard SensorCheckDemo.variant == "live" else { return }
                    try? await Task.sleep(for: .milliseconds(400))
                    proxy.scrollTo(Self.liveTestID, anchor: .top)
                }
                #endif
        }
    }

    private static let liveTestID = "liveTest"

    private var form: some View {
        Form {
            Section {
                ForEach(check.setupRows) { row in
                    SensorRowView(row: row, screen: "Check Sensors")
                }
            } header: {
                Text("Setup")
            }

            if allowsLiveTest {
                liveTest
                    .id(Self.liveTestID)
            } else {
                Section {
                } footer: {
                    Text("The live test can run once this run is finished: the run is using heart rate now.")
                }
            }
        }
        .sensorFixes { check.refresh() }
        .navigationTitle("Check Sensors")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Trace.tap("Check Sensors", "Done")
                        dismiss()
                    }
                }
            }
        }
        .traceScreen("Check Sensors")
        .onAppear { check.refresh() }
        // Permissions can change in the Settings app, and nothing is tested in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                check.refresh()
            } else if phase == .background {
                check.stop()
            }
        }
        .onDisappear { check.stop() }
    }

    /// Ticks each second while the test runs, for the time left and the heart rate wait. A TimelineView
    /// around a Section would break the Form's grouping.
    @State private var now = Date.now

    private var liveTest: some View {
        let elapsed = check.elapsed(at: now)
        return Section {
            if check.isRunning || check.finishedAt != nil {
                ForEach(check.liveRows(at: now)) { row in
                    SensorRowView(row: row, screen: "Check Sensors")
                }
            }
            if check.isRunning {
                ProgressView(value: elapsed, total: check.duration)
                    .tint(.accentColor)
                    .accessibilityLabel("Live test")
                    .accessibilityValue("\(Int(check.duration - elapsed)) seconds left")
            }
            Button(check.isRunning ? "Stop Test" : (check.finishedAt == nil ? "Start Test" : "Test Again"),
                   systemImage: check.isRunning ? "stop.fill" : "play.fill") {
                Trace.tap("Check Sensors", check.isRunning ? "Stop Test" : "Start Test")
                if check.isRunning { check.stop() } else { check.start(.test) }
            }
            .frame(maxWidth: .infinity)
        } header: {
            Text(header(elapsed: elapsed))
        } footer: {
            Text("Put your AirPods in or your strap on, then start. The test runs a workout session that's thrown away, so nothing is saved to Health or your runs. GPS shows its accuracy only, never where you are.")
        }
        .task(id: check.isRunning) {
            now = .now
            while check.isRunning, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }

    /// "Live test", "Live test · 0:38 left" or "Live test · done".
    private func header(elapsed: TimeInterval) -> String {
        if check.isRunning {
            return "Live test · \(RunFormat.duration((check.duration - elapsed).rounded(.up))) left"
        }
        return check.finishedAt == nil ? "Live test" : "Live test · done"
    }
}

/// A check's status, as a small filled symbol.
struct SensorStatusDot: View {
    let state: SensorState
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch state {
        case .ok: "checkmark.circle.fill"
        case .problem, .warning: "exclamationmark.circle.fill"
        case .waiting: "ellipsis.circle.fill"
        case .notUsed: "minus.circle.fill"
        }
    }

    var color: Color {
        switch state {
        case .ok: .green
        case .problem: .red
        case .warning: .orange
        case .waiting, .notUsed: Color(uiColor: .systemGray2)
        }
    }

    private var label: String {
        switch state {
        case .ok: "OK"
        case .problem: "Problem"
        case .warning: "Warning"
        case .waiting: "Waiting"
        case .notUsed: "Not used"
        }
    }
}

/// One check: its status, title and sentence, and a fix button on the right.
struct SensorRowView: View {
    let row: SensorRow
    /// For the trace: which screen the fix was tapped on.
    let screen: String

    @Environment(\.performSensorFix) private var performFix

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            SensorStatusDot(state: row.state)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.body.weight(.semibold))
                    if let bpm = row.beatsPerMinute {
                        Label("\(bpm)", systemImage: "heart.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.body.weight(.bold).monospacedDigit())
                            .foregroundStyle(.red)
                            .accessibilityLabel("\(bpm) beats per minute")
                            .contentTransition(.numericText())
                    }
                }
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let fix = row.fix {
                Button(fix.title) {
                    performFix(fix, row: row.id, from: screen)
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .tint(.accentColor)
                .accessibilityHint(hint(for: fix))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func hint(for fix: SensorFix) -> String {
        switch fix {
        case .turnOnHeartRate: "Turns on heart rate, which asks Health"
        case .turnOnSteps: "Turns on steps, which asks for Motion & Fitness"
        case .openSettings: "Opens Wind Run's settings"
        case .healthSettings: "Says where to allow Workouts in Health"
        }
    }
}

// MARK: - Fixes

/// Carries out a check's fix. Set up by `sensorFixes(refresh:)`.
struct PerformSensorFix {
    fileprivate var action: (SensorFix, SensorKind, String) -> Void

    func callAsFunction(_ fix: SensorFix, row: SensorKind, from screen: String) {
        action(fix, row, screen)
    }
}

extension EnvironmentValues {
    @Entry var performSensorFix = PerformSensorFix { _, _, _ in }
}

extension View {
    /// Lets the sensor rows inside carry out their fixes, calling `refresh` once one is done.
    func sensorFixes(refresh: @escaping () -> Void) -> some View {
        modifier(SensorFixHandler(refresh: refresh))
    }
}

private struct SensorFixHandler: ViewModifier {
    let refresh: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isExplainingHealth = false

    func body(content: Content) -> some View {
        content
            .environment(\.performSensorFix, PerformSensorFix { fix, row, screen in
                Trace.tap(screen, "Fix: \(fix.rawValue)", ["row": row.rawValue])
                perform(fix)
            })
            .alert("Allow Workouts in Health", isPresented: $isExplainingHealth) {
                Button("Open Settings") { openSettings() }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Heart rate and Apple's distance come from a workout session, which Health has to allow. In Settings, open Privacy & Security › Health › Wind Run, and allow Workouts and Heart Rate.")
            }
    }

    private func perform(_ fix: SensorFix) {
        switch fix {
        case .turnOnHeartRate:
            Task {
                await HeartRateMonitor.turnOn()
                refresh()
            }
        case .turnOnSteps:
            UserDefaults.standard.set(true, forKey: MotionMonitor.stepsKey)
            Task {
                // Steps need Motion & Fitness, and go back off without it, as in Settings.
                if !(await MotionMonitor.requestAccess()) {
                    UserDefaults.standard.set(false, forKey: MotionMonitor.stepsKey)
                }
                refresh()
            }
        case .openSettings:
            openSettings()
        case .healthSettings:
            isExplainingHealth = true
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

#Preview("Check Sensors") {
    NavigationStack { SensorCheckView() }
}
