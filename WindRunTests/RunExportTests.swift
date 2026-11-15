//
//  RunExportTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct RunExportTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private let utc = TimeZone(identifier: "UTC")!
    private let phone = DeviceInfo(kind: .iPhone, model: "iPhone17,1", system: "iOS 26.1.0", app: "0.3.0 (70)")
    private let watch = DeviceInfo(kind: .appleWatch, model: "Watch7,1", system: "watchOS 26.1.0")

    /// A finished run near a real place, with a note, a pause, heart rate and Apple's distance.
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
                speed: 3,
                course: 0,
                speedAccuracy: 0.4
            ))
            run.record(HeartRateSample(timestamp: runStart.addingTimeInterval(Double(second)), beatsPerMinute: 150, source: .appleWatch))
        }
        run.recordAppleDistance(80)
        run.notes = "Ran past my house on Main Street"
        run.finish(at: runStart.addingTimeInterval(30))
        return run
    }

    private func lines(_ csv: String) -> [[String]] {
        csv.split(separator: "\n").map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    }

    private func column(_ name: String, in table: [[String]], row: Int) -> String? {
        guard let index = table.first?.firstIndex(of: name), table.count > row else { return nil }
        return table[row][index]
    }

    @Test func oneRowPerFinishedRunOldestFirst() {
        let later = makeRun(startingAt: 86_400)
        let earlier = makeRun()
        let unfinished = Run(startDate: start.addingTimeInterval(200_000))
        container.mainContext.insert(unfinished)

        let files = RunExport.make([later, unfinished, earlier], exportedBy: phone, timeZone: utc)
        let runs = lines(files.runs)
        #expect(runs.count == 3)
        #expect(runs[0] == RunExport.runColumns)
        #expect(column("run", in: runs, row: 1) == "1")
        #expect(column("date", in: runs, row: 1) == start.formatted(Date.ISO8601FormatStyle(timeZone: utc).year().month().day()))
        #expect(column("date", in: runs, row: 2) == later.startDate.formatted(Date.ISO8601FormatStyle(timeZone: utc).year().month().day()))
        #expect(lines(files.fixes).count == 1 + 2 * 31)
    }

    @Test func theRunRowSaysWhereTheDataCameFromAndWhichVersions() {
        let run = makeRun()
        let runs = lines(RunExport.make([run], exportedBy: phone, timeZone: utc).runs)
        #expect(column("data_from", in: runs, row: 1) == "iPhone + Apple Watch")
        #expect(column("recorder_model", in: runs, row: 1) == "iPhone17,1")
        #expect(column("recorder_os", in: runs, row: 1) == "iOS 26.1.0")
        #expect(column("recorder_app", in: runs, row: 1) == "0.3.0 (70)")
        #expect(column("heart_rate_devices", in: runs, row: 1) == "Apple Watch Watch7,1 watchOS 26.1.0")
        #expect(column("heart_rate_sources", in: runs, row: 1) == "appleWatch")
        #expect(column("distance_method", in: runs, row: 1) == DistanceEstimator.method)
        #expect(column("apple_distance_m", in: runs, row: 1) == "80.00")
        #expect(column("distance_m", in: runs, row: 1) == RunExport.number(run.distanceMeters))
        #expect(column("recomputed_distance_m", in: runs, row: 1) == RunExport.number(run.distanceMeters))
        #expect(column("pauses", in: runs, row: 1) == "1")
        #expect(column("exported_by_app", in: runs, row: 1) == "0.3.0 (70)")
    }

    @Test func nothingSaysWhereTheRunnerWasOrWhoTheyAre() {
        let run = makeRun()
        let files = RunExport.make([run], exportedBy: phone, timeZone: utc)
        let everything = files.runs + files.fixes
        // No coordinates, in any rounding.
        #expect(!everything.contains("39.7"))
        #expect(!everything.contains("104.9"))
        // No absolute heights, notes, ids, heart rate values or time of day.
        #expect(!everything.contains("1600"))
        #expect(!everything.contains("Main Street"))
        #expect(!everything.contains(run.runID.uuidString))
        #expect(!everything.contains("150"))
        #expect(!everything.contains(":"))
        for name in ["latitude", "longitude", "course", "notes", "heart_rate_bpm", "weight", "calories"] {
            #expect(!RunExport.runColumns.contains(name))
            #expect(!RunExport.fixColumns.contains(name))
        }
    }

    @Test func fixRowsCarryWhatTheDistanceNeedsWithoutPositions() {
        let run = makeRun()
        let fixes = lines(RunExport.make([run], exportedBy: phone, timeZone: utc).fixes)
        #expect(fixes[0] == RunExport.fixColumns)
        #expect(column("seconds", in: fixes, row: 1) == "0.0")
        #expect(column("altitude_change_m", in: fixes, row: 11) == "10.0")
        #expect(column("speed_mps", in: fixes, row: 2) == "3.00")
        #expect(column("speed_accuracy_mps", in: fixes, row: 2) == "0.40")
        #expect(column("counted_by", in: fixes, row: 2) == "speed")
        // Second 22 was during the pause.
        #expect(column("active", in: fixes, row: 23) == "0")
        #expect(column("counted_m", in: fixes, row: 23) == "0.00")
    }

    @Test func fieldsWithCommasOrQuotesAreQuoted() {
        #expect(RunExport.escape("plain") == "plain")
        #expect(RunExport.escape("a, b") == "\"a, b\"")
        #expect(RunExport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(RunExport.number(.nan) == "")
    }

    @Test func runsFromBeforeDevicesWereKeptSayUnknown() {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        run.distanceMethodValue = nil
        run.gpsTrackMetersValue = nil
        run.finish(at: start.addingTimeInterval(60))
        let runs = lines(RunExport.make([run], exportedBy: phone, timeZone: utc).runs)
        #expect(column("data_from", in: runs, row: 1) == "unknown")
        #expect(column("distance_method", in: runs, row: 1) == "gps-track")
        #expect(column("gps_track_m", in: runs, row: 1) == "")
    }
}

@MainActor
struct RunDevicesTests {
    private let phone = DeviceInfo(kind: .iPhone, model: "iPhone17,1", system: "iOS 26.1.0", app: "0.3.0 (70)")
    private let watch = DeviceInfo(kind: .appleWatch, model: "Watch7,1", system: "watchOS 26.1.0", app: "0.3.0 (70)")

    @Test func dataFromNamesEachKindOnce() {
        #expect(RunDevices(recorder: phone).dataFrom == "iPhone")
        #expect(RunDevices(recorder: watch, heartRate: [watch]).dataFrom == "Apple Watch")
        #expect(RunDevices(recorder: phone, heartRate: [watch]).dataFrom == "iPhone + Apple Watch")
        let strap = DeviceInfo(kind: .strapOrSensor, model: "H10", manufacturer: "Polar", firmware: "5.0")
        #expect(RunDevices(recorder: phone, heartRate: [strap]).dataFrom == "iPhone")
        #expect(strap.details == "strap or sensor Polar H10 firmware 5.0")
    }

    @Test func aHeartRateDeviceIsAddedOnce() {
        var devices = RunDevices(recorder: phone)
        devices.addHeartRate(watch)
        devices.addHeartRate(watch)
        #expect(devices.heartRate == [watch])
    }

    @Test func thisDeviceIsNamedByItsModelNotItsName() {
        let current = DeviceInfo.current
        #expect(current.kind == .iPhone)
        #expect(current.app == AppVersion.current)
        #expect(current.system?.hasPrefix("iOS ") == true)
        #expect(current.model?.isEmpty == false)
    }

    @Test func aWatchRunBringsItsDevicesAndDistancesToTheIPhone() throws {
        let watchContainer = WindRunSchema.makeContainer(inMemory: true)
        let phoneContainer = WindRunSchema.makeContainer(inMemory: true)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let run = Run(startDate: start)
        watchContainer.mainContext.insert(run)
        run.saveDevices(RunDevices(recorder: watch, heartRate: [watch]))
        for second in 0...10 {
            run.record(RouteSample(timestamp: start.addingTimeInterval(Double(second)), latitude: Double(second) * 3 / 111_111, longitude: 0, horizontalAccuracy: 5, speed: 3, speedAccuracy: 0.3))
        }
        run.recordAppleDistance(31)
        run.finish(at: start.addingTimeInterval(10))

        let record = try #require(WatchRunRecord(run))
        let received = try #require(WatchRunRecord.decode(try #require(record.encoded())))
        let inserted = try #require(received.insert(into: phoneContainer.mainContext))
        #expect(inserted.appleDistanceMeters == 31)
        #expect(inserted.distanceMethod == DistanceEstimator.method)
        #expect(inserted.gpsTrackMeters == run.gpsTrackMeters)
        #expect(inserted.route.first?.speedAccuracyValue == 0.3)
        #expect(inserted.devices?.recorder == watch)
        #expect(inserted.devices?.dataFrom == "Apple Watch")
        #expect(inserted.devices?.receivedBy?.kind == .iPhone)
    }

    @Test func aRunFromAnOlderWatchAppStillSaysItCameFromAWatch() throws {
        let phoneContainer = WindRunSchema.makeContainer(inMemory: true)
        let json = """
            {"runID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"free","start":0,"end":60,"meters":150,
             "route":[{"timestamp":0,"latitude":0,"longitude":0,"altitude":0,"horizontalAccuracy":5,"verticalAccuracy":5,"speed":-1,"course":-1}],
             "pauses":[],"heartRate":[]}
            """
        let record = try #require(WatchRunRecord.decode(Data(json.utf8)))
        let inserted = try #require(record.insert(into: phoneContainer.mainContext))
        #expect(inserted.distanceMethod == nil)
        #expect(inserted.distanceMeters == 150)
        #expect(inserted.devices?.dataFrom == "Apple Watch")
        #expect(inserted.route.first?.speedAccuracyValue == -1)
    }
}
