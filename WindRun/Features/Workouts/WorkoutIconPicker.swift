import SwiftUI

struct WorkoutIconPicker: View {
    let name: String
    let automaticIcon: String
    @Binding var manualIcon: String?
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice("Automatic", glyph: automaticIcon, value: nil)
                }
                Section("Emoji") {
                    ForEach(WorkoutEmoji.suggestions(name: name, symbol: automaticIcon)) { emoji in
                        choice(emoji.name.capitalized, glyph: emoji.id, value: emoji.id)
                    }
                    TextField("Type or paste one emoji", text: $entry)
                        .autocorrectionDisabled()
                        .onSubmit { if WorkoutIcon.isEmoji(entry) { select(entry) } }
                    Button("Use emoji") { select(entry) }
                        .disabled(!WorkoutIcon.isEmoji(entry))
                }
                Section("Symbols") {
                    ForEach(WorkoutSymbol.catalog) { symbol in
                        choice(symbol.title, glyph: symbol.id, value: symbol.id)
                    }
                }
            }
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
