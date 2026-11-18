//
//  EditDisplayView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Where the runner builds one of their saved displays: its name, then a preview of the run screen, the
/// Watch or the Lock Screen with sample numbers, where tapping any of the six spots picks what it shows.
/// Changes save as they're made and follow the runner to the Watch and their other devices.
struct EditDisplayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var screen: DisplayScreen
    @State private var name: String
    @State private var isDefault: Bool
    @State private var isFull: Bool
    @State private var picking: DisplaySlot?
    @State private var device = PreviewDevice.iPhone
    @State private var isConfirmingReset = false
    @State private var isConfirmingDelete = false

    /// Which device's layout the preview shows.
    enum PreviewDevice: String, CaseIterable, Identifiable {
        case iPhone
        case watch
        case lockScreen

        var id: Self { self }

        var name: String {
            switch self {
            case .iPhone: "iPhone"
            case .watch: "Watch"
            case .lockScreen: "Lock Screen"
            }
        }
    }

    /// Opens on the display with `screenID`, or the default when it's nil or was deleted.
    init(screenID: UUID? = nil, picking: DisplaySlot? = nil, device: PreviewDevice = .iPhone) {
        let library = DisplayLibrary.current
        let screen = library.screen(id: screenID)
        _screen = State(initialValue: screen)
        _name = State(initialValue: screen.name)
        _isDefault = State(initialValue: library.isDefault(screen.id))
        _isFull = State(initialValue: library.isFull)
        _picking = State(initialValue: picking)
        _device = State(initialValue: device)
    }

    var body: some View {
        let readings = screen.readings(.sample(unit: unit))
        Form {
            Section {
                TextField(DisplayLibrary.newName, text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onChange(of: name) { _, typed in
                        switch DisplayLibrary.nameEdit(typed: typed, current: screen.name) {
                        case .cut(let cut):
                            name = cut
                        case .rename(let trimmed):
                            screen.name = trimmed
                            save()
                        case .keep:
                            break
                        }
                    }
            } header: {
                Text("Name")
            }

            Section {
                Picker("Preview", selection: $device) {
                    ForEach(PreviewDevice.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                preview(readings)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: LayoutMetrics.sectionSpacing, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            } footer: {
                Text("Tap any number to change what it shows. Runs that use this display show these six on your run screen, Apple Watch and Lock Screen. Sample numbers shown.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, LayoutMetrics.compactSpacing)
            }

            Section("Spots") {
                ForEach(DisplaySlot.all) { slot in
                    Button {
                        Trace.tap("Edit Display", "Spot: \(slot.name)")
                        picking = slot
                    } label: {
                        LabeledContent(slot.name) {
                            HStack(spacing: 6) {
                                Text(screen[slot].name)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            Section {
                if !isDefault {
                    Button("Make Default") {
                        Trace.tap("Edit Display", "Make Default")
                        var library = DisplayLibrary.current
                        library.makeDefault(screen.id)
                        library.save()
                        withAnimation { isDefault = true }
                    }
                }
                Button("Duplicate") {
                    Trace.tap("Edit Display", "Duplicate")
                    duplicate()
                }
                .disabled(isFull)
            } footer: {
                Text(isDefault
                    ? "This is your default: it shows on any run that doesn't pick another display."
                    : "Make it the default to show it on every run that doesn't pick another display.")
            }

            if !screen.hasStandardSpots {
                Section {
                    // It replaces all six choices at once, so it asks first.
                    Button("Reset to Standard", role: .destructive) {
                        Trace.tap("Edit Display", "Reset to Standard")
                        isConfirmingReset = true
                    }
                    .confirmationDialog("Reset all six spots to Standard?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                        Button("Reset to Standard", role: .destructive) {
                            Trace.tap("Edit Display", "Reset all six spots to Standard?: Reset")
                            withAnimation { screen.reset() }
                            save()
                        }
                    } message: {
                        Text("Your own choices for each spot on this display are replaced, here and on your Apple Watch.")
                    }
                } footer: {
                    Text("Standard shows elapsed time and distance, then current pace, heart rate, elevation from start and cadence.")
                }
            }

            if !isDefault {
                Section {
                    Button("Delete Display", role: .destructive) {
                        Trace.tap("Edit Display", "Delete Display")
                        isConfirmingDelete = true
                    }
                    .confirmationDialog("Delete “\(screen.name)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                        Button("Delete Display", role: .destructive) {
                            Trace.tap("Edit Display", "Delete display?: Delete Display")
                            DisplayActions.delete(screen.id, in: modelContext)
                            dismiss()
                        }
                    } message: {
                        Text(DisplayActions.deleteMessage(.current))
                    }
                }
            }
        }
        .navigationTitle("Edit Display")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Edit Display")
        .sheet(item: $picking) { slot in
            DisplayMetricPicker(slot: slot, screen: screen, unit: unit) { metric in
                Trace.tap("Edit Display", "Picked", ["spot": slot.name, "metric": metric.rawValue])
                withAnimation { screen.place(metric, in: slot) }
                save()
            }
        }
        // A name left blank reads as the one kept.
        .onDisappear { name = screen.name }
    }

    /// Keeps the display as it is now in the saved displays.
    private func save() {
        var library = DisplayLibrary.current
        library.update(screen)
        library.save()
    }

    /// Makes a copy of this display and carries on editing the copy.
    private func duplicate() {
        var library = DisplayLibrary.current
        guard let copy = DisplayActions.add(copying: screen, to: &library) else { return }
        withAnimation {
            screen = copy
            name = copy.name
            isDefault = false
            isFull = library.isFull
        }
    }

    // MARK: - Previews

    @ViewBuilder
    private func preview(_ readings: DisplayScreenReadings) -> some View {
        switch device {
        case .iPhone: phonePreview(readings)
        case .watch: watchPreview(readings)
        case .lockScreen: lockScreenPreview(readings)
        }
    }

    private func phonePreview(_ readings: DisplayScreenReadings) -> some View {
        let style = RunDisplayScreenView.style.scaled(by: 0.72)
        return VStack(spacing: LayoutMetrics.compactSpacing) {
            spot(.primary) {
                DisplayHeadline(reading: readings.primary, size: style.primarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
            }
            spot(.secondary) {
                DisplayHeadline(reading: readings.secondary, size: style.secondarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
            }
            tileGrid(readings.tiles, style: style)
                .padding(.top, LayoutMetrics.compactSpacing)
        }
        .padding(LayoutMetrics.sectionSpacing)
        .frame(maxWidth: 360)
        .background(Color(.systemBackground), in: .rect(cornerRadius: LayoutMetrics.curvedCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: LayoutMetrics.curvedCornerRadius).strokeBorder(.quaternary))
    }

    private func watchPreview(_ readings: DisplayScreenReadings) -> some View {
        let style = DisplaySizes.watchPreview
        return VStack(spacing: 4) {
            spot(.primary) {
                DisplayHeadline(reading: readings.primary, size: style.primarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
            }
            spot(.secondary) {
                DisplayHeadline(reading: readings.secondary, size: style.secondarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
            }
            tileGrid(readings.tiles, style: style)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: 220)
        .background(Color.black, in: .rect(cornerRadius: 44))
        .overlay(RoundedRectangle(cornerRadius: 44).strokeBorder(Color.gray.opacity(0.5), lineWidth: 6))
        .environment(\.colorScheme, .dark)
    }

    /// The Lock Screen as the Live Activity draws it: both headlines the same size, side by side, with the
    /// pause button beside them, then the grid in one row.
    private func lockScreenPreview(_ readings: DisplayScreenReadings) -> some View {
        let style = DisplaySizes.lockScreen.scaled(by: 0.8)
        return VStack(spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .center, spacing: 10) {
                spot(.primary) {
                    DisplayHeadline(reading: readings.primary, size: style.primarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
                }
                spot(.secondary) {
                    DisplayHeadline(reading: readings.secondary, size: style.secondarySize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
                }
                Image(systemName: "pause.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor, in: .circle)
                    .accessibilityHidden(true)
            }
            DisplayTileRow(tiles: readings.tiles, style: style) { index, tile in
                spot(.tile(index)) { tile }
            }
        }
        .padding(14)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .padding(LayoutMetrics.sectionSpacing)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.15)], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: LayoutMetrics.curvedCornerRadius)
        )
    }

    /// The grid as the run screen and the Watch lay it out, each tile a spot to tap.
    private func tileGrid(_ tiles: [DisplayReading], style: DisplayStyle) -> some View {
        DisplayTileGrid(tiles: tiles, style: style) { index, tile in
            spot(.tile(index)) { tile }
        }
    }

    /// One spot in a preview, outlined so it reads as something to tap.
    private func spot(_ slot: DisplaySlot, @ViewBuilder content: () -> some View) -> some View {
        Button {
            Trace.tap("Edit Display", "Preview spot: \(slot.name)")
            picking = slot
        } label: {
            content()
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .overlay(
                    RoundedRectangle(cornerRadius: LayoutMetrics.compactCornerRadius)
                        .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Changes what \(slot.phrase) shows")
    }
}

/// Every metric a spot can show, in groups, each with what it shows and a sample.
struct DisplayMetricPicker: View {
    let slot: DisplaySlot
    let screen: DisplayScreen
    let unit: DistanceUnit
    let pick: (DisplayMetric) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let sample = RunSnapshot.sample(unit: unit)
        let foundAny = DisplayMetric.allCases.contains(where: matches)
        NavigationStack {
            List {
                ForEach(DisplayMetricCategory.allCases) { category in
                    let metrics = category.metrics.filter(matches)
                    if !metrics.isEmpty {
                        Section(category.name) {
                            ForEach(metrics) { metric in
                                row(metric, sample: metric.reading(sample))
                            }
                        }
                    }
                }
            }
            .overlay {
                if !foundAny {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Search data")
            .navigationTitle(slot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .traceScreen("Edit Display picker")
    }

    private func matches(_ metric: DisplayMetric) -> Bool {
        let text = search.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || metric.name.localizedCaseInsensitiveContains(text) || metric.summary.localizedCaseInsensitiveContains(text)
    }

    private func row(_ metric: DisplayMetric, sample: DisplayReading) -> some View {
        let current = screen[slot]
        let elsewhere = screen.slot(showing: metric, otherThan: slot)
        return Button {
            pick(metric)
            dismiss()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.compactSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.name)
                        .font(.body.weight(metric == current ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(metric.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    // What this runner's settings leave blank, so it isn't only found out mid-run.
                    if let needs = metric.missingRequirement() {
                        Label(needs, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if let elsewhere {
                        Text("Now in \(elsewhere.phrase). Picking it swaps the two.")
                            .font(.footnote)
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: LayoutMetrics.compactSpacing)
                Text([sample.value, sample.unit].compactMap { $0 }.joined(separator: " "))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                if metric == current {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(metric == current ? .isSelected : [])
    }
}

extension DisplayMetric {
    private static let heartRateOff = "Shows a dash until heart rate is on in Settings."

    /// What's missing for this to show anything on this runner's setup, or nil when nothing is.
    func missingRequirement(in defaults: UserDefaults = .standard) -> String? {
        switch self {
        case .calories:
            BodyWeight.kilograms(in: defaults) == nil ? "Shows a dash until you add your weight in Settings." : nil
        case .cadence, .strideLength:
            defaults.bool(forKey: MotionMonitor.stepsKey) ? nil : "Shows a dash until Steps and cadence is on in Settings."
        case .heartRate, .averageHeartRate:
            defaults.bool(forKey: HeartRateMonitor.storageKey) ? nil : Self.heartRateOff
        case .heartRateZone:
            if !defaults.bool(forKey: HeartRateMonitor.storageKey) {
                Self.heartRateOff
            } else if HeartRateMax.value(in: defaults) == nil {
                "Shows a dash until you've run with heart rate once."
            } else {
                nil
            }
        default:
            nil
        }
    }
}

#Preview("Edit Display") {
    NavigationStack { EditDisplayView() }
}

#Preview("Picker") {
    DisplayMetricPicker(slot: .tile(0), screen: .standard, unit: .kilometers) { _ in }
}
