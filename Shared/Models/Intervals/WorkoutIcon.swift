import SwiftUI

nonisolated enum WorkoutIcon {
    static let fallback = "repeat"
    static let identifiers = Set(WorkoutSymbolGroup.all.flatMap(\.symbols))

    static func supported(_ value: String?) -> String? {
        guard let value, identifiers.contains(value) else { return nil }
        return value
    }
}

struct WorkoutGlyph: View {
    let value: String?

    var body: some View {
        Image(systemName: value ?? WorkoutIcon.fallback)
            .accessibilityHidden(true)
    }
}
