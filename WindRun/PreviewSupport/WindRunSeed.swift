//
//  WindRunSeed.swift
//  Wind Run
//

import Foundation
import SwiftData

/// Sample data for previews.
enum WindRunSeed {
    /// An in-memory store with a few finished runs, each with a short straight route and heart rate.
    static func containerWithRuns() -> ModelContainer {
        let container = WindRunSchema.makeContainer(inMemory: true)
        let context = container.mainContext

        let runs: [(daysAgo: Double, kilometers: Double, paceSeconds: Double)] = [
            (1, 5.02, 312),
            (3, 10.4, 335),
            (6, 21.1, 348),
        ]
        for entry in runs {
            let start = Date.now.addingTimeInterval(-entry.daysAgo * 86_400)
            let run = Run(startDate: start)
            context.insert(run)

            // Walk north from a point; 0.009° of latitude is about a kilometer.
            let duration = entry.kilometers * entry.paceSeconds
            let steps = 20
            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                run.record(RouteSample(
                    timestamp: start.addingTimeInterval(duration * fraction),
                    latitude: 37.7749 + 0.009 * entry.kilometers * fraction,
                    longitude: -122.4194 + 0.002 * sin(fraction * .pi * 4),
                    horizontalAccuracy: 5
                ))
                run.record(HeartRateSample(
                    timestamp: start.addingTimeInterval(duration * fraction),
                    beatsPerMinute: 138 + 22 * fraction + 5 * sin(fraction * .pi * 6)
                ))
            }
            run.finish(at: start.addingTimeInterval(duration))
        }

        context.insert(IntervalPlan.classicFiveByThree())
        context.saveQuietly()
        return container
    }
}
