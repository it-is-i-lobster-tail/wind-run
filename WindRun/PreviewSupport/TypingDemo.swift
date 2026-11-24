//
//  TypingDemo.swift
//  Wind Run
//

#if DEBUG
import Foundation

/// Types a name into the open page's name field one character at a time, as the keyboard would, for
/// simulator screenshots of title case, which can't type. Launch with `-typeNameDemo "Lap Of The Park"`
/// alongside a `-workoutsDemo` page with a name field (new, edit or edit-display). Debug builds only.
enum TypingDemo {
    static var text: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-typeNameDemo"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Clears the field, then types `text` into it a character at a time so each change runs the field's
    /// own handling.
    @MainActor
    static func type(into field: @escaping @MainActor (String) -> Void, reading current: @escaping @MainActor () -> String) async {
        guard let text else { return }
        try? await Task.sleep(for: .milliseconds(800))
        field("")
        for character in text {
            try? await Task.sleep(for: .milliseconds(80))
            field(current() + String(character))
        }
    }
}
#endif
