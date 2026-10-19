//
//  RunPause.swift
//  Wind Run
//

import Foundation
import SwiftData

/// A stretch of a run where the runner paused the clock.
@Model
final class RunPause {
    var startDateValue: Date = Date.now
    /// Nil while the pause is still going.
    var endDateValue: Date?

    var runValue: Run?

    init(startDate: Date) {
        self.startDateValue = startDate
    }
}

extension RunPause {
    var startDate: Date { startDateValue }
    var endDate: Date? { endDateValue }

    func end(at date: Date) {
        endDateValue = max(date, startDateValue)
    }

    /// Whether `date` falls inside the pause. An open pause covers everything after it starts.
    func contains(_ date: Date) -> Bool {
        date >= startDateValue && date < (endDateValue ?? .distantFuture)
    }

    /// How long the pause lasted, counting an open pause up to `now`.
    func duration(at now: Date) -> TimeInterval {
        let end = min(endDateValue ?? now, now)
        return max(0, end.timeIntervalSince(startDateValue))
    }
}
