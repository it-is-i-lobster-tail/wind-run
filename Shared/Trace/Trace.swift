//
//  Trace.swift
//  Wind Run
//

import Foundation
import SwiftUI

/// Developer trace logging: one line for every tap, screen, setting change, save and run event, so a
/// problem can be followed step by step. It's off unless the runner turns it on in Settings → Developer
/// Tool, and turning it off deletes every trace file. The files stay on this iPhone until the runner
/// shares them.
///
/// Lines leave out personal details on purpose, so a shared trace doesn't say who or where the runner is:
/// - no locations: no coordinates, headings, heights or place names, only GPS accuracy and speed
/// - no typed text: text fields only log that they were edited and how long the text is
/// - no names or notes: workout, step and plan names the runner types are left out
/// - no body or health readings: weight, height, age, heart rate values and zones are left out
/// - no clock times: lines are timed in seconds since the app opened, and each session only gives its date
/// - no device name, account or iCloud details
///
/// `TraceRedactor` also scrubs every line for emails, phone numbers, coordinates, web addresses and file
/// paths, in case one slips into a message such as an error's description.
nonisolated enum Trace {
    /// The Trace logging switch. Kept on each device only: it isn't copied to iCloud or the watch, so
    /// trace logging never turns itself on somewhere the runner didn't read the warning.
    static let storageKey = "traceLogging"

    static var isOn: Bool { TraceFiles.shared.isOn }

    /// "2026-11-15" in this device's time zone: the date only, with no clock time, as a session header and a
    /// shared zip's name give it.
    static func day(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    /// Seconds on a clock that keeps counting while the device sleeps, which `systemUptime` doesn't. A
    /// locked-screen run sleeps between GPS fixes, so its gaps show as long as they really were.
    static var clock: TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    /// Adds a line while trace logging is on. `message` and `details` aren't worked out when it's off.
    /// Write them from fixed words and numbers, never from text the runner typed.
    static func log(
        _ kind: TraceKind,
        _ message: @autoclosure () -> String,
        _ details: @autoclosure () -> KeyValuePairs<String, Any> = [:]
    ) {
        let files = TraceFiles.shared
        guard files.isOn else { return }
        let uptime = clock
        let pairs = details().map { ($0.key, Self.text(for: $0.value)) }
        files.write(TraceLine(uptime: uptime, kind: kind, message: message(), details: pairs))
    }

    /// The runner tapped `control` on `screen`, such as `tap("Settings", "Done")`.
    static func tap(
        _ screen: @autoclosure () -> String,
        _ control: @autoclosure () -> String,
        _ details: @autoclosure () -> KeyValuePairs<String, Any> = [:]
    ) {
        log(.tap, "\(screen()) › \(control())", details())
    }

    /// The runner changed `control` on `screen` to `value`, for pickers and switches that aren't a stored
    /// setting (those log themselves as they're saved).
    static func changed(_ screen: @autoclosure () -> String, _ control: @autoclosure () -> String, to value: @autoclosure () -> Any) {
        log(.control, "\(screen()) › \(control())", ["value": value()])
    }

    /// An error as its domain and code only, since an error's description can carry names or paths.
    static func error(_ what: @autoclosure () -> String, _ error: any Error) {
        log(.error, what(), Self.details(of: error))
    }

    static func details(of error: any Error) -> KeyValuePairs<String, Any> {
        let error = error as NSError
        return ["domain": error.domain, "code": error.code]
    }

    /// A value as the line shows it: numbers rounded, optionals unwrapped.
    static func text(for value: Any) -> String {
        switch value {
        case let value as String: value
        case let value as Bool: value ? "yes" : "no"
        case let value as Double: Self.number(value)
        case let value as Float: Self.number(Double(value))
        case let value as CGFloat: Self.number(Double(value))
        case let value as Int: "\(value)"
        default: optionalText(for: value) ?? String(describing: value)
        }
    }

    /// An optional's value, or "none", or nil when `value` isn't an optional.
    private static func optionalText(for value: Any) -> String? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        guard let wrapped = mirror.children.first?.value else { return "none" }
        return text(for: wrapped)
    }

    /// Two decimals at most, with a dot whatever the region.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        if value == value.rounded() && abs(value) < 1e15 { return "\(Int(value))" }
        return String(format: "%.2f", value)
    }
}

/// What a trace line is about, shown in its second column.
nonisolated enum TraceKind: String, CaseIterable, Sendable {
    case app
    case screen
    case tap
    case touch
    case control
    case text
    case keyboard
    case setting
    case data
    case run
    case gps
    case heart
    case motion
    case steps
    case coach
    case callout
    case haptic
    case health
    case icloud
    case watch
    case prompt
    case log
    case error
}

/// One trace line, before it's written.
nonisolated struct TraceLine: Sendable {
    /// `Trace.clock` when it happened.
    var uptime: TimeInterval
    var kind: TraceKind
    var message: String
    var details: [(String, String)] = []

    /// `+   12.345  tap       Settings › Done  key=value`, with the time in seconds since `start`.
    func text(since start: TimeInterval) -> String {
        let seconds = String(format: "+%9.3f", max(0, uptime - start))
        let column = kind.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
        var line = "\(seconds)  \(column) \(TraceRedactor.scrub(message))"
        for (key, value) in details {
            line += "  \(key)=\(TraceRedactor.scrub(value))"
        }
        // One event per line, so a value can't break the file's layout.
        return line.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }
}

extension Binding {
    /// The same binding, logging each new value the runner picks as `Trace.changed`. Pass `describe` to log
    /// something other than the value itself, and never the runner's own text.
    func traced(_ screen: String, _ control: String, describe: @escaping (Value) -> Any = { $0 }) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { value, transaction in
                Trace.changed(screen, control, to: describe(value))
                self.transaction(transaction).wrappedValue = value
            }
        )
    }
}

extension View {
    /// Logs when this screen appears and goes away while trace logging is on. Name it in fixed words, never
    /// from the runner's own text.
    func traceScreen(_ name: String) -> some View {
        onAppear { Trace.log(.screen, "\(name) appeared") }
            .onDisappear { Trace.log(.screen, "\(name) went away") }
    }
}
