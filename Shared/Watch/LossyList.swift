//
//  LossyList.swift
//  Wind Run
//

import Foundation

/// A list decoded one item at a time, so an item this app can't read, such as one from a newer app on the
/// other device, drops only itself instead of the whole list.
nonisolated struct LossyList<Element: Decodable>: Decodable {
    var elements: [Element] = []
    /// How many items couldn't be read.
    var dropped = 0

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else if (try? container.decode(Skipped.self)) != nil {
                dropped += 1
            } else {
                break
            }
        }
    }

    /// Reads past an item without looking at it.
    private struct Skipped: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    /// Decodes `data`, tracing what was dropped or why nothing could be read as `what`.
    static func decode(_ data: Data, what: String) -> [Element] {
        do {
            let list = try JSONDecoder().decode(Self.self, from: data)
            if list.dropped > 0 {
                Trace.log(.watch, "Dropped \(what) it couldn't read", ["dropped": list.dropped, "kept": list.elements.count])
            }
            return list.elements
        } catch {
            Trace.error("Couldn't read \(what)", error)
            return []
        }
    }
}
