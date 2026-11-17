//
//  Logger+WindRun.swift
//  Wind Run
//

import Foundation
import OSLog

// Not tied to the main actor, so code off it (watch messages, Health callbacks) can log too.
extension Logger {
    private nonisolated static let subsystem = "WindRun"

    nonisolated static let run = WindRunLogger(subsystem: subsystem, category: "Run")
    nonisolated static let intervals = WindRunLogger(subsystem: subsystem, category: "Intervals")
    nonisolated static let coach = WindRunLogger(subsystem: subsystem, category: "Coach")
    nonisolated static let recording = WindRunLogger(subsystem: subsystem, category: "Recording")
    nonisolated static let callouts = WindRunLogger(subsystem: subsystem, category: "Callouts")
    nonisolated static let settings = WindRunLogger(subsystem: subsystem, category: "Settings")
    nonisolated static let persistence = WindRunLogger(subsystem: subsystem, category: "Persistence")
    nonisolated static let health = WindRunLogger(subsystem: subsystem, category: "Health")
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
            // The fixed words and public values stay readable in Console; only the private values are hidden.
            logger.log(level: level, "\(message.tracedText, privacy: .public) | \(message.text, privacy: .private)")
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
            if let error = value as? any Error {
                appendInterpolation(error: error, privacy: privacy)
                return
            }
            let shown = Trace.text(for: value)
            text += shown
            let isPublic = switch privacy {
            case .public: true
            case .private: false
            case nil: value is any Numeric || value is Bool
            }
            if isPublic {
                tracedText += shown
            } else {
                tracedText += "<hidden>"
                hasPrivateValues = true
            }
        }

        /// An error: its domain and code always reach the trace, so a failure can be told apart, whatever
        /// the privacy. Its description can hold record names, account ids or paths, so it's only in the
        /// system log, kept private there unless the message marks it public.
        mutating func appendInterpolation(error: any Error, privacy: WindRunLogPrivacy? = nil) {
            let nsError = error as NSError
            let code = "\(nsError.domain) \(nsError.code)"
            text += "\(error.localizedDescription) (\(code))"
            tracedText += code
            if privacy != .public {
                hasPrivateValues = true
            }
        }
    }
}
