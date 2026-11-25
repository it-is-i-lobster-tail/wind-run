import SwiftUI

/// SF Symbol names and single emoji can share one string in storage and watch messages.
nonisolated enum WorkoutIcon {
    static let fallback = "repeat"

    static func isEmoji(_ value: String) -> Bool {
        guard value.count == 1, let first = value.unicodeScalars.first,
              first.properties.isEmoji else { return false }
        if first.isASCII {
            return value.unicodeScalars.last?.value == 0x20E3 // keycap
        }
        return !value.unicodeScalars.contains("\u{FE0E}") // explicit text presentation
    }
}

struct WorkoutGlyph: View {
    let value: String?

    var body: some View {
        Group {
            if let value, WorkoutIcon.isEmoji(value) {
                Text(verbatim: value)
            } else {
                Image(systemName: value ?? WorkoutIcon.fallback)
            }
        }
        .accessibilityHidden(true)
    }
}
