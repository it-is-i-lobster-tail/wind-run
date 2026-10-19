//
//  RunDetailView.swift
//  Wind Run
//

import MapKit
import SwiftData
import SwiftUI

struct RunDetailView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let run: Run

    private var coordinates: [CLLocationCoordinate2D] {
        run.route.map(\.coordinate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.sectionSpacing) {
                if coordinates.count > 1 {
                    Map(interactionModes: [.zoom, .pan]) {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.tint, lineWidth: 5)
                    }
                    // Just the route and the streets, no shops or venues.
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .frame(height: 280)
                    .clipShape(.rect(cornerRadius: LayoutMetrics.cardCornerRadius))
                }

                Grid(horizontalSpacing: LayoutMetrics.compactSpacing, verticalSpacing: LayoutMetrics.compactSpacing) {
                    GridRow {
                        Stat(title: "Distance", value: RunFormat.distance(run.distanceMeters, unit: unit))
                        Stat(title: "Time", value: RunFormat.duration(run.activeDuration()))
                    }
                    GridRow {
                        Stat(title: "Pace", value: RunFormat.pace(run.pace(), unit: unit))
                        Stat(title: "Type", value: run.kind.name)
                    }
                }

                if let heartRate = run.heartRateStats {
                    HeartRateSummary(timeline: run.heartRateTimeline, stats: heartRate)
                }

                if run.healthWorkoutID != nil {
                    Label("Saved to Apple Health", systemImage: "heart")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(run.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The run's heart rate over time, then its lowest, highest, mean and spread.
private struct HeartRateSummary: View {
    let timeline: [HeartRatePoint]
    let stats: HeartRateStats

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            // A line needs two readings.
            if timeline.count > 1 {
                VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                    Text("Heart rate")
                        .font(.headline)
                    HeartRateChart(points: timeline, mean: stats.mean)
                        .frame(height: 200)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .windRunGlassCard()
            }

            Grid(horizontalSpacing: LayoutMetrics.compactSpacing, verticalSpacing: LayoutMetrics.compactSpacing) {
                GridRow {
                    Stat(title: "Avg heart rate", value: RunFormat.heartRate(stats.mean))
                    Stat(title: "Max heart rate", value: RunFormat.heartRate(stats.maximum))
                }
                GridRow {
                    Stat(title: "Min heart rate", value: RunFormat.heartRate(stats.minimum))
                    Stat(
                        title: "Variance",
                        value: RunFormat.heartRateVariance(stats.variance),
                        detail: "Std dev \(RunFormat.heartRateDeviation(stats.standardDeviation))"
                    )
                }
            }
        }
    }
}

private struct Stat: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            if let detail {
                Text(detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        // Fill the row, so a card with a detail line doesn't stand taller than its neighbor.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .windRunGlassCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview("Run detail") {
    let container = WindRunSeed.containerWithRuns()
    let run = try! container.mainContext.fetch(FetchDescriptor<Run>()).first!
    return NavigationStack {
        RunDetailView(run: run)
    }
    .modelContainer(container)
}
