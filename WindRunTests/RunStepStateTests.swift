//
//  RunStepStateTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// What the Live Activity reads from the app: the step's clock, and a payload from an older app.
struct RunStepStateTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private func step(startDate: Date? = nil, endDate: Date? = nil, detail: String? = nil, isFinished: Bool = false) -> RunStepState {
        RunStepState(name: "Work", number: 3, count: 8, startDate: startDate, endDate: endDate, detail: detail, isFinished: isFinished)
    }

    // MARK: Clock

    @Test func aTimedStepRunningCountsDown() {
        let end = start.addingTimeInterval(120)

        #expect(step(startDate: start, endDate: end).clock == .countdown(start...end))
    }

    @Test func aTimedStepEndingAsItStartsStillCountsDown() {
        #expect(step(startDate: start, endDate: start).clock == .countdown(start...start))
    }

    @Test func aPausedStepShowsItsDetail() {
        #expect(step(detail: "1:20").clock == .text("1:20"))
    }

    @Test func aDistanceStepShowsItsDetailOverItsStart() {
        #expect(step(startDate: start, detail: "400 m left").clock == .text("400 m left"))
    }

    @Test func anOpenStepRunningCountsUp() {
        #expect(step(startDate: start).clock == .countUp(start))
    }

    @Test func anEndBeforeItsStartFallsToTheDetail() {
        let earlier = start.addingTimeInterval(-10)

        #expect(step(startDate: start, endDate: earlier, detail: "0:00").clock == .text("0:00"))
        #expect(step(startDate: start, endDate: earlier).clock == .countUp(start))
    }

    @Test func aFinishedStepWithNothingToShowHasNoClock() {
        #expect(step(isFinished: true).clock == RunStepState.Clock.none)
    }

    // MARK: Older payloads

    /// What an app from before the display screen, pause and finish sent.
    private struct OlderState: Codable {
        var beatsPerMinute: Int?
        var window: HeartRateWindow
    }

    @Test func aPayloadFromAnOlderAppReadsAsRunning() throws {
        let window = HeartRateWindow(end: start)
        let data = try JSONEncoder().encode(OlderState(beatsPerMinute: 140, window: window))

        let state = try JSONDecoder().decode(HeartRateActivityAttributes.ContentState.self, from: data)

        #expect(state.beatsPerMinute == 140)
        #expect(state.window == window)
        #expect(state.isPaused == nil)
        #expect(state.isFinished == nil)
        #expect(!state.runIsPaused)
        #expect(!state.runIsFinished)
        #expect(state.display == nil)
        #expect(state.step == nil)
    }

    @Test func pausedAndFinishedReadAsSet() {
        var state = HeartRateActivityAttributes.ContentState(beatsPerMinute: nil, window: HeartRateWindow(end: start))
        state.isPaused = true
        state.isFinished = true
        #expect(state.runIsPaused)
        #expect(state.runIsFinished)

        state.isPaused = false
        state.isFinished = false
        #expect(!state.runIsPaused)
        #expect(!state.runIsFinished)
    }
}

/// The Live Activity's buttons reaching the run. These statics are shared, so each test puts back what it found.
@MainActor
@Suite(.serialized)
struct ActiveRunControlTests {
    @Test func aTapWithNoRunIsHeardAsNotHandled() {
        let savedTapped = ActiveRunControl.tapped
        defer { ActiveRunControl.tapped = savedTapped }
        var heard: [String] = []
        ActiveRunControl.tapped = { control, handled in heard.append("\(control) \(handled)") }

        ActiveRunControl.perform("Pause", nil)

        #expect(heard == ["Pause false"])
    }

    @Test func aTapWithARunRunsTheActionOnce() {
        let savedTapped = ActiveRunControl.tapped
        defer { ActiveRunControl.tapped = savedTapped }
        var heard: [String] = []
        ActiveRunControl.tapped = { control, handled in heard.append("\(control) \(handled)") }
        var runs = 0

        ActiveRunControl.perform("Next step") { runs += 1 }

        #expect(runs == 1)
        #expect(heard == ["Next step true"])
    }
}
