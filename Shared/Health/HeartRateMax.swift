//
//  HeartRateMax.swift
//  Wind Run
//

import Foundation
import SwiftData

/// The highest heart rate the runner reaches, for the run screen's heart rate zone. A lab-tested maximum
/// from the coach's heart rate settings wins; otherwise it's the highest of the recent runs on this device.
/// Like other heart rate settings it stays on the device and never goes to iCloud.
///
/// Each run counts its sustained peak, not its single highest reading, and only the last `recentRuns` runs
/// count, so a run where the sensor locked onto cadence doesn't set the zones for good.
enum HeartRateMax {
    /// The highest heart rate seen on recent runs, in beats per minute.
    static let storageKey = "heartRateMaxSeen"
    /// The recent runs' peaks, oldest first.
    static let peaksKey = "heartRateRunPeaks"
    /// Where the coach keeps its heart rate settings, with any lab-tested maximum.
    static let coachSettingsKey = "coachHeartRateSettings"
    /// Readings outside this are sensor glitches.
    static let plausible: ClosedRange<Double> = 100...230
    /// How many runs' peaks count. A month or two of running, so a race's real maximum stays a while.
    static let recentRuns = 20

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

    /// A run's peak: a height its heart rate held, so a spike from a loose sensor doesn't count. With ten or
    /// more readings it's the 98th percentile; with fewer, the second-highest. Nil with fewer than two
    /// readings or a peak that can't be real.
    static func peak(of beatsPerMinute: [Double]) -> Double? {
        let sorted = beatsPerMinute.sorted()
        guard sorted.count >= 2 else { return nil }
        let peak = sorted.count >= 10 ? sorted[Int(Double(sorted.count - 1) * 0.98)] : sorted[sorted.count - 2]
        return plausible.contains(peak) ? peak : nil
    }

    /// Counts a run's peak among the recent runs' and saves the highest of them as the maximum.
    static func record(_ beatsPerMinute: [Double], in defaults: UserDefaults = .standard) {
        guard let peak = peak(of: beatsPerMinute) else { return }
        var peaks = defaults.array(forKey: peaksKey) as? [Double] ?? []
        if peaks.isEmpty {
            // Saved before peaks were kept run by run: it counts as one run, and leaves with the others.
            let seen = defaults.double(forKey: storageKey)
            if plausible.contains(seen) { peaks.append(seen) }
        }
        peaks.append(peak)
        peaks = Array(peaks.suffix(recentRuns))
        defaults.set(peaks, forKey: peaksKey)
        if let highest = peaks.max() {
            defaults.set(highest, forKey: storageKey)
        }
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
        // Oldest first, so the most recent runs are the ones that count.
        guard let runs = try? context.fetch(FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDateValue)])) else { return }
        for run in runs {
            record(run.heartRateSamples.map(\.beatsPerMinute), in: defaults)
        }
    }
}
