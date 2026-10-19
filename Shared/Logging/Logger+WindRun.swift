//
//  Logger+WindRun.swift
//  Wind Run
//

import OSLog

extension Logger {
    private static let subsystem = "WindRun"

    static let run = Logger(subsystem: subsystem, category: "Run")
    static let intervals = Logger(subsystem: subsystem, category: "Intervals")
    static let coach = Logger(subsystem: subsystem, category: "Coach")
    static let recording = Logger(subsystem: subsystem, category: "Recording")
    static let callouts = Logger(subsystem: subsystem, category: "Callouts")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
}
