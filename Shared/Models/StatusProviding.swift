//
//  StatusProviding.swift
//  Wind Run
//

import OSLog
import Synchronization

/// Something that can be the one active item of its kind, like the current coach plan.
protocol StatusProviding {
    var isActive: Bool { get }
}

extension Collection where Element: StatusProviding {
    /// The single active element. If more than one is active, logs it and returns the first.
    var active: Element? {
        let active = filter(\.isActive)
        if active.count > 1 {
            SeveralActive.note(String(describing: Element.self), count: active.count)
        }
        return active.first
    }
}

/// Two active coach plans, usually from an iCloud merge, logged and traced once for each count, since the
/// screens that read `active` do so on every redraw.
private nonisolated enum SeveralActive {
    private static let lastCounts = Mutex<[String: Int]>([:])

    static func note(_ type: String, count: Int) {
        let isNew = lastCounts.withLock { counts in
            guard counts[type] != count else { return false }
            counts[type] = count
            return true
        }
        guard isNew else { return }
        Logger.persistence.warning("Found \(count) active items where only one was expected.")
        Trace.log(.data, "Several active", ["type": type, "count": count])
    }
}
