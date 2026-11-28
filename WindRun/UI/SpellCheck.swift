//
//  SpellCheck.swift
//  Wind Run
//

import UIKit

/// Turns on spell checking and autocorrect in every text box the runner types words into: the search bars,
/// workout and display names, waypoint names and the place search (the owner, 2026-11-28).
///
/// SwiftUI has no spell-check setting, and `.searchable` gives no way to reach its field, so this sets both on
/// the field itself as it starts editing, app wide, which also covers text boxes added later. Number fields
/// (weight, distances, times and paces) keep their pads and are left as they are, so "8:30" never autocorrects.
@MainActor
enum SpellCheck {
    private static var observers: [NSObjectProtocol] = []

    /// Call once at launch.
    static func install() {
        guard observers.isEmpty else { return }
        observers = [
            NotificationCenter.default.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { if let field = note.object as? UITextField { apply(to: field) } }
            },
            NotificationCenter.default.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { if let view = note.object as? UITextView { apply(to: view) } }
            },
        ]
    }

    /// True for a keyboard that types words. The number and punctuation pads type amounts, never words.
    static func typesWords(_ keyboard: UIKeyboardType) -> Bool {
        switch keyboard {
        case .default, .asciiCapable, .webSearch, .alphabet: true
        default: false
        }
    }

    /// Whether a text box should check spelling: a word keyboard, and not a password.
    static func wanted(keyboard: UIKeyboardType, secure: Bool) -> Bool {
        typesWords(keyboard) && !secure
    }

    static func apply(to field: UITextField) {
        guard wanted(keyboard: field.keyboardType, secure: field.isSecureTextEntry) else { return }
        if set(on: field) { field.reloadInputViews() }
    }

    static func apply(to view: UITextView) {
        guard view.isEditable, wanted(keyboard: view.keyboardType, secure: view.isSecureTextEntry) else { return }
        if set(on: view) { view.reloadInputViews() }
    }

    /// Sets both on, and says whether anything changed, so the keyboard only reloads when it has to.
    @discardableResult
    static func set(on field: UITextField) -> Bool {
        let changed = field.autocorrectionType != .yes || field.spellCheckingType != .yes
        field.autocorrectionType = .yes
        field.spellCheckingType = .yes
        return changed
    }

    @discardableResult
    static func set(on view: UITextView) -> Bool {
        let changed = view.autocorrectionType != .yes || view.spellCheckingType != .yes
        view.autocorrectionType = .yes
        view.spellCheckingType = .yes
        return changed
    }
}
