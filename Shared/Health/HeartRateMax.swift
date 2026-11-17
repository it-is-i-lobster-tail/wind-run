//
//  HeartRateMax.swift
//  Wind Run
//

import Foundation
import SwiftData

/// The highest heart rate the runner reaches, for the run screen's heart rate zone. A lab-tested maximum
/// from the coach's heart rate settings wins; otherwise it's the highest seen on this device's runs.
/// Like other heart rate settings it stays on the device and never goes to iCloud.
enum HeartRateMax {
    /// The highest heart rate seen on a run, in beats per minute.
    static let storageKey = "heartRateMaxSeen"
    /// Where the coach keeps its heart rate settings, with any lab-tested maximum.
    static let coachSettingsKey = "coachHeartRateSettings"
    /// Readings outside this are sensor glitches.
    static let plausible: ClosedRange<Double> = 100...230

    /// The maximum to work zones out from, or nil before any run with heart rate.
    static func value(in defaults: UserDefaults = .standard) -> Double? {
        if let data = defaults.data(forKey: coachSettingsKey),
           let settings = try? JSONDecoder().decode(HeartRateSettings.self, from: data),
           let labMax = settings.labMax, plausible.contains(labMax) {
            return labMax
        }
        let seen = defaults.double(forKey: storageKey)
        return plausible.contains(seen) ? seen : nil
    }

    /// A run's peak: its second-highest reading, so one spike from a loose sensor doesn't count. Nil with
    /// fewer than two readings or a peak that can't be real.
    static func peak(of beatsPerMinute: [Double]) -> Double? {
        let sorted = beatsPerMinute.sorted(by: >)
        guard sorted.count >= 2, plausible.contains(sorted[1]) else { return nil }
        return sorted[1]
    }

    /// Raises the saved maximum when a run went higher.
    static func record(_ beatsPerMinute: [Double], in defaults: UserDefaults = .standard) {
        guard let peak = peak(of: beatsPerMinute), peak > defaults.double(forKey: storageKey) else { return }
        defaults.set(peak, forKey: storageKey)
    }

    /// Zone 1 to 5 at `beatsPerMinute`: under 60% of the maximum is zone 1, then a zone every 10%, and
    /// 90% and over is zone 5.
    static func zone(_ beatsPerMinute: Double, max: Double) -> Int {
        let share = beatsPerMinute / max
        switch share {
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }
}

extension HeartRateMax {
    /// Set once the saved runs have been read for their highest heart rate.
    static let backfilledKey = "heartRateMaxBackfilled"

    /// Reads the saved runs' heart rate once, so zones work before the next run with heart rate.
    @MainActor
    static func backfill(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: backfilledKey) else { return }
        defaults.set(true, forKey: backfilledKey)
        guard let runs = try? context.fetch(FetchDescriptor<Run>()) else { return }
        for run in runs {
            record(run.heartRateSamples.map(\.beatsPerMinute), in: defaults)
        }
    }
}
