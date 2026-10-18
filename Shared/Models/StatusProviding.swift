//
//  StatusProviding.swift
//  Wind Run
//

import OSLog

/// Something that can be the one active item of its kind, like the current coach plan.
protocol StatusProviding {
    var isActive: Bool { get }
}

extension Collection where Element: StatusProviding {
    /// The single active element. If more than one is active, logs it and returns the first.
    var active: Element? {
        let active = filter(\.isActive)
        if active.count > 1 {
            Logger.persistence.warning("Found \(active.count) active items where only one was expected.")
        }
        return active.first
    }
}
