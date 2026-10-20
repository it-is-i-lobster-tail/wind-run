//
//  CoachInbox.swift
//  Wind Run
//

import Foundation
import Observation

/// What the coach last said and what it's waiting to ask, shared by the coach screens.
@Observable
final class CoachInbox {
    /// The coach's latest notes, until the runner dismisses them.
    var notes: [CoachNote] = []
    /// The questions the coach is waiting on, in order.
    var questions: [CoachQuestion] = []

    /// Takes in what an engine call returned. New notes replace the old; questions follow the engine,
    /// with any the call itself just asked kept in front.
    func receive(_ update: CoachUpdate, after earlier: [CoachQuestion] = []) {
        if !update.notes.isEmpty {
            notes = update.notes
        }
        var seen = Set<CoachQuestion>()
        questions = (earlier + update.questions).filter { seen.insert($0).inserted }
    }

    func dismissNotes() {
        notes = []
    }
}
