//
//  TraceFileView.swift
//  Wind Run
//

import SwiftUI

/// One trace file's lines, oldest at the top, with a search and a Delete button.
struct TraceFileView: View {
    private static let screen = "Trace file"

    let file: TraceFile
    /// Called once the file is deleted, so the list can drop it.
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String]?
    @State private var search = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if let lines {
                    let shown = shownLines(lines)
                    if shown.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "No Lines" : "No Matches", systemImage: "doc.text.magnifyingglass")
                    } else {
                        ScrollView([.vertical]) {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(shown, id: \.offset) { line in
                                    Text(line.element)
                                        .font(.caption2.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(line.offset)
                                }
                            }
                            .padding(.horizontal)
                            .textSelection(.enabled)
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .bottomBar) {
                                Button("Top", systemImage: "arrow.up.to.line") {
                                    Trace.tap(Self.screen, "Jump to top")
                                    proxy.scrollTo(shown.first?.offset, anchor: .top)
                                }
                                Spacer()
                                Text("\(shown.count) lines")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Latest", systemImage: "arrow.down.to.line") {
                                    Trace.tap(Self.screen, "Jump to latest")
                                    proxy.scrollTo(shown.last?.offset, anchor: .bottom)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search lines")
        .onSubmit(of: .search) {
            // Only the length, as with any typed text.
            Trace.tap(Self.screen, "Search", ["length": search.count])
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Trace.tap(Self.screen, "Delete", ["file": file.number])
                    isConfirmingDelete = true
                }
            }
        }
        .confirmationDialog("Delete \(file.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Trace.tap(Self.screen, "Delete confirmed", ["file": file.number])
                TraceFiles.shared.delete(file)
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {
                Trace.tap(Self.screen, "Delete cancelled", ["file": file.number])
            }
        }
        .traceScreen(Self.screen)
        .task {
            let file = file
            let text = await Task.detached(priority: .userInitiated) {
                TraceFiles.shared.contents(of: file) ?? ""
            }.value
            lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
        }
    }

    private func shownLines(_ lines: [String]) -> [EnumeratedSequence<[String]>.Element] {
        let all = Array(lines.enumerated())
        guard !search.isEmpty else { return all }
        return all.filter { $0.element.localizedCaseInsensitiveContains(search) }
    }
}
