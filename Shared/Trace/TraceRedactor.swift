//
//  TraceRedactor.swift
//  Wind Run
//

import Foundation

/// The last check on every trace line: anything that looks like a personal detail is swapped for a
/// placeholder, in case one slips into a message, such as a path or address in an error's description.
/// Trace lines are written from fixed words to begin with (see `Trace`); this only catches what gets past.
nonisolated enum TraceRedactor {
    private static let rules: [(NSRegularExpression, String)] = [
        // Before the rest, so the parts of an address aren't taken for something else.
        (#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "<email>"),
        (#"\b[a-z][a-z0-9+.-]*://\S+"#, "<link>"),
        // A file path names the app's folders, which can hold a device or account name.
        (#"(?:file:)?(?:/(?:private|var|Users|Volumes|System|Library|Applications|mobile|tmp)\b)\S*"#, "<path>"),
        (#"\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b"#, "<id>"),
        // A latitude and longitude pair, or one number with as many decimal places as a coordinate.
        (#"-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}"#, "<location>"),
        (#"-?\b\d{1,3}\.\d{5,}\b"#, "<number>"),
        // Phone numbers: 9 or more digits, with or without spaces, dots, dashes or brackets between them.
        (#"\+?\(?\d(?:[\s().-]*\d){8,}"#, "<number>"),
    ].map { pattern, placeholder in
        // The patterns are fixed, so they always compile.
        (try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), placeholder)
    }

    static func scrub(_ text: String) -> String {
        // Most lines are a few fixed words; skip the work when nothing could match.
        guard text.contains(where: { $0.isNumber || $0 == "@" || $0 == "/" || $0 == ":" }) else { return text }
        var text = text
        for (expression, placeholder) in rules {
            let range = NSRange(text.startIndex..., in: text)
            text = expression.stringByReplacingMatches(in: text, range: range, withTemplate: placeholder)
        }
        return text
    }
}
