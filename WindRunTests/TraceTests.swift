//
//  TraceTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Developer trace logging: rotation, turning off, deleting, the zip, and keeping personal details out.
@MainActor
final class TraceTests {
    private let suiteName = "TraceTests-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let directory = URL.temporaryDirectory.appending(path: "TraceTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFiles(maximumFileBytes: Int = 1_000, maximumFiles: Int = 3) -> TraceFiles {
        TraceFiles(directory: directory, defaults: defaults, maximumFileBytes: maximumFileBytes, maximumFiles: maximumFiles, sessionStart: 100)
    }

    private func line(_ message: String, at uptime: TimeInterval = 101) -> TraceLine {
        TraceLine(uptime: uptime, kind: .tap, message: message)
    }

    @Test func startsOffAndWritesNothingUntilTurnedOn() {
        let files = makeFiles()
        #expect(!files.isOn)
        files.write(line("Settings › Done"))
        #expect(files.files().isEmpty)
    }

    @Test func turningOnIsKeptOnThisDevice() {
        let files = makeFiles()
        files.turnOn()
        #expect(defaults.bool(forKey: Trace.storageKey))
        #expect(makeFiles().isOn)
        #expect(!CloudSettings.keys.contains(Trace.storageKey))
        #expect(!SettingsSync.keys.contains(Trace.storageKey))
    }

    @Test func writesLinesWithTimesSinceTheAppOpened() throws {
        let files = makeFiles()
        files.turnOn()
        files.write(TraceLine(uptime: 112.5, kind: .tap, message: "Settings › Done", details: [("on", "yes")]))
        let file = try #require(files.files().first)
        let text = try #require(files.contents(of: file))
        #expect(text.contains("==== App opened"))
        #expect(text.contains("+   12.500  tap       Settings › Done  on=yes"))
        #expect(file.isCurrent)
        #expect(file.name == "Trace 1")
    }

    @Test func startsANewFileWhenOneIsFullAndDropsTheOldest() throws {
        let files = makeFiles(maximumFileBytes: 600, maximumFiles: 3)
        files.turnOn()
        for index in 0 ..< 60 {
            files.write(line("Tap number \(index) on a screen with a longer name"))
        }
        let list = files.files()
        #expect(list.count == 3)
        #expect(list.map(\.number) == list.map(\.number).sorted(by: >))
        #expect(list.first?.isCurrent == true)
        #expect(list.dropFirst().allSatisfy { !$0.isCurrent })
        for file in list {
            #expect(file.bytes <= 600)
        }
        // The newest file has the last line, and the oldest ones are gone.
        let newest = try #require(files.contents(of: list[0]))
        #expect(newest.contains("Tap number 59"))
        #expect(newest.contains("==== Carried on from an earlier file"))
        #expect(!list.contains { $0.number == 1 })
    }

    @Test func defaultsAreTenFilesOfFiveMegabytes() {
        #expect(TraceFiles.defaultMaximumFiles == 10)
        #expect(TraceFiles.defaultMaximumFileBytes == 5 * 1024 * 1024)
    }

    @Test func turningOffDeletesEveryFile() {
        let files = makeFiles()
        files.turnOn()
        files.write(line("Settings › Done"))
        #expect(!files.files().isEmpty)
        files.turnOff()
        #expect(!files.isOn)
        #expect(!defaults.bool(forKey: Trace.storageKey))
        #expect(files.files().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        // Lines after turning off go nowhere.
        files.write(line("Settings › Done"))
        #expect(files.files().isEmpty)
    }

    @Test func deletingTheCurrentFileStartsANewOne() throws {
        let files = makeFiles(maximumFileBytes: 600)
        files.turnOn()
        for index in 0 ..< 20 {
            files.write(line("Tap number \(index) on a screen with a longer name"))
        }
        let before = files.files()
        let current = try #require(before.first)
        files.delete(current)
        files.write(line("After deleting"))
        let after = files.files()
        #expect(!after.contains { $0.number == current.number })
        let newest = try #require(after.first)
        #expect(newest.number > current.number)
        #expect(try #require(files.contents(of: newest)).contains("After deleting"))
    }

    @Test func deletingAnOlderFileKeepsWritingToTheCurrentOne() throws {
        let files = makeFiles(maximumFileBytes: 600)
        files.turnOn()
        for index in 0 ..< 20 {
            files.write(line("Tap number \(index) on a screen with a longer name"))
        }
        let before = files.files()
        let older = try #require(before.last)
        let current = try #require(before.first)
        files.delete(older)
        files.write(line("Still here"))
        let after = files.files()
        #expect(!after.contains { $0.number == older.number })
        #expect(after.first?.number == current.number)
    }

    @Test func zipsEveryFile() async throws {
        let files = makeFiles(maximumFileBytes: 600)
        files.turnOn()
        for index in 0 ..< 20 {
            files.write(line("Tap number \(index) on a screen with a longer name"))
        }
        let zip = try await TraceZip.make(from: files)
        defer { TraceZip.deleteMadeZips() }
        #expect(zip.url.pathExtension == "zip")
        #expect(zip.url.lastPathComponent.hasPrefix("Wind Run trace logs "))
        let data = try Data(contentsOf: zip.url)
        // A zip starts "PK" and names each file inside.
        #expect(data.prefix(2) == Data("PK".utf8))
        for file in files.files() {
            #expect(data.range(of: Data(file.url.lastPathComponent.utf8)) != nil)
        }
    }

    // MARK: - Personal details

    @Test func scrubsPersonalDetailsFromLines() {
        let scrubbed = TraceRedactor.scrub(
            "mail runner@example.com at 39.7128, -105.0060 or +1 (303) 555-0142, see https://example.com/a, "
                + "/var/mobile/Containers/Data/Application/0F8E2C9A-1B3D-4E5F-8A7B-6C5D4E3F2A1B/Library id 0F8E2C9A-1B3D-4E5F-8A7B-6C5D4E3F2A1B"
        )
        #expect(!scrubbed.contains("runner@example.com"))
        #expect(!scrubbed.contains("39.7128"))
        #expect(!scrubbed.contains("555-0142"))
        #expect(!scrubbed.contains("example.com/a"))
        #expect(!scrubbed.contains("/var/mobile"))
        #expect(!scrubbed.contains("0F8E2C9A"))
        #expect(scrubbed.contains("<email>"))
        #expect(scrubbed.contains("<location>"))
    }

    @Test func leavesEverydayLinesAlone() {
        for text in ["Settings › Done", "Fix  horizontalAccuracy=4.70  speed=3.21", "Speaking  text=1 kilometer. Pace 5 minutes 30.", "Trace 12", "Run days › Monday"] {
            #expect(TraceRedactor.scrub(text) == text)
        }
    }

    @Test func linesStayOnOneLine() {
        let text = TraceLine(uptime: 1, kind: .log, message: "one\ntwo", details: [("value", "a\nb")]).text(since: 0)
        #expect(!text.contains("\n"))
    }

    @Test func logMessagesLeaveOutPrivateValues() {
        let name = "Morning tempo"
        let count = 3
        let message: WindRunLogMessage = "Saved \(name) with \(count) steps, \(true), \("public", privacy: .public)"
        #expect(message.text == "Saved Morning tempo with 3 steps, yes, public")
        #expect(message.tracedText == "Saved <hidden> with 3 steps, yes, public")
        #expect(message.hasPrivateValues)
        let plain: WindRunLogMessage = "Settings sync with iCloud"
        #expect(!plain.hasPrivateValues)
    }

    @Test func settingChangesHideValuesThatArentPlainChoices() {
        let old = [DistanceUnit.storageKey: "km", BodyWeight.storageKey: "70", "watchSavedWorkouts": "{…}"]
        let new = [DistanceUnit.storageKey: "miles", BodyWeight.storageKey: "72", "watchSavedWorkouts": "{…!}", HeartRateMonitor.storageKey: "1"]
        let changes = Dictionary(uniqueKeysWithValues: TraceSettings.changes(from: old, to: new).map { ($0.key, $0.value) })
        #expect(changes[DistanceUnit.storageKey] == "miles")
        #expect(changes[BodyWeight.storageKey] == "changed (hidden)")
        #expect(changes["watchSavedWorkouts"] == "changed (hidden)")
        #expect(changes[HeartRateMonitor.storageKey] == "1")
        #expect(!TraceSettings.shownKeys.contains(BodyWeight.storageKey))
        #expect(!TraceSettings.shownKeys.contains(CoachHeartRateStore.storageKey))
        #expect(!TraceSettings.shownKeys.contains(TermsAcceptance.dateKey))
    }

    @Test func valuesShowPlainly() {
        #expect(Trace.text(for: 3.14159) == "3.14")
        #expect(Trace.text(for: 4.0) == "4")
        #expect(Trace.text(for: true) == "yes")
        #expect(Trace.text(for: Optional<Double>.none as Any) == "none")
        #expect(Trace.text(for: Optional(2.5) as Any) == "2.50")
    }
}
