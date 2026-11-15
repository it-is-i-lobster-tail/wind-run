//
//  ExportRunsRow.swift
//  Wind Run
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Your Data → Export Runs: warns what the files hold, makes them, then lets the runner save
/// the folder in Files. Nothing is sent anywhere: the files only leave the iPhone if the runner shares them.
struct ExportRunsRow: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isWarning = false
    @State private var isPreparing = false
    @State private var isExporting = false
    @State private var document: RunExportFolder?
    @State private var outcome: String?

    var body: some View {
        Button {
            isWarning = true
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Runs")
                    Text(outcome ?? "Saves your runs to Files as CSV, without locations or personal details, for looking at in a spreadsheet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                if isPreparing {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .disabled(isPreparing)
        .alert("Export Your Runs?", isPresented: $isWarning) {
            Button("Export", action: prepare)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(RunExport.privacyNote)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: .folder,
            defaultFilename: RunExport.folderName
        ) { result in
            switch result {
            case .success:
                outcome = "Saved to Files."
            case .failure(let error):
                outcome = "Couldn't save: \(error.localizedDescription)"
            }
            document = nil
        }
    }

    private func prepare() {
        isPreparing = true
        outcome = nil
        Task {
            // Let the button show it's working before the runs are read.
            await Task.yield()
            let runs = (try? modelContext.fetch(FetchDescriptor<Run>())) ?? []
            document = RunExportFolder(files: RunExport.make(runs))
            isPreparing = false
            isExporting = true
        }
    }
}

/// The export as a folder holding `runs.csv` and `fixes.csv`, for `fileExporter`.
nonisolated struct RunExportFolder: FileDocument {
    static let readableContentTypes: [UTType] = [.folder]
    static let writableContentTypes: [UTType] = [.folder]

    var files: RunExport.Files

    init(files: RunExport.Files) {
        self.files = files
    }

    init(configuration: ReadConfiguration) throws {
        let wrappers = configuration.file.fileWrappers ?? [:]
        func text(_ name: String) -> String {
            wrappers[name]?.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        files = RunExport.Files(runs: text("runs.csv"), fixes: text("fixes.csv"))
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: [
            "runs.csv": FileWrapper(regularFileWithContents: Data(files.runs.utf8)),
            "fixes.csv": FileWrapper(regularFileWithContents: Data(files.fixes.utf8)),
        ])
    }
}
