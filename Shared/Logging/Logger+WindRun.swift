//
//  Logger+WindRun.swift
//  Wind Run
//

import Foundation
import OSLog

extension Logger {
    private static let subsystem = "WindRun"

    static let run = WindRunLogger(subsystem: subsystem, category: "Run")
    static let intervals = WindRunLogger(subsystem: subsystem, category: "Intervals")
    static let coach = WindRunLogger(subsystem: subsystem, category: "Coach")
    static let recording = WindRunLogger(subsystem: subsystem, category: "Recording")
    static let callouts = WindRunLogger(subsystem: subsystem, category: "Callouts")
    static let settings = WindRunLogger(subsystem: subsystem, category: "Settings")
    static let persistence = WindRunLogger(subsystem: subsystem, category: "Persistence")
    static let health = WindRunLogger(subsystem: subsystem, category: "Health")
}

/// One of the app's loggers. Each message goes to the system log as `Logger` sends it, and while trace
/// logging is on, also into the trace files. A value the message doesn't mark `privacy: .public` is left
/// out of the trace (and kept private in the system log), the same default `Logger` uses; numbers and
/// yes/no values show, as they do there.
nonisolated struct WindRunLogger: Sendable {
    let logger: Logger
    let category: String

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    func debug(_ message: WindRunLogMessage) { write(.debug, message) }
    func info(_ message: WindRunLogMessage) { write(.info, message) }
    func notice(_ message: WindRunLogMessage) { write(.default, message) }
    func warning(_ message: WindRunLogMessage) { write(.error, message, isWarning: true) }
    func error(_ message: WindRunLogMessage) { write(.error, message) }
    func fault(_ message: WindRunLogMessage) { write(.fault, message) }

    private func write(_ level: OSLogType, _ message: WindRunLogMessage, isWarning: Bool = false) {
        if message.hasPrivateValues {
            logger.log(level: level, "\(message.text, privacy: .private)")
        } else {
            logger.log(level: level, "\(message.text, privacy: .public)")
        }
        let isError = !isWarning && (level == .error || level == .fault)
        Trace.log(isError ? .error : .log, "\(category): \(message.tracedText)")
    }
}

/// How a logged value shows, as with `Logger`'s `privacy:`.
nonisolated enum WindRunLogPrivacy: Sendable {
    case `public`
    case `private`
}

/// A log message written with string interpolation, as for `Logger`.
nonisolated struct WindRunLogMessage: ExpressibleByStringInterpolation, Sendable {
    /// The whole message, for the system log.
    var text: String
    /// The message with private values left out, for the trace.
    var tracedText: String
    var hasPrivateValues: Bool

    init(stringLiteral value: String) {
        text = value
        tracedText = value
        hasPrivateValues = false
    }

    init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
        tracedText = stringInterpolation.tracedText
        hasPrivateValues = stringInterpolation.hasPrivateValues
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var text = ""
        var tracedText = ""
        var hasPrivateValues = false

        init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity)
            tracedText.reserveCapacity(literalCapacity)
        }

        mutating func appendLiteral(_ literal: String) {
            text += literal
            tracedText += literal
        }

        mutating func appendInterpolation<Value>(_ value: Value, privacy: WindRunLogPrivacy? = nil) {
            let shown = Trace.text(for: value)
            text += shown
            let isPublic = switch privacy {
            case .public: true
            case .private: false
            case nil: value is any Numeric || value is Bool
            }
            if isPublic, let error = value as? any Error {
                // An error's description can hold record names, account ids or paths, so the trace only
                // gets its domain and code, even where the system log shows all of it.
                let error = error as NSError
                tracedText += "\(error.domain) \(error.code)"
            } else if isPublic {
                tracedText += shown
            } else {
                tracedText += "<hidden>"
                hasPrivateValues = true
            }
        }
    }
}
