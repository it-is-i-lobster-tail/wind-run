//
//  ExportRunsRow.swift
//  Wind Run
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Your Data → Export Runs: says what the files hold, lets the runner pick `runs.csv`,
/// `gps_points.csv` or both in a zip, makes it, then lets them save it in Files. Nothing is sent anywhere: the
/// files only leave the iPhone if the runner shares them.
struct ExportRunsRow: View {
    private static let screen = "Export Runs"

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isChoosing = false
    @State private var isPreparing = false
    @State private var isExporting = false
    @State private var document: ExportFile?
    /// The choice behind `document`, for the trace.
    @State private var choice: RunExport.Choice?
    /// How the last try went, shown under the description.
    @State private var outcome: String?

    var body: some View {
        Button {
            Trace.tap("Settings", "Export Runs")
            openChoices()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Runs")
                    Text("Saves your runs to Files as CSV, without locations or personal details, for looking at in a spreadsheet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let outcome {
                        Text(outcome)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .default, value: outcome)
            } icon: {
                if isPreparing {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .disabled(isPreparing)
        .confirmationDialog("Export Your Runs?", isPresented: $isChoosing, titleVisibility: .visible) {
            ForEach(RunExport.Choice.allCases) { choice in
                Button(choice.title) { prepare(choice) }
            }
            Button("Cancel", role: .cancel) {
                Trace.tap(Self.screen, "Cancel")
            }
        } message: {
            Text(RunExport.privacyNote)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: document?.contentType ?? .commaSeparatedText,
            defaultFilename: document?.filename
        ) { result in
            switch result {
            case .success:
                outcome = "Saved to Files."
                Trace.log(.data, "Run export saved", ["choice": choice?.rawValue ?? "?"])
            case .failure(let error):
                outcome = "Couldn't save the file. Try again."
                Trace.error("Run export save failed", error)
            }
            document = nil
        } onCancellation: {
            Trace.tap(Self.screen, "Save cancelled")
            document = nil
        }
    }

    /// Asks what to export, or says there's nothing to yet.
    private func openChoices() {
        outcome = nil
        do {
            guard try !finishedRuns().isEmpty else {
                outcome = "No finished runs to export yet."
                Trace.log(.data, "Run export: no finished runs")
                return
            }
            isChoosing = true
        } catch {
            outcome = "Couldn't read your runs. Try again."
            Trace.error("Run export fetch failed", error)
        }
    }

    /// The runs an export holds: the finished ones, oldest first.
    private func finishedRuns() throws -> [Run] {
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.endDateValue != nil }, sortBy: [SortDescriptor(\.startDateValue)])
        // A discarded run has an end too.
        return try modelContext.fetch(descriptor).filter { $0.status == .complete }
    }

    private func prepare(_ choice: RunExport.Choice) {
        Trace.tap(Self.screen, choice.rawValue)
        self.choice = choice
        isPreparing = true
        outcome = nil
        Task {
            let started = Date.now
            do {
                let runs = try finishedRuns()
                // Each run is read here and turned into rows off the main actor, so the screen keeps moving.
                let maker = RunExport.Maker(exportedBy: .current)
                for run in runs {
                    await maker.add(RunExport.Record(run))
                }
                let made = try await maker.export(choice)
                // Counts and how long it took only.
                Trace.log(.data, "Run export made", [
                    "choice": choice.rawValue,
                    "runs": runs.count,
                    "pointRows": made.files.pointRows,
                    "pointsInPrivacyZones": made.files.pointsLeftOut,
                    "bytes": made.data.count,
                    "seconds": Date.now.timeIntervalSince(started),
                ])
                document = ExportFile(data: made.data, contentType: choice.contentType, filename: choice.filename)
                isExporting = true
            } catch {
                outcome = "Couldn't make the export. Try again."
                Trace.error("Run export failed", error)
            }
            isPreparing = false
        }
    }
}

/// One exported file, a CSV or a zip, for `fileExporter`.
nonisolated struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .zip]

    var data: Data
    var contentType: UTType
    var filename: String

    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
        filename = configuration.file.filename ?? RunExport.folderName
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
