//
//  DisplayScreenTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The display screen: what its six spots hold, and how each reading reads.
struct DisplayScreenTests {
    private let snapshot = RunSnapshot(
        elapsed: 32 * 60 + 48,
        meters: 6_400,
        unit: .kilometers,
        currentPace: 312,
        averagePace: 307.6,
        beatsPerMinute: 148.4,
        heightFromStart: -43.2,
        cadence: 171.6
    )

    @Test func theStandardScreenIsTimeDistanceThenPaceHeartRateElevationCadence() {
        let screen = DisplayScreen.standard

        #expect(screen.primary == .elapsed)
        #expect(screen.secondary == .distance)
        #expect(screen.tiles == [.currentPace, .heartRate, .heightFromStart, .cadence])
        #expect(screen.metrics.count == 6)
        #expect(DisplayScreen.current == .standard)
    }

    @Test func aScreenAlwaysHasFourTiles() {
        var screen = DisplayScreen(name: "Short", primary: .distance, secondary: .elapsed, tiles: [.averagePace])
        #expect(screen.tiles == [.averagePace, .heartRate, .heightFromStart, .cadence])

        screen.tiles = [.cadence, .cadence, .cadence, .cadence, .heartRate]
        #expect(screen.tiles == [.cadence, .cadence, .cadence, .cadence])
    }

    @Test func aScreenKeepsAndComesBackFromStorage() throws {
        let screen = DisplayScreen(name: "Hills", primary: .distance, secondary: .heightFromStart, tiles: [.elapsed, .averagePace, .heartRate, .cadence])
        let data = try JSONEncoder().encode(screen)

        #expect(try JSONDecoder().decode(DisplayScreen.self, from: data) == screen)
    }

    @Test func theStandardScreenReadsAsTheRunStands() {
        let readings = DisplayScreen.standard.readings(snapshot)

        #expect(readings.primary.value == "32:48")
        #expect(readings.primary.label == "ELAPSED")
        #expect(readings.primary.clockStart == nil)
        #expect(readings.secondary.value == "6.40")
        #expect(readings.secondary.unit == "km")
        #expect(readings.secondary.label == "DISTANCE")
        #expect(readings.tiles.map(\.value) == ["5:12", "148", "43", "172"])
        #expect(readings.tiles.map(\.unit) == ["/km", "bpm", "m", "spm"])
        #expect(readings.tiles.map(\.label) == ["CURRENT PACE", "HEART RATE", "BELOW START", "CADENCE"])
        #expect(readings.tiles[1].tint == .heartRate)
        #expect(readings.tiles[2].symbol == "arrow.down")
    }

    @Test func theScreensOwnChoiceDecidesWhatShows() {
        let screen = DisplayScreen(name: "Pace first", primary: .currentPace, secondary: .averagePace, tiles: [.elapsed, .distance, .heartRate, .heightFromStart])
        let readings = screen.readings(snapshot)

        #expect(readings.primary.label == "CURRENT PACE")
        #expect(readings.secondary.value == "5:07")
        #expect(readings.secondary.label == "AVG PACE")
        #expect(readings.tiles.map(\.metric) == [.elapsed, .distance, .heartRate, .heightFromStart])
    }

    @Test func missingReadingsShowADash() {
        let empty = RunSnapshot(elapsed: 5, meters: 0, unit: .kilometers)
        let readings = DisplayScreen.standard.readings(empty)

        #expect(readings.tiles.map(\.value) == ["–:––", "––", "––", "––"])
        #expect(readings.tiles[2].label == "ELEVATION")
    }

    @Test func pausedDimsTheClockAndDropsThePace() {
        var paused = snapshot
        paused.isPaused = true
        let readings = DisplayScreen.standard.readings(paused, clockRunsAt: .now)

        #expect(readings.primary.isDimmed)
        #expect(readings.primary.clockStart == nil, "A paused clock doesn't count on")
        #expect(readings.tiles[0].value == "–:––")
    }

    @Test func theLockScreenClockCountsFromWhenTheRunsTimeStarted() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let readings = DisplayScreen.standard.readings(snapshot, clockRunsAt: now)

        #expect(readings.primary.clockStart == now.addingTimeInterval(-1_968))
        #expect(readings.secondary.clockStart == nil)
    }

    @Test func elevationReadsAboveOrAtTheStart() {
        var above = snapshot
        above.heightFromStart = 12.4
        var level = snapshot
        level.heightFromStart = -0.3

        let up = DisplayMetric.heightFromStart.reading(above)
        let flat = DisplayMetric.heightFromStart.reading(level)
        #expect(up.value == "12")
        #expect(up.label == "ABOVE START")
        #expect(up.symbol == "arrow.up")
        #expect(flat.value == "0")
        #expect(flat.label == "AT START")
    }

    @Test func milesReadInFeetAndPerMile() {
        var miles = snapshot
        miles.unit = .miles
        let readings = DisplayScreen.standard.readings(miles)

        #expect(readings.secondary.unit == "mi")
        #expect(readings.tiles[0].unit == "/mi")
        #expect(readings.tiles[2].unit == "ft")
        #expect(readings.tiles[2].value == "142")
    }

    @Test func aCoachGoalNamesTheDistanceOrTime() {
        var coached = snapshot
        coached.goalMeters = 8_000
        coached.goalSeconds = 40 * 60
        let readings = DisplayScreen.standard.readings(coached)

        #expect(readings.secondary.label == "OF 8.00 KM")
        #expect(readings.primary.label == "OF 40:00")
    }

    @Test func aCoachPaceRangeNamesTheCurrentPace() {
        var coached = snapshot
        coached.paceTarget = 290...305
        let readings = DisplayScreen.standard.readings(coached)

        #expect(readings.tiles[0].label == "TARGET 4:50–5:05")
        #expect(readings.tiles[0].value == "5:12")
    }

    @Test func readingsAreSmallEnoughForTheLiveActivity() throws {
        let readings = DisplayScreen.standard.readings(snapshot, clockRunsAt: .now)
        let data = try JSONEncoder().encode(readings)

        // A Live Activity's whole state has to stay under 4 KB, with heart rate and the step too.
        #expect(data.count < 2_000)
    }
}
