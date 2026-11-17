//
//  TraceTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
import UIKit
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
        // Just into a second file, so the current one has room for the next lines whatever the header's length.
        var index = 0
        while files.files().count < 2 {
            files.write(line("Tap number \(index) on a screen with a longer name"))
            index += 1
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
        // No clock times or time zone: each entry's header starts "PK\u{3}\u{4}" and has its modified time 10
        // bytes in, which is 0 at midnight, its date 12 bytes in, 1 January 1980, and no extra fields, where
        // a system zip keeps its UTC times.
        let bytes = [UInt8](data)
        var entries = 0
        for start in 0 ..< max(0, bytes.count - 30) where bytes[start ..< start + 4].elementsEqual([0x50, 0x4B, 0x03, 0x04]) {
            entries += 1
            #expect(bytes[start + 10] == 0 && bytes[start + 11] == 0)
            #expect(bytes[start + 12] == 0x21 && bytes[start + 13] == 0)
            #expect(bytes[start + 28] == 0 && bytes[start + 29] == 0)
        }
        #expect(entries == files.files().count)
    }

    // MARK: - Personal details

    /// Where each key was pressed would give back what was typed, so touches on a keyboard are told apart by
    /// the class names of the view, the views holding it and the window.
    @Test func touchesOnAKeyboardAreToldApart() {
        let keyboard = KeyboardKeyStandIn()
        let key = UIView()
        keyboard.addSubview(key)
        #expect(TraceHooks.isOnKeyboard(keyboard, in: nil))
        #expect(TraceHooks.isOnKeyboard(key, in: nil))
        #expect(TraceHooks.isOnKeyboard(UIView(), in: RemoteKeyboardWindowStandIn()))
        #expect(!TraceHooks.isOnKeyboard(UIButton(), in: nil))
        #expect(!TraceHooks.isOnKeyboard(nil, in: UIWindow()))
    }

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

    @Test func logMessagesGiveOnlyAnErrorsDomainAndCode() {
        let error = NSError(domain: "CKErrorDomain", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Record _3f2c9a1b7d8e4f60a1b2c3d4e5f60718 in the zone on Example Phone failed",
        ])
        let message: WindRunLogMessage = "iCloud export failed: \(error, privacy: .public)"
        #expect(message.text.contains("Example Phone"))
        #expect(message.tracedText == "iCloud export failed: CKErrorDomain 2")
    }

    @Test func anErrorWithoutPrivacyStillGivesItsDomainAndCode() {
        let error = NSError(domain: "com.apple.healthkit", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "Protected health data is inaccessible",
        ])
        let message: WindRunLogMessage = "Couldn't save run to Health: \(error)"
        #expect(message.tracedText == "Couldn't save run to Health: com.apple.healthkit 6")
        // The description stays out of the public part of the system log.
        #expect(message.hasPrivateValues)
        #expect(message.text.contains("inaccessible"))
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

/// Named like the views a keyboard is drawn with.
private final class KeyboardKeyStandIn: UIView {}

/// Named like the window a keyboard is drawn in.
private final class RemoteKeyboardWindowStandIn: UIWindow {}
