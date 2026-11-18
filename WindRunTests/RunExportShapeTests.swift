//
//  RunExportShapeTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The export's shape: a field for every column on every row, and the same files whether they're made all
/// at once or a run at a time off the main actor, as the app makes them.
@MainActor
struct RunExportShapeTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private let phone = DeviceInfo(kind: .iPhone, model: "iPhone17,1", system: "iOS 26.1.0", app: "0.3.0 (70)")
    private let watch = DeviceInfo(kind: .appleWatch, model: "Watch7,1", system: "watchOS 26.1.0")

    /// A finished run heading north, with a pause, heart rate from the watch and Apple's distance.
    private func makeRun(startingAt offset: TimeInterval = 0) -> Run {
        let runStart = start.addingTimeInterval(offset)
        let run = Run(startDate: runStart)
        container.mainContext.insert(run)
        var devices = RunDevices(recorder: phone)
        devices.addHeartRate(watch)
        run.saveDevices(devices)
        for second in 0...30 {
            if second == 20 { run.pause(at: runStart.addingTimeInterval(20)) }
            if second == 25 { run.resume(at: runStart.addingTimeInterval(25)) }
            run.record(RouteSample(
                timestamp: runStart.addingTimeInterval(Double(second)),
                latitude: 39.7392 + Double(second) * 3 / 111_111,
                longitude: -104.9903,
                altitude: 1_600 + Double(second),
                horizontalAccuracy: 5,
                verticalAccuracy: 4,
                speed: second.isMultiple(of: 2) ? 3 : -1,
                course: 0,
                speedAccuracy: second.isMultiple(of: 2) ? 0.4 : -1
            ))
            run.record(HeartRateSample(timestamp: runStart.addingTimeInterval(Double(second)), beatsPerMinute: 150, source: .appleWatch))
        }
        run.recordAppleDistance(80)
        run.finish(at: runStart.addingTimeInterval(30))
        return run
    }

    /// The runs an export is asked for: two finished ones out of order, one still going and one discarded.
    private func someRuns() -> [Run] {
        let later = makeRun(startingAt: 86_400)
        let earlier = makeRun()
        let unfinished = Run(startDate: start.addingTimeInterval(200_000))
        container.mainContext.insert(unfinished)
        let discarded = Run(startDate: start.addingTimeInterval(300_000))
        container.mainContext.insert(discarded)
        discarded.discard(at: start.addingTimeInterval(300_060))
        return [later, unfinished, discarded, earlier]
    }

    /// How many fields each CSV line has, counting a quoted comma as part of its field.
    private func fieldCounts(_ csv: String) -> [Int] {
        csv.split(separator: "\n").map { line in
            var count = 1
            var quoted = false
            for character in line {
                if character == "\"" {
                    quoted.toggle()
                } else if character == ",", !quoted {
                    count += 1
                }
            }
            return count
        }
    }

    @Test func everyRowHasAFieldForEveryColumn() {
        let files = RunExport.make(someRuns(), exportedBy: phone, privacyZone: 0)
        let runs = fieldCounts(files.runs)
        let points = fieldCounts(files.points)
        #expect(runs.count == 3)
        #expect(runs.allSatisfy { $0 == RunExport.runColumns.count })
        #expect(points.count == 1 + 2 * 31)
        #expect(points.allSatisfy { $0 == RunExport.pointColumns.count })
    }

    @Test func onlyFinishedRunsGoInOldestFirst() {
        let runs = someRuns()
        let finished = RunExport.finished(runs)
        #expect(finished.count == 2)
        #expect(finished.allSatisfy { $0.status == .complete })
        #expect(finished.map(\.startDate) == [start, start.addingTimeInterval(86_400)])
    }

    @Test func theAppsWayMakesTheSameFiles() async throws {
        let runs = someRuns()
        let maker = RunExport.Maker(exportedBy: phone, privacyZone: 0)
        for run in RunExport.finished(runs) {
            await maker.add(RunExport.Record(run))
        }
        let made = try await maker.export(.runs)
        #expect(made.files == RunExport.make(runs, exportedBy: phone, privacyZone: 0))
        #expect(made.data == Data(made.files.runs.utf8))
    }
}
