//
//  SettingsDemo.swift
//  Wind Run
//

#if DEBUG
import Foundation

/// Opens Settings on one of its pages, for simulator screenshots, which can't tap. Launch with
/// `-settingsDemo PAGE`, where PAGE is top, or a `SettingsPage` raw value: personalization, health,
/// appearance, data, starting-point, legal, privacy, terms or developer. Privacy and terms open over
/// Legal, and starting-point over Your Data, as a tap would. Debug builds only.
enum SettingsDemo {
    static var page: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-settingsDemo") else { return nil }
        return arguments.indices.contains(index + 1) ? arguments[index + 1] : "top"
    }

    /// The pages pushed in Settings as it opens.
    static var path: [SettingsPage] {
        guard let page = page.flatMap(SettingsPage.init(rawValue:)) else { return [] }
        switch page {
        case .privacyPolicy, .termsAndConditions: return [.legal, page]
        case .startingPoint: return [.yourData, page]
        default: return [page]
        }
    }
}
#endif
