//
//  SpellCheck.swift
//  Wind Run
//

import UIKit

/// Turns on spell checking and autocorrect in every text box the runner types words into: the search bars,
/// workout and display names, waypoint names and the place search (the owner, 2026-11-28).
///
/// SwiftUI has no spell-check setting, and `.searchable` gives no way to reach its field, so this sets both on
/// the field itself as it starts editing, app wide, which also covers text boxes added later. A search bar hands
/// its own traits back to its field after editing starts (turning autocorrect off, so the keyboard showed no
/// suggestions), so they are set on the bar too and checked again each time the keyboard shows. Number fields
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
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { applyToFirstResponder() }
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
        var changed = set(on: field)
        if let bar = searchBar(holding: field) { changed = set(on: bar) || changed }
        if changed { field.reloadInputViews() }
    }

    /// The search bar a `.searchable` field sits in. The bar keeps its own traits and hands them back to its field
    /// (turning autocorrect off again), so they are set on the bar too.
    private static func searchBar(holding field: UITextField) -> UISearchBar? {
        var view = field.superview
        while let current = view {
            if let bar = current as? UISearchBar { return bar }
            view = current.superview
        }
        return nil
    }

    /// The text box being typed into, for the keyboard-show check.
    static func applyToFirstResponder() {
        FirstResponder.current = nil
        UIApplication.shared.sendAction(#selector(UIResponder.spellCheckCaptureFirstResponder), to: nil, from: nil, for: nil)
        defer { FirstResponder.current = nil }
        if let field = FirstResponder.current as? UITextField { apply(to: field) }
        else if let view = FirstResponder.current as? UITextView { apply(to: view) }
    }

    @discardableResult
    static func set(on bar: UISearchBar) -> Bool {
        let changed = bar.autocorrectionType != .yes || bar.spellCheckingType != .yes
        bar.autocorrectionType = .yes
        bar.spellCheckingType = .yes
        return changed
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

@MainActor private enum FirstResponder { static weak var current: UIResponder? }

extension UIResponder {
    @MainActor @objc fileprivate func spellCheckCaptureFirstResponder() { FirstResponder.current = self }
}
