//
//  DisplayScreenStorage.swift
//  Wind Run
//

import Foundation
import Synchronization

/// Reading and saving the single display screen kept before saved displays (`DisplayLibrary`). The library
/// still writes its default here, for older versions, and reads it once to become the first saved display.
/// The stored text is only decoded again when it changes, and a screen that can't be read is traced once
/// rather than every tick.
extension DisplayScreen {
    /// The text last read and the screen it made.
    private nonisolated static let lastRead = Mutex<(text: String, screen: DisplayScreen)?>(nil)

    /// The screen stored under the old key, or `standard` when there's none or it can't be read.
    nonisolated static func legacy(in defaults: UserDefaults) -> DisplayScreen {
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

    /// Keeps this under the old key, where older versions read the one display every run shows.
    nonisolated func save(in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.storageKey)
    }
}
