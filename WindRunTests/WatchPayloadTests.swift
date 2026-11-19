//
//  WatchPayloadTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// What passes between the iPhone and the watch: sessions and workouts as the watch reads them, lists with
/// an item the watch can't read, and runs as they come back to the iPhone.
@MainActor
struct WatchPayloadTests {
    private let phone = WindRunSchema.makeContainer(inMemory: true)
    private let watch = WindRunSchema.makeContainer(inMemory: true)
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private let work = WatchCoachSession.Step(kind: .work, goalKind: .time, goalAmount: 60, isWalk: false)
    private let jog = WatchCoachSession.Step(kind: .recovery, goalKind: .distance, goalAmount: 200, isWalk: true)

    private func session(
        blocks: [WatchCoachSession.Block] = [],
        paceFast: TimeInterval? = nil,
        paceSlow: TimeInterval? = nil,
        effortLow: Int? = nil,
        effortHigh: Int? = nil
    ) -> WatchCoachSession {
        WatchCoachSession(
            sessionID: UUID(),
            kind: "intervals",
            title: "Hills",
            detail: "",
            date: day,
            targetMeters: nil,
            targetSeconds: nil,
            paceFast: paceFast,
            paceSlow: paceSlow,
            effortLow: effortLow,
            effortHigh: effortHigh,
            runWalk: nil,
            isKeySession: false,
            isQuality: false,
            stepsSignature: "",
            blocks: blocks
        )
    }

    // MARK: Steps

    @Test func repeatsAreWrittenOutInOrder() {
        let timeline = session(blocks: [WatchCoachSession.Block(repeatCount: 3, steps: [work, jog])]).timeline
        #expect(timeline.count == 6)
        #expect(timeline.map(\.kind) == [.work, .recovery, .work, .recovery, .work, .recovery])
        #expect(timeline.map(\.repetition) == [1, 1, 2, 2, 3, 3])
        #expect(timeline.allSatisfy { $0.repeatCount == 3 })
        #expect(timeline[0].goal == .time(60))
        #expect(timeline[1].goal == .distance(meters: 200))
        #expect(timeline.map(\.isWalk) == [false, true, false, true, false, true])
    }

    @Test func aRepeatCountUnderOneRunsOnce() {
        let blocks = [WatchCoachSession.Block(repeatCount: 0, steps: [work])]
        let timeline = session(blocks: blocks).timeline
        #expect(timeline.count == 1)
        #expect(timeline.first?.repeatCount == 1)
        #expect(timeline.first?.repetition == 1)

        let saved = WatchSavedWorkout(name: "Short", createdDate: day, blocks: blocks)
        #expect(saved.timeline == timeline)
    }

    @Test func blocksGoToTheWatchAndBackUnchanged() {
        let original = IntervalPlan.classicFiveByThree()
        phone.mainContext.insert(original)
        let blocks = original.blocks.map { WatchCoachSession.Block($0) }
        #expect(blocks.map(\.repeatCount) == [1, 5, 1])
        #expect(blocks[1].steps == [
            WatchCoachSession.Step(kind: .work, goalKind: .time, goalAmount: 180, isWalk: false),
            WatchCoachSession.Step(kind: .recovery, goalKind: .time, goalAmount: 120, isWalk: false),
        ])
        #expect(blocks.timeline == original.timeline)

        let copy = IntervalPlan(name: "Copy")
        watch.mainContext.insert(copy)
        copy.addBlocks(blocks)
        #expect(copy.timeline == original.timeline)
        #expect(copy.blocks.map { WatchCoachSession.Block($0) } == blocks)
    }

    // MARK: Targets

    @Test func anUpsideDownRangeIsNoTarget() {
        #expect(session(paceFast: 300, paceSlow: 280).target.pace == nil)
        #expect(session(paceFast: 280, paceSlow: 300).target.pace == 280...300)
        #expect(session(paceFast: 290, paceSlow: 290).target.pace == 290...290)
        #expect(session(paceFast: 290).target.pace == nil)

        #expect(session(effortLow: 5, effortHigh: 3).target.effort == nil)
        #expect(session(effortLow: 3, effortHigh: 5).target.effort == 3...5)
        #expect(session(effortHigh: 5).target.effort == nil)
    }

    // MARK: Lists the watch can only partly read

    @Test func aBadItemIsCountedAndSkipped() throws {
        let list = try JSONDecoder().decode(LossyList<Int>.self, from: Data(#"[1,"x",3]"#.utf8))
        #expect(list.elements == [1, 3])
        #expect(list.dropped == 1)
    }

    @Test func anUnknownStepKindDropsOnlyThatWorkout() {
        let json = #"""
        [
            {"name": "A", "createdDate": 0, "blocks": []},
            {"name": "B", "createdDate": 0, "blocks": [{"repeatCount": 1, "steps": [{"kind": "sprint", "goalKind": "time", "goalAmount": 60, "isWalk": false}]}]},
            {"name": "C", "createdDate": 1, "blocks": []}
        ]
        """#
        let workouts = WatchSavedWorkout.decode(Data(json.utf8))
        #expect(workouts.map(\.name) == ["A", "C"])
    }

    @Test func notAListGivesNothing() {
        #expect(LossyList<Int>.decode(Data("{}".utf8), what: "numbers").isEmpty)
        #expect(LossyList<Int>.decode(Data("not json".utf8), what: "numbers").isEmpty)
        #expect(WatchSavedWorkout.decode(Data("{}".utf8)).isEmpty)
        #expect(WatchCoachSession.decode(Data("{}".utf8)).isEmpty)
    }

    @Test func nothingSentGivesNothing() {
        #expect(WatchCoachSession.decode(nil).isEmpty)
        #expect(WatchSavedWorkout.decode(nil).isEmpty)
    }

    @Test func sessionsComeBackAsTheyWereSent() {
        let sessions = [session(blocks: [WatchCoachSession.Block(repeatCount: 2, steps: [work, jog])]), session()]
        #expect(WatchCoachSession.decode(WatchCoachSession.encode(sessions)) == sessions)
    }

    // MARK: The run back on the iPhone

    /// A finished run on the watch with no coach session, paused once from 20 s to 30 s.
    private func watchRun() -> Run {
        let run = Run(kind: .free, startDate: day)
        watch.mainContext.insert(run)
        run.pause(at: day.addingTimeInterval(20))
        run.resume(at: day.addingTimeInterval(30))
        run.finish(at: day.addingTimeInterval(60))
        return run
    }

    @Test func pausesComeAcrossWithTheRun() throws {
        let record = try #require(WatchRunRecord(watchRun()))
        let inserted = try #require(record.insert(into: phone.mainContext))
        #expect(inserted.pauses.count == 1)
        #expect(inserted.pauses.first?.startDate == day.addingTimeInterval(20))
        #expect(inserted.pauses.first?.endDate == day.addingTimeInterval(30))
        #expect(inserted.status == .complete)
        #expect(inserted.endDate == day.addingTimeInterval(60))
    }

    @Test func anOpenPauseInTheRecordStaysOpen() throws {
        var record = try #require(WatchRunRecord(watchRun()))
        record.pauses = [WatchRunRecord.Pause(start: day.addingTimeInterval(50), end: nil)]
        let inserted = try #require(record.insert(into: phone.mainContext))
        #expect(inserted.pauses.count == 1)
        #expect(inserted.pauses.first?.startDate == day.addingTimeInterval(50))
        #expect(inserted.pauses.first?.endDate == nil)
    }

    @Test func aRunWithoutASessionJoinsOnItsOwn() throws {
        let record = try #require(WatchRunRecord(watchRun()))
        #expect(record.sessionID == nil)
        let inserted = try #require(record.insert(into: phone.mainContext))
        #expect(inserted.coachWorkout == nil)
        #expect(inserted.intervalPlan == nil)
        #expect(inserted.stepLog.isEmpty)
    }

    @Test func aRunForAnUnknownSessionStillJoins() throws {
        var record = try #require(WatchRunRecord(watchRun()))
        record.sessionID = UUID()
        record.stepsSignature = "steps"
        let inserted = try #require(record.insert(into: phone.mainContext))
        #expect(inserted.status == .complete)
        #expect(inserted.coachWorkout == nil)
        #expect(inserted.intervalPlan == nil)
        #expect(inserted.stepLog.isEmpty)
    }

    @Test func stepCountsComeAcross() throws {
        let run = watchRun()
        let steps = Data([1, 2, 3])
        run.stepCountDataValue = steps
        let record = try #require(WatchRunRecord(run))
        let inserted = try #require(record.insert(into: phone.mainContext))
        #expect(inserted.stepCountDataValue == steps)
    }

    @Test func aRunFromAnOlderWatchAppWasStillRecordedOnAWatch() throws {
        var record = try #require(WatchRunRecord(watchRun()))
        record.devices = nil
        let inserted = try #require(record.insert(into: phone.mainContext))
        let devices = try #require(inserted.devices)
        #expect(devices.recorder.kind == .appleWatch)
        #expect(devices.heartRate.isEmpty)
        #expect(devices.receivedBy == DeviceInfo.current)
    }
}
