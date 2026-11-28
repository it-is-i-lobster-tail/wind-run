import Foundation
import UIKit
import Testing
@testable import WindRun

/// A misspelled search word is read as the spell checker's fix, only when search can use the fix.
@MainActor
@Suite(.serialized)
struct WorkoutSearchSpellingTests {
    private func record(title: String = "", notes: String = "", type: String = "free") -> WorkoutSearchRecord {
        WorkoutSearchRecord(id: UUID(), date: Date(timeIntervalSince1970: 1_800_000_000), sport: "running",
                            type: type, title: title, notes: notes, distance: 5_000, duration: 1_800,
                            place: nil, terrain: [])
    }

    private func withGuesses<T>(_ table: [String: [String]], _ body: () -> T) -> T {
        let saved = WorkoutSearchSpelling.guesses
        defer { WorkoutSearchSpelling.guesses = saved }
        WorkoutSearchSpelling.guesses = { table[$0] ?? [] }
        return body()
    }

    @Test func aMisspelledWordReadsAsAHistoryWord() {
        let tempo = record(title: "Tempo by the river")
        let easy = record(title: "Easy loop")
        let result = withGuesses(["tmepoo": ["Temple", "Tempo"]]) {
            WorkoutSearchEngine.search(WorkoutSearchEngine.parse("tmepoo"), in: [tempo, easy])
        }
        // "Temple" is in no workout, so the next guess is used, and it counts like the word typed right.
        #expect(result.ids == [tempo.id])
        #expect(result.spelling.words == ["tempo": "tmepoo"])
        #expect(result.notUnderstood.isEmpty)
        #expect(result.appliedIntent.terms == ["tempo"])
    }

    @Test func aMisspelledWordCanReadAsAFilter() {
        let result = withGuesses(["hils": ["hills"]]) {
            WorkoutSearchEngine.search(WorkoutSearchEngine.parse("hils"), in: [record(title: "Loop")])
        }
        #expect(result.appliedIntent.terms.isEmpty)
        #expect(result.appliedIntent.filters.contains(.terrain(.hills)))
        #expect(result.spelling.filters[.terrain(.hills)]?.hasSuffix("(from hils)") == true)
    }

    @Test func aWordTheHistoryHasIsNeverChanged() {
        // The dictionary doesn't know "Fartlek", but a workout says it, so it searches as typed.
        let fartlek = record(title: "Fartlek Friday")
        let result = withGuesses(["fartlek": ["fart lek"], "fartlk": ["fartlek"]]) {
            (WorkoutSearchEngine.search(WorkoutSearchEngine.parse("fartlek"), in: [fartlek]),
             WorkoutSearchEngine.search(WorkoutSearchEngine.parse("Fridya"), in: [fartlek]))
        }
        #expect(result.0.ids == [fartlek.id])
        #expect(result.0.spelling == WorkoutSearchSpelling.Fixes())
        // The search's own typo matching still finds a near spelling of a history word, with no fix needed.
        #expect(result.1.ids == [fartlek.id])
        #expect(result.1.spelling == WorkoutSearchSpelling.Fixes())
    }

    @Test func aFixSearchCannotUseLeavesTheWordNotUnderstood() {
        let result = withGuesses(["zorp": ["zoo", "zip"]]) {
            WorkoutSearchEngine.search(WorkoutSearchEngine.parse("zorp"), in: [record(title: "Easy loop")])
        }
        #expect(result.notUnderstood == ["zorp"])
        #expect(result.spelling == WorkoutSearchSpelling.Fixes())
    }

    @Test func numbersAndShortWordsAreLeftAlone() {
        #expect(!WorkoutSearchSpelling.isCheckable("5k"))
        #expect(!WorkoutSearchSpelling.isCheckable("mi"))
        #expect(WorkoutSearchSpelling.isCheckable("tempo"))
    }

    @Test func theSystemCheckerFixesACommonTypo() {
        // The real checker, as the app uses it.
        #expect(WorkoutSearchSpelling.systemGuesses("tempo").isEmpty)
        #expect(WorkoutSearchSpelling.systemGuesses("recieve").contains("receive"))
    }
}

/// Every word text box checks spelling and autocorrects; number pads are left as they are.
@MainActor
struct SpellCheckTests {
    @Test func wordFieldsGetSpellCheckAndAutocorrect() {
        let field = UITextField()
        #expect(SpellCheck.set(on: field))
        #expect(field.autocorrectionType == .yes && field.spellCheckingType == .yes)
        // Already on: nothing to reload.
        #expect(!SpellCheck.set(on: field))
        let view = UITextView()
        SpellCheck.set(on: view)
        #expect(view.autocorrectionType == .yes && view.spellCheckingType == .yes)
    }

    @Test func numberPadsAndPasswordsAreLeftAlone() {
        for pad in [UIKeyboardType.decimalPad, .numberPad, .numbersAndPunctuation] {
            let field = UITextField()
            field.keyboardType = pad
            SpellCheck.apply(to: field)
            #expect(field.autocorrectionType == .default)
        }
        #expect(!SpellCheck.wanted(keyboard: .default, secure: true))
        #expect(SpellCheck.wanted(keyboard: .webSearch, secure: false))
    }
}
