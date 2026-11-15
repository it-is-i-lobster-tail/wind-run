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
    @State private var files: [TraceFile] = []
    @State private var isConfirmingExport = false
    @State private var isPreparingZip = false
    @State private var zip: TraceZip?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: traceLogging) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trace logging")
                            Text("Logs every action taken in the app, for debugging. Not recommended.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
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

    /// Turning on waits for the warning to be accepted. Turning off deletes the files straight away.
    private var traceLogging: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { turnsOn in
                if turnsOn {
                    isWarning = true
                } else {
                    Trace.tap(Self.screen, "Trace logging", ["on": false])
                    TraceFiles.shared.turnOff()
                    TraceZip.deleteMadeZips()
                    isOn = false
                    refresh()
                }
            }
        )
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
        Trace logging completely logs every action taken in Wind Run, such as every tap, screen, setting \
        change, save and run event, at the most detailed level. It's for debugging and developer improvement, \
        and is not recommended.

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
            Text("\(DeveloperToolView.size(file.bytes)) · \(file.started.formatted(date: .abbreviated, time: .shortened)) to \(file.lastWritten.formatted(date: .omitted, time: .shortened))")
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
