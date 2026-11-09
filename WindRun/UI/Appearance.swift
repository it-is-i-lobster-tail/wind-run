//
//  Appearance.swift
//  Wind Run
//

import SwiftUI
import UIKit

/// Light or dark, or whatever the iPhone is set to, which is where everyone starts.
/// The watch is always dark, so this is the iPhone's alone.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: Self { self }

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// The runner's pick on this device, or System when they haven't made one.
    static func current(in defaults: UserDefaults = .standard) -> Appearance {
        defaults.string(forKey: storageKey).flatMap(Appearance.init(rawValue:)) ?? .system
    }

    /// Sets every window rather than the root view, so sheets and alerts that are already open
    /// change too, and System hands straight back to the iPhone's own setting.
    @MainActor
    func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}
