import SwiftUI
import UIKit

nonisolated enum WorkoutIcon {
    static let fallback = WorkoutSport.running.systemImage
    static let identifiers = Set(WorkoutSymbolGroup.all.flatMap(\.symbols))

    static func supported(_ value: String?) -> String? {
        guard let value else { return nil }
        if identifiers.contains(value) { return value }
        // Keep previously selected system artwork when the picker is curated.
        return UIImage(systemName: value) == nil ? nil : value
    }
}

struct WorkoutGlyph: View {
    let value: String?

    var body: some View {
        let name = value ?? WorkoutIcon.fallback
        let image = name.hasPrefix("workout.") ? Image(name) : Image(systemName: name)
        image.accessibilityHidden(true)
    }
}
