//
//  SummaryLoadBenchmarkTests.swift
//  Wind Run Tests
//
//  Investigation only: times how long the run summary and the comparison page take to load, stage by
//  stage, on an on-disk store, for a first open and a second open of the same run. Prints lines that start
//  with "BENCH|" so a script can pull them out of the log. Skipped unless WINDRUN_BENCH=1 is set.

import CoreLocation
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import WindRun

@MainActor
final class SummaryLoadBenchmarkTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WINDRUN_BENCH"] == "1"
                          || ProcessInfo.processInfo.arguments.contains("-windRunBench"),
                          "Set WINDRUN_BENCH=1 to run the summary load benchmark.")
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("summary-bench-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("bench.store")
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let storeURL { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
    }

    // MARK: - Helpers

    private func openContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: WindRunSchema.schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: WindRunSchema.schema, configurations: configuration)
    }

    private func report(_ label: String, _ ms: Double) {
        print("BENCH|\(label)|\(String(format: "%.1f", ms))")
    }

    @discardableResult
    private func time<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let started = ContinuousClock.now
        let value = try body()
        report(label, Double((ContinuousClock.now - started) / .microseconds(1)) / 1_000)
        return value
    }

    /// A run of `minutes` at one fix a second, like a real phone or watch recording: heart rate every 5 s,
    /// steps in 15 s stretches, the barometer every 2 s, and two stops.
    @discardableResult
    private func addRun(minutes: Int, start: Date, goalMeters: Double? = nil, in context: ModelContext) -> Run {
        let run = Run(kind: .free, startDate: start)
        context.insert(run)
        if let goalMeters { run.goal = .distance(meters: goalMeters) }
        let seconds = minutes * 60
        let stops: [(at: Int, length: Int)] = [(seconds / 3, 40), (2 * seconds / 3, 55)]
        var paused = 0
        var meters = 0.0
        var footsteps: [StepCountSample] = []
        var barometer: [AltitudeSample] = []
        let center = (latitude: 37.7694, longitude: -122.4662)
        for second in 1...seconds {
            if let stop = stops.first(where: { $0.at == second }) {
                let date = start.addingTimeInterval(TimeInterval(second + paused))
                run.pause(at: date)
                run.resume(at: date.addingTimeInterval(TimeInterval(stop.length)))
                paused += stop.length
            }
            let date = start.addingTimeInterval(TimeInterval(second + paused))
            let pace = 330 * (1 + 0.05 * sin(Double(second) / 41))
            meters += 1_000 / pace
            let angle = meters / 6_500 * 2 * .pi
            let north = 650 * sin(angle), east = 1_400 * cos(angle) + 30 * sin(angle * 7)
            let altitude = 64 + 10 * sin(angle) + 7 * sin(6 * angle)
            run.record(RouteSample(
                timestamp: date,
                latitude: center.latitude + north / 111_111,
                longitude: center.longitude + east / (111_111 * cos(center.latitude * .pi / 180)),
                altitude: altitude + 2 * sin(Double(second) / 3),
                horizontalAccuracy: 5,
                verticalAccuracy: 4,
                speed: 1_000 / pace,
                course: 90,
                speedAccuracy: 0.5
            ))
            if second % 5 == 0 {
                run.record(HeartRateSample(timestamp: date, beatsPerMinute: 150 + 10 * sin(Double(second) / 120)))
            }
            if second % 15 == 0 {
                footsteps.append(StepCountSample(start: date.addingTimeInterval(-15), end: date, count: 42 + 2 * sin(Double(second) / 60)))
            }
            if second % 2 == 0 {
                barometer.append(AltitudeSample(timestamp: date, relativeMeters: altitude - 64))
            }
        }
        run.saveStepCounts(footsteps)
        run.saveBarometricAltitude(barometer)
        run.finish(at: start.addingTimeInterval(TimeInterval(seconds + paused + 1)))
        return run
    }

    private func fetchRun(_ id: UUID, in context: ModelContext) throws -> Run {
        var descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.runIDValue == id })
        descriptor.fetchLimit = 1
        return try XCTUnwrap(context.fetch(descriptor).first)
    }

    /// The same steps, in the same order, as `RunDetailView.Summary.init`, each timed.
    private func buildSummary(_ run: Run, prefix: String) {
        let total = ContinuousClock.now
        let readings = time("\(prefix).routeReadings(read once, sorted)") { run.routeReadings }
        _ = time("\(prefix).startLocation") { Run.startLocation(in: readings) }
        let clock = time("\(prefix).pauseClock") { run.pauseClock }
        let fixes = time("\(prefix).activeRoute") {
            Run.activeRoute(readings, clock: clock, measuresBySpeed: run.distanceMethod != nil, sport: run.sport)
        }
        let track = time("\(prefix).altitudeTrack") { run.altitudeTrack(for: fixes) }
        let buffers = time("\(prefix).chartPauseBuffers") { run.chartPauseBuffers }
        let cadence = time("\(prefix).cadenceSeries") { run.cadenceSeries(buffers: buffers) }
        _ = time("\(prefix).sections") { run.sections }
        let routes = time("\(prefix).coloredRoutes") { Run.coloredRoutes(fixes: fixes, track: track, cadence: cadence.map) }
        _ = time("\(prefix).paceTimeline") { Run.paceTimeline(fixes, buffers: buffers) }
        _ = time("\(prefix).elevation") { Run.elevation(track) }
        _ = time("\(prefix).calories") { CalorieEstimator.estimate(Run.energyLegs(fixes: fixes, track: track), sport: run.sport) }
        _ = time("\(prefix).heartRateChart(faults readings)") { run.heartRateChart(buffers: buffers) }
        _ = time("\(prefix).stepTotal") { run.stepTotal }
        report("\(prefix).TOTAL", Double((ContinuousClock.now - total) / .microseconds(1)) / 1_000)
        report("\(prefix).fixes", Double(fixes.count))
        report("\(prefix).mapSegments", Double(routes.map { $0.segments.count }.max() ?? 0))
        report("\(prefix).mapPoints", Double(routes.map { $0.segments.reduce(0) { $0 + $1.coordinates.count } + $0.edge.count }.max() ?? 0))
    }

    /// Puts a view in a real window and lays it out until SwiftUI has nothing left to do, a few passes, so
    /// work started in onAppear (the summary) is counted too. Returns the time spent laying out.
    /// Spins the run loop until `done` says so, up to 5 s, so work in a view's task is counted.
    private func waitUntil(_ done: () -> Bool) {
        let deadline = Date.now.addingTimeInterval(5)
        while !done(), Date.now < deadline {
            RunLoop.main.run(mode: .default, before: Date.now.addingTimeInterval(0.002))
        }
    }

    /// `settle` keeps the run loop going for that long after the first pass, for a page whose `until` is
    /// already true (a cached summary still goes in after the first frame).
    private func render<V: View>(_ label: String, _ view: V, passes: Int = 6, until: (() -> Bool)? = nil, settle: Duration = .zero) -> UIHostingController<V> {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: view)
        var spent = Duration.zero
        let first = ContinuousClock.now
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        CATransaction.flush()
        let firstPass = ContinuousClock.now - first
        spent += firstPass
        if settle > .zero {
            let settled = ContinuousClock.now + settle
            while ContinuousClock.now < settled {
                RunLoop.main.run(mode: .default, before: Date.now.addingTimeInterval(0.002))
            }
        }
        for _ in 0..<passes {
            RunLoop.main.run(mode: .default, before: Date())
            if let until { waitUntil(until) }
            let started = ContinuousClock.now
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            CATransaction.flush()
            spent += ContinuousClock.now - started
        }
        report("\(label).firstPass", Double(firstPass / .microseconds(1)) / 1_000)
        report("\(label).wallUntilLoaded", Double((ContinuousClock.now - first) / .microseconds(1)) / 1_000)
        report("\(label).layoutTotal", Double(spent / .microseconds(1)) / 1_000)
        window.isHidden = true
        window.rootViewController = nil
        objc_setAssociatedObject(self, "window-\(label)", window, .OBJC_ASSOCIATION_RETAIN)
        return host
    }

    // MARK: - Benchmarks

    /// Data work for one run summary, first and second open, at a range of lengths.
    func testSummaryDataBuild() throws {
        for minutes in [30, 60, 240] {
            let id: UUID
            do {
                let container = try openContainer()
                let run = addRun(minutes: minutes, start: .now.addingTimeInterval(-Double(minutes + 10) * 60), in: container.mainContext)
                id = run.runID
                try container.mainContext.save()
            }
            // A fresh container, like opening the app and tapping the run.
            let container = try openContainer()
            let context = container.mainContext
            let run = try time("\(minutes)min.fetchRun") { try fetchRun(id, in: context) }
            buildSummary(run, prefix: "\(minutes)min.open1")
            // Back out and tap the same run again: same context, same run.
            buildSummary(run, prefix: "\(minutes)min.open2")
            if minutes == 240 {
                report("240min.packedBytes", Double(run.routeDataValue?.count ?? 0))
                // The same run read from its fix records, as a run not yet packed is. Not saved.
                let unpackedContainer = try openContainer()
                let unpacked = try fetchRun(id, in: unpackedContainer.mainContext)
                unpacked.routePackedCountValue = nil
                buildSummary(unpacked, prefix: "240min.unpacked.open1")
                buildSummary(unpacked, prefix: "240min.unpacked.open2")
            }
            try? FileManager.default.removeItem(at: storeURL)
        }
    }

    /// The whole page, data and drawing, in a window, first and second open of the same run.
    func testSummaryPageRender() throws {
        for minutes in [60, 240] {
            let id: UUID
            do {
                let container = try openContainer()
                let run = addRun(minutes: minutes, start: .now.addingTimeInterval(-Double(minutes + 10) * 60), in: container.mainContext)
                id = run.runID
                try container.mainContext.save()
            }
            let container = try openContainer()
            let run = try fetchRun(id, in: container.mainContext)
            RunDerivedCache.shared.removeAll()
            let loaded = { (RunDerivedCache.shared.cached("run summary", for: run) as Any?) != nil }
            _ = render("\(minutes)min.page.open1", NavigationStack { RunDetailView(run: run) }.modelContainer(container), until: loaded)
            // The summary is cached by now, so `loaded` is already true: give the page 50 ms to put it in instead.
            _ = render("\(minutes)min.page.open2", NavigationStack { RunDetailView(run: run) }.modelContainer(container), settle: .milliseconds(50))
            // Charts only, from data already built, to split drawing from data.
            let fixes = run.activeRoute
            let buffers = run.chartPauseBuffers
            let pace = Run.paceTimeline(fixes, buffers: buffers)
            let (heart, stats) = run.heartRateChart(buffers: buffers)
            _ = render("\(minutes)min.paceChartOnly", PaceChart(points: pace, average: run.pace(), duration: run.activeDuration(), unit: .kilometers).frame(height: 180))
            _ = render("\(minutes)min.heartChartOnly", HeartRateChart(points: heart, mean: stats?.mean ?? 150, duration: run.activeDuration()).frame(height: 200))
            let routes = Run.coloredRoutes(fixes: fixes, track: run.altitudeTrack(for: fixes), cadence: run.cadenceSeries(buffers: buffers).map)
            _ = render("\(minutes)min.mapOnly", RouteMapCard(routes: routes))
            try? FileManager.default.removeItem(at: storeURL)
        }
    }

    /// Comparing: the suggestions (ranks every run in the group), each selected run's series, and the page.
    func testComparison() throws {
        var ids: [UUID] = []
        do {
            let container = try openContainer()
            for index in 0..<30 {
                let run = addRun(minutes: 50, start: .now.addingTimeInterval(-Double(index + 1) * 86_400), goalMeters: 8_000, in: container.mainContext)
                ids.append(run.runID)
            }
            try container.mainContext.save()
        }
        let container = try openContainer()
        let context = container.mainContext
        let runs = try time("compare.fetchAll") {
            try context.fetch(FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDateValue, order: .reverse)]))
        }
        let group = try XCTUnwrap(ProgressGroup(runs[0]))
        RunDerivedCache.shared.removeAll()
        _ = time("compare.suggestions(30 runs).open1") { ComparisonSuggestions(group: group, runs: runs, startingRunID: runs[0].runID) }
        _ = time("compare.suggestions(30 runs).open2") { ComparisonSuggestions(group: group, runs: runs, startingRunID: runs[0].runID) }
        let picked = Array(runs.prefix(3))
        let series = time("compare.series(3 runs).open1") { picked.map { ComparisonSeries.cached($0) } }
        _ = time("compare.series(3 runs).open2") { picked.map { ComparisonSeries.cached($0) } }
        report("compare.routePointsPerRun", Double(series[0].coordinates.reduce(0) { $0 + $1.count }))
        _ = render("compare.page(series ready)", NavigationStack {
            ProgressComparison(group: group, runs: runs, suggestions: nil, initialSeries: series)
        }.modelContainer(container))
    }
}
