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
            }
            .padding()
        }
        .navigationTitle(run.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
