//
//  DisplayScreenStorage.swift
//  Wind Run
//

import Foundation
import Synchronization

/// Reading and saving the runner's display screen. Every run screen asks for it each second, so the stored
/// text is only decoded again when it changes, and a screen that can't be read is traced once rather than
/// every tick.
extension DisplayScreen {
    /// The text last read and the screen it made.
    private nonisolated static let lastRead = Mutex<(text: String, screen: DisplayScreen)?>(nil)

    /// The screen the run shows: the one the runner edited, or `standard`.
    nonisolated static var current: DisplayScreen { current(in: .standard) }

    /// The stored screen, or `standard` when there's none or it can't be read.
    nonisolated static func current(in defaults: UserDefaults) -> DisplayScreen {
        guard let text = defaults.string(forKey: storageKey) else { return standard }
        return lastRead.withLock { last in
            if let last, last.text == text { return last.screen }
            let screen = decode(text)
            last = (text, screen)
            return screen
        }
    }

    /// Decodes stored text, tracing what went wrong: no names, just the error's domain and code, or how
    /// many spots held a metric this version doesn't know.
    private nonisolated static func decode(_ text: String) -> DisplayScreen {
        let data = Data(text.utf8)
        do {
            let screen = try JSONDecoder().decode(DisplayScreen.self, from: data)
            let unknown = unknownMetrics(in: data)
            if unknown > 0 {
                Trace.log(.setting, "Display screen metric unknown", ["spots": unknown])
            }
            return screen
        } catch {
            Trace.error("Display screen didn't decode, so Standard shows", error)
            return standard
        }
    }

    /// Keeps this as the screen every run shows.
    nonisolated func save(in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.storageKey)
    }
}
