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
    /// Every line of the file, or nil while it's read.
    @State private var lines: [Line]?
    /// The lines the search matches, or every line with no search.
    @State private var shown: [Line] = []
    @State private var search = ""
    @State private var isConfirmingDelete = false
    /// The line to scroll to once it's on the page, for "Latest" after the file is read again.
    @State private var latestTarget: Int?

    /// One line, numbered from 0 in the file.
    nonisolated struct Line: Identifiable, Sendable {
        let id: Int
        let text: String
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if lines != nil {
                    if shown.isEmpty {
                        ContentUnavailableView(search.isEmpty ? "No Lines" : "No Matches", systemImage: "doc.text.magnifyingglass")
                    } else {
                        ScrollView([.vertical]) {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(shown) { line in
                                    Text(line.text)
                                        .font(.caption2.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(line.id)
                                }
                            }
                            .padding(.horizontal)
                            .textSelection(.enabled)
                        }
                        .onChange(of: latestTarget) { _, target in
                            guard let target else { return }
                            proxy.scrollTo(target, anchor: .bottom)
                            latestTarget = nil
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .bottomBar) {
                                Button("Top", systemImage: "arrow.up.to.line") {
                                    Trace.tap(Self.screen, "Jump to top")
                                    proxy.scrollTo(shown.first?.id, anchor: .top)
                                }
                                Spacer()
                                Text("\(shown.count) lines")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Latest", systemImage: "arrow.down.to.line") {
                                    Trace.tap(Self.screen, "Jump to latest", ["reloads": file.isCurrent])
                                    if file.isCurrent {
                                        // The file being written has more lines by now.
                                        Task {
                                            await load()
                                            latestTarget = shown.last?.id
                                        }
                                    } else {
                                        proxy.scrollTo(shown.last?.id, anchor: .bottom)
                                    }
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
        .alert("Delete “\(file.name)”?", isPresented: $isConfirmingDelete) {
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
        .task { await load() }
        .task(id: search) {
            // Waits for a pause in typing, so a 5 MB file isn't searched again on every letter.
            guard lines != nil else { return }
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await filter()
        }
    }

    /// Reads the file and splits it into lines, off the main actor.
    private func load() async {
        let file = file
        lines = await Task.detached(priority: .userInitiated) {
            Self.splitLines(TraceFiles.shared.contents(of: file) ?? "")
        }.value
        await filter()
    }

    /// Finds the lines the search matches, off the main actor. A search changed meanwhile wins.
    private func filter() async {
        guard let lines else { return }
        let search = search
        let matches = await Task.detached(priority: .userInitiated) {
            Self.matching(lines, search)
        }.value
        guard search == self.search else { return }
        shown = matches
    }

    nonisolated static func splitLines(_ text: String) -> [Line] {
        text.split(separator: "\n").enumerated().map { Line(id: $0.offset, text: String($0.element)) }
    }

    nonisolated static func matching(_ lines: [Line], _ search: String) -> [Line] {
        guard !search.isEmpty else { return lines }
        return lines.filter { $0.text.range(of: search, options: .caseInsensitive) != nil }
    }
}
