//
//  DeveloperToolView.swift
//  Wind Run
//

import SwiftUI

/// Settings → Developer Tool: the Trace logging switch, the trace files, and exporting them as a zip.
struct DeveloperToolView: View {
    private static let screen = "Developer Tool"

    @State private var isOn = Trace.isOn
    @State private var isWarning = false
    @State private var isConfirmingTurnOff = false
    @State private var files: [TraceFile] = []
    @State private var isConfirmingExport = false
    @State private var isPreparingZip = false
    @State private var zip: TraceZip?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: traceLogging) {
                    SettingsRowLabel(
                        title: "Trace logging",
                        detail: "Records every action in the app, for debugging. Leave it off unless you're reporting a problem."
                    ) {
                        Image(systemName: "ladybug")
                    }
                }
            } footer: {
                if isOn {
                    Text("Keeps up to \(TraceFiles.defaultMaximumFiles) files of \(Self.maximumFileSize) each on this iPhone, deleting the oldest as new ones start. Turning it off deletes them all.")
                } else {
                    Text("Off. Nothing is being logged.")
                }
            }

            if isOn || !files.isEmpty {
                Section {
                    if files.isEmpty {
                        Text("No trace files yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(files) { file in
                        NavigationLink {
                            TraceFileView(file: file) { refresh() }
                        } label: {
                            TraceFileRow(file: file)
                        }
                    }
                    .onDelete { offsets in
                        for file in offsets.map({ files[$0] }) {
                            Trace.tap(Self.screen, "Swipe to delete a trace file", ["file": file.number])
                            TraceFiles.shared.delete(file)
                        }
                        refresh()
                    }
                } header: {
                    Text("Trace Files")
                } footer: {
                    if !files.isEmpty {
                        Text("\(files.count) of \(TraceFiles.defaultMaximumFiles) files, \(Self.size(files.map(\.bytes).reduce(0, +))) in all. Swipe a file to delete it.")
                    }
                }

                Section {
                    Button {
                        Trace.tap(Self.screen, "Export All as Zip")
                        isConfirmingExport = true
                    } label: {
                        Label {
                            Text("Export All as Zip")
                        } icon: {
                            if isPreparingZip {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    .disabled(files.isEmpty || isPreparingZip)
                } footer: {
                    Text(exportError ?? "Puts every trace file in one zip, to share or save in Files.")
                }
            }
        }
        .navigationTitle(Self.screen)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Turn On Trace Logging?", isPresented: $isWarning) {
            Button("Cancel", role: .cancel) {
                Trace.tap(Self.screen, "Trace logging warning: Cancel")
            }
            Button("Turn On") {
                turnOn()
            }
        } message: {
            Text(Self.warning)
        }
        .alert("Turn Off Trace Logging?", isPresented: $isConfirmingTurnOff) {
            Button("Turn Off and Delete \(files.count == 1 ? "1 File" : "\(files.count) Files")", role: .destructive) {
                Trace.tap(Self.screen, "Turn off: Turn Off and Delete", ["files": files.count])
                turnOff()
            }
            Button("Export First") {
                Trace.tap(Self.screen, "Turn off: Export First")
                isConfirmingExport = true
            }
            Button("Cancel", role: .cancel) {
                Trace.tap(Self.screen, "Turn off: Cancel")
            }
        } message: {
            Text("Turning it off deletes every trace file on this iPhone. Export them first to keep them.")
        }
        .alert("Export Trace Files?", isPresented: $isConfirmingExport) {
            Button("Cancel", role: .cancel) {
                Trace.tap(Self.screen, "Export warning: Cancel")
            }
            Button("Export") {
                Trace.tap(Self.screen, "Export warning: Export")
                makeZip()
            }
        } message: {
            Text(TraceZip.privacyNote)
        }
        .sheet(item: $zip, onDismiss: {
            Trace.log(.app, "Share sheet closed")
            TraceZip.deleteMadeZips()
        }) { zip in
            ShareSheet(items: [zip.url])
                .ignoresSafeArea()
                .presentationDetents([.medium, .large])
        }
        .traceScreen(Self.screen)
        .task {
            // Sizes grow as lines are written, so the list keeps up while it's on screen.
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Turning on waits for the warning to be accepted. Turning off asks first while there are files, since
    /// it deletes them and they can't be got back.
    private var traceLogging: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { turnsOn in
                Trace.tap(Self.screen, "Trace logging", ["on": turnsOn])
                if turnsOn {
                    isWarning = true
                } else if files.isEmpty {
                    turnOff()
                } else {
                    isConfirmingTurnOff = true
                }
            }
        )
    }

    private func turnOff() {
        TraceFiles.shared.turnOff()
        TraceZip.deleteMadeZips()
        isOn = false
        refresh()
    }

    private func turnOn() {
        TraceFiles.shared.turnOn()
        TraceHooks.installIfOn()
        isOn = true
        Trace.tap(Self.screen, "Trace logging warning: Turn On")
        refresh()
    }

    private func refresh() {
        files = TraceFiles.shared.files()
    }

    private func makeZip() {
        isPreparingZip = true
        exportError = nil
        Task {
            do {
                zip = try await TraceZip.make()
                Trace.log(.app, "Made the trace zip", ["files": files.count])
            } catch {
                exportError = "Couldn't make the zip. Try again."
                Trace.error("Couldn't make the trace zip", error)
            }
            isPreparingZip = false
        }
    }

    static let warning = """
        Trace logging records every tap, screen, setting change, save and run event in Wind Run, for \
        debugging. It uses up to \(size(TraceFiles.defaultMaximumFiles * TraceFiles.defaultMaximumFileBytes)) on \
        this iPhone and a little extra battery, so leave it off unless you're reporting a problem.

        The logs stay on this iPhone unless you share them, and leave out locations, typed text, names, notes, \
        and body and health readings. Turning it off deletes them.
        """

    static let maximumFileSize = size(TraceFiles.defaultMaximumFileBytes)

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

private struct TraceFileRow: View {
    let file: TraceFile

    /// "Nov 15, 2026 at 9:02 AM to 8:40 AM", with the end's date too when the file went on past that day.
    private var span: String {
        let sameDay = Calendar.current.isDate(file.started, inSameDayAs: file.lastWritten)
        let start = file.started.formatted(date: .abbreviated, time: .shortened)
        let end = file.lastWritten.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
        return "\(start) to \(end)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(file.name)
                if file.isCurrent {
                    Text("Writing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text("\(DeveloperToolView.size(file.bytes)) · \(span)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The system share sheet, which also offers Save to Files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview("Developer Tool") {
    NavigationStack {
        DeveloperToolView()
    }
}
