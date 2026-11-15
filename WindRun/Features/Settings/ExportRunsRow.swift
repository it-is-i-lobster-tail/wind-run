//
//  ExportRunsRow.swift
//  Wind Run
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Your Data → Export Runs: says what the files hold, lets the runner pick `runs.csv`, `fixes.csv`
/// or both in a zip, makes it, then lets them save it in Files. Nothing is sent anywhere: the files only leave
/// the iPhone if the runner shares them.
struct ExportRunsRow: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isChoosing = false
    @State private var isPreparing = false
    @State private var isExporting = false
    @State private var document: ExportFile?
    @State private var outcome: String?

    var body: some View {
        Button {
            isChoosing = true
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
        .confirmationDialog("Export Your Runs?", isPresented: $isChoosing, titleVisibility: .visible) {
            ForEach(RunExport.Choice.allCases) { choice in
                Button(choice.title) { prepare(choice) }
            }
            Button("Cancel", role: .cancel) {}
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
            case .failure(let error):
                outcome = "Couldn't save: \(error.localizedDescription)"
            }
            document = nil
        }
    }

    private func prepare(_ choice: RunExport.Choice) {
        isPreparing = true
        outcome = nil
        Task {
            // Let the button show it's working before the runs are read.
            await Task.yield()
            let runs = (try? modelContext.fetch(FetchDescriptor<Run>())) ?? []
            let files = RunExport.make(runs)
            do {
                let data = try await Task.detached { try RunExport.data(for: choice, from: files) }.value
                document = ExportFile(data: data, contentType: choice.contentType, filename: choice.filename)
                isExporting = true
            } catch {
                outcome = "Couldn't make the export: \(error.localizedDescription)"
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
