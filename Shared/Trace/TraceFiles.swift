//
//  TraceFiles.swift
//  Wind Run
//

import Foundation
import OSLog
import Synchronization

/// One trace file, for the Developer Tool list.
nonisolated struct TraceFile: Identifiable, Hashable, Sendable {
    var url: URL
    /// Counts up from 1 as files are started, so a newer file has a bigger number.
    var number: Int
    var bytes: Int
    var started: Date
    var lastWritten: Date
    /// The file new lines go into.
    var isCurrent: Bool

    var id: URL { url }
    var name: String { "Trace \(number)" }
}

/// Writes trace lines to at most `maximumFiles` files of up to `maximumFileBytes` each, starting a new file
/// when one is full and deleting the oldest past the limit. The files sit in Application Support, kept out
/// of iCloud and device backups, and stay readable with the phone locked mid-run.
///
/// Lines are written in order on one queue, straight to the file, so a crash loses nothing already logged.
nonisolated final class TraceFiles: @unchecked Sendable {
    static let shared = TraceFiles()

    static let defaultMaximumFileBytes = 5 * 1024 * 1024
    static let defaultMaximumFiles = 10

    let directory: URL
    let maximumFileBytes: Int
    let maximumFiles: Int

    private let defaults: UserDefaults
    private let enabled: Atomic<Bool>
    private let queue = DispatchQueue(label: "WindRun.trace", qos: .utility)
    /// `Trace.clock` when the app opened, which line times count from.
    private let sessionStart: TimeInterval
    private let sessionDate: Date

    // Only touched on `queue`.
    private var handle: FileHandle?
    private var current: URL?
    private var currentBytes = 0
    /// Whether this launch's opening lines are in a file yet.
    private var wroteSessionStart = false
    /// The file lines went into was deleted, so the next line starts a new one rather than adding to an older file.
    private var startsFreshFile = false
    /// The biggest file number used, so a file started after the newest was deleted doesn't take its number again.
    private var highestNumber = 0
    /// Lines that couldn't be written, such as with the disk full, counted until writing works again.
    private var droppedLines = 0
    /// After a failed write, nothing is tried again before this, rather than on every line.
    private var retryAt: TimeInterval = 0
    /// Whether the last try failed, so the system log hears about it once, not on every line.
    private var isFailing = false

    /// How long a failed write waits before the next try.
    private static let retryDelay: TimeInterval = 5
    /// For the trace's own failures, which can't go in the trace.
    private static let systemLog = Logger(subsystem: "WindRun", category: "Trace")

    init(
        directory: URL = URL.applicationSupportDirectory.appending(path: "TraceLogs", directoryHint: .isDirectory),
        defaults: UserDefaults = .standard,
        maximumFileBytes: Int = TraceFiles.defaultMaximumFileBytes,
        maximumFiles: Int = TraceFiles.defaultMaximumFiles,
        sessionStart: TimeInterval = Trace.clock,
        sessionDate: Date = .now
    ) {
        self.directory = directory
        self.defaults = defaults
        self.maximumFileBytes = maximumFileBytes
        self.maximumFiles = maximumFiles
        self.sessionStart = sessionStart
        self.sessionDate = sessionDate
        enabled = Atomic(defaults.bool(forKey: Trace.storageKey))
    }

    var isOn: Bool { enabled.load(ordering: .relaxed) }

    /// Starts logging. Call it only once the runner has accepted the warning.
    func turnOn() {
        defaults.set(true, forKey: Trace.storageKey)
        enabled.store(true, ordering: .relaxed)
        write(TraceLine(uptime: Trace.clock, kind: .app, message: "Trace logging turned on"))
    }

    /// Stops logging and deletes every trace file.
    func turnOff() {
        enabled.store(false, ordering: .relaxed)
        defaults.set(false, forKey: Trace.storageKey)
        queue.sync {
            closeFile()
            try? FileManager.default.removeItem(at: directory)
            wroteSessionStart = false
            startsFreshFile = false
            droppedLines = 0
            retryAt = 0
            isFailing = false
        }
    }

    func write(_ line: TraceLine) {
        queue.async { [self] in
            // A line that was on its way as logging turned off is dropped with the files.
            guard isOn else { return }
            append(line)
        }
    }

    /// Every trace file, newest first.
    func files() -> [TraceFile] {
        queue.sync { listFiles() }
    }

    /// The file's text, or nil once it's gone.
    func contents(of file: TraceFile) -> String? {
        let data = queue.sync { try? Data(contentsOf: file.url) }
        return data.map { String(decoding: $0, as: UTF8.self) }
    }

    func delete(_ file: TraceFile) {
        queue.sync {
            if file.isCurrent || file.url == current {
                closeFile()
                startsFreshFile = true
            }
            try? FileManager.default.removeItem(at: file.url)
        }
        write(TraceLine(uptime: Trace.clock, kind: .app, message: "Deleted a trace file", details: [("file", "\(file.number)")]))
    }

    /// Copies of every trace file in a new folder named `folderName`, for zipping. The caller deletes it.
    func copyAll(into parent: URL, folderName: String) throws -> URL {
        try queue.sync {
            let folder = parent.appending(path: folderName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in listFiles() {
                try FileManager.default.copyItem(at: file.url, to: folder.appending(path: file.url.lastPathComponent))
            }
            return folder
        }
    }

    // MARK: - On the queue

    private func append(_ line: TraceLine) {
        if handle == nil {
            // A file that couldn't be written a moment ago, such as with the disk full, gets a rest first.
            guard Trace.clock >= retryAt else {
                droppedLines += 1
                return
            }
            if startsFreshFile { startFile() } else { openNewestFile() }
            guard handle != nil else {
                failed(nil)
                droppedLines += 1
                return
            }
            startsFreshFile = false
            appendText(sessionHeader(continuing: wroteSessionStart))
            wroteSessionStart = true
        }
        // Says where lines went missing, so a trace that stopped isn't read as nothing happening.
        if droppedLines > 0, appendText("==== \(droppedLines) lines dropped here: the trace file couldn't be written\n") {
            droppedLines = 0
        }
        let text = line.text(since: sessionStart) + "\n"
        if currentBytes + text.utf8.count > maximumFileBytes {
            startFile()
            appendText(sessionHeader(continuing: true))
        }
        if !appendText(text) {
            droppedLines += 1
        }
    }

    /// Writes `text`, or returns false when it couldn't be.
    @discardableResult
    private func appendText(_ text: String) -> Bool {
        guard let handle else { return false }
        let data = Data(text.utf8)
        do {
            try handle.write(contentsOf: data)
            currentBytes += data.count
            isFailing = false
            return true
        } catch {
            // The file went away or the disk is full: the next try starts again, after a rest.
            closeFile()
            failed(error)
            return false
        }
    }

    /// Waits before trying again, and tells the system log once, with the error's domain and code only.
    private func failed(_ error: (any Error)?) {
        retryAt = Trace.clock + Self.retryDelay
        guard !isFailing else { return }
        isFailing = true
        let code = error.map { "\(($0 as NSError).domain) \(($0 as NSError).code)" } ?? "the file couldn't be made"
        Self.systemLog.error("Trace file couldn't be written: \(code, privacy: .public)")
    }

    /// Carries on in the newest file if it has room, so each launch doesn't start a nearly empty file.
    private func openNewestFile() {
        if let newest = listFiles().first, newest.bytes < maximumFileBytes, let handle = try? FileHandle(forWritingTo: newest.url) {
            self.handle = handle
            current = newest.url
            currentBytes = Int((try? handle.seekToEnd()) ?? UInt64(newest.bytes))
        } else {
            startFile()
        }
    }

    private func startFile() {
        closeFile()
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
        ])
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)

        let existing = listFiles()
        // Room for the new file: the oldest go first.
        for old in existing.dropFirst(max(0, maximumFiles - 1)) {
            try? manager.removeItem(at: old.url)
        }
        let number = max(existing.map(\.number).max() ?? 0, highestNumber) + 1
        highestNumber = number
        let url = directory.appending(path: Self.fileName(number))
        guard manager.createFile(atPath: url.path, contents: nil, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
        ]) else { return }
        handle = try? FileHandle(forWritingTo: url)
        current = url
        currentBytes = 0
    }

    private func closeFile() {
        try? handle?.close()
        handle = nil
        current = nil
        currentBytes = 0
    }

    private func listFiles() -> [TraceFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url -> TraceFile? in
            guard let number = Self.number(of: url) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isCurrent = url.standardizedFileURL == current?.standardizedFileURL
            return TraceFile(
                url: url,
                number: number,
                bytes: isCurrent ? currentBytes : values?.fileSize ?? 0,
                started: values?.creationDate ?? .distantPast,
                lastWritten: values?.contentModificationDate ?? .distantPast,
                isCurrent: isCurrent
            )
        }
        .sorted { $0.number > $1.number }
    }

    private func sessionHeader(continuing: Bool) -> String {
        let day = sessionDate.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let lead = continuing ? "Carried on from an earlier file" : "App opened"
        return """
            ==== \(lead) · \(day) · Wind Run \(Self.appVersion) · \(Self.deviceModel) · \(Self.systemVersion)
            ==== Times are seconds since the app opened. Locations, typed text, names, notes, body and health readings are left out.

            """
    }

    static func fileName(_ number: Int) -> String {
        String(format: "trace-%04d.log", number)
    }

    static func number(of url: URL) -> Int? {
        let name = url.lastPathComponent
        guard name.hasPrefix("trace-"), name.hasSuffix(".log") else { return nil }
        return Int(name.dropFirst("trace-".count).dropLast(".log".count))
    }

    /// "0.2.0 (57)", as `AppVersion` gives it.
    static let appVersion: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()

    /// The hardware model, such as "iPhone17,1", never the name the runner gave the device.
    static let deviceModel: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return "\(simulated) simulator" }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    static let systemVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(watchOS)
        let system = "watchOS"
        #else
        let system = "iOS"
        #endif
        return "\(system) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }()
}
