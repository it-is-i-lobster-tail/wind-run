//
//  TitleCaseTests.swift
//  Wind Run Tests
//

import Testing
@testable import WindRun

/// Names typed in title case: small words go lowercase once the next space is typed, other words don't change.
struct TitleCaseTests {
    /// Types `text` one character at a time, as the keyboard would, and returns what the field shows.
    private func type(_ text: String) -> String {
        var field = ""
        for character in text { field = TitleCase.typed(field + String(character), after: field) }
        return field
    }

    @Test func smallWordsGoLowercase() {
        #expect(type("Lap Of The Park") == "Lap of the Park")
        #expect(type("Run To The Hill And Back") == "Run to the Hill and Back")
    }

    @Test func firstWordKeepsItsCapital() {
        #expect(type("The Long Run") == "The Long Run")
        #expect(type("  A Hill") == "  A Hill")
    }

    @Test func lastWordKeepsItsCapital() {
        #expect(type("Something To Run For") == "Something to Run For")
    }

    @Test func wordsTypedOnPurposeStay() {
        #expect(type("Run OF Hills") == "Run OF Hills")
        #expect(type("easy run") == "easy run")
        #expect(type("Warm Up Then Go") == "Warm Up Then Go")
    }

    @Test func pastingOrDeletingChangesNothing() {
        #expect(TitleCase.typed("Lap Of The Park ", after: "") == "Lap Of The Park ")
        #expect(TitleCase.typed("Lap Of", after: "Lap Of ") == "Lap Of")
    }
}
