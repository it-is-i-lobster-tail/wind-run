import SwiftUI

struct WorkoutIconPicker: View {
    let automaticIcon: String
    @Binding var manualIcon: String?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        choice("Automatic", glyph: automaticIcon, value: nil)
                    }
                    Section("Browse symbols") {
                        ForEach(WorkoutSymbolEntry.sections, id: \.title) { section in
                            NavigationLink(section.title) {
                                List(section.entries) { item in
                                    choice(item.title, glyph: item.id, value: item.id)
                                }
                                .navigationTitle(section.title)
                            }
                        }
                    }
                    Section("Quick picks") {
                        ForEach(WorkoutSymbol.catalog) { symbol in
                            choice(symbol.title, glyph: symbol.id, value: symbol.id)
                        }
                    }
                } else {
                    let results = WorkoutSymbolEntry.search(search)
                    if results.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                    ForEach(results, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.entries) { item in
                                choice(item.title, glyph: item.id, value: item.id)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search workout symbols")
            .navigationTitle("Workout icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func choice(_ title: String, glyph: String, value: String?) -> some View {
        Button {
            select(value)
        } label: {
            HStack {
                WorkoutGlyph(value: glyph)
                Text(title)
                Spacer()
                if manualIcon == value {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(manualIcon == value ? .isSelected : [])
    }

    private func select(_ value: String?) {
        manualIcon = value
        dismiss()
    }
}
