//
//  DisplayModelTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Saved displays as stored values: their spots, decoding, names, the keys they're kept under, what uses
/// each, and what a runner's settings leave blank.
@MainActor
struct DisplayModelTests {
    private func defaults() -> UserDefaults {
        let name = "DisplayModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let hills = DisplayScreen(name: "Hills", primary: .elapsed, secondary: .distance, tiles: [.grade, .gradeAdjustedPace, .elevation, .heartRate])

    private func decode(_ json: String) throws -> DisplayScreen {
        try JSONDecoder().decode(DisplayScreen.self, from: Data(json.utf8))
    }

    // MARK: Spots

    @Test func theOtherSpotShowingAMetricIsFound() {
        let standard = DisplayScreen.standard

        #expect(standard.slot(showing: .cadence, otherThan: .primary) == .tile(3))
        #expect(standard.slot(showing: .elapsed, otherThan: .secondary) == .primary)
        #expect(standard.slot(showing: .elapsed, otherThan: .primary) == nil)
        #expect(standard.slot(showing: .grade, otherThan: .primary) == nil)
    }

    @Test func resetPutsStandardBackAndKeepsTheNameAndId() {
        var screen = hills
        #expect(!screen.hasStandardSpots)

        screen.reset()

        #expect(screen.id == hills.id)
        #expect(screen.name == "Hills")
        #expect(screen.hasStandardSpots)
        #expect(screen.metrics == DisplayScreen.standard.metrics)
    }

    @Test func placingOneMetricLeavesStandard() {
        var screen = DisplayScreen.standard
        #expect(screen.hasStandardSpots)

        screen.place(.grade, in: .tile(0))

        #expect(!screen.hasStandardSpots)
    }

    @Test func noTilesFillFromTheStandardGrid() {
        let screen = DisplayScreen(name: "Empty", primary: .distance, secondary: .elapsed, tiles: [])

        #expect(screen.tiles == DisplayScreen.standard.tiles)
    }

    @Test func theGridFallsIntoRowsOfTwo() {
        #expect(DisplayTileLayout.rows(count: 4) == [0..<2, 2..<4])
        #expect(DisplayTileLayout.rows(count: 3) == [0..<2, 2..<3])
        #expect(DisplayTileLayout.rows(count: 2) == [0..<2])
        #expect(DisplayTileLayout.rows(count: 0).isEmpty)
    }

    @Test func slotsHaveIdsNamesAndPhrases() {
        #expect(DisplaySlot.all.map(\.id) == ["primary", "secondary", "tile0", "tile1", "tile2", "tile3"])
        #expect(DisplaySlot.all.map(\.name) == ["Main number", "Second number", "Top left", "Top right", "Bottom left", "Bottom right"])
        #expect(DisplaySlot.primary.phrase == "the main number")
        #expect(DisplaySlot.tile(2).phrase == "the bottom left spot")
    }

    // MARK: Decoding

    @Test func aMetricShownTwiceTakesStandardsMetricForThatSpot() throws {
        let screen = try decode(#"{"id":"6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F","name":"Twice","primary":"cadence","secondary":"distance","tiles":["cadence","heartRate","grade","altitude"]}"#)

        #expect(screen.primary == .cadence)
        #expect(screen.tiles == [.currentPace, .heartRate, .grade, .altitude])
        #expect(Set(screen.metrics).count == 6)
    }

    @Test func fewerTilesPadFromStandard() throws {
        let screen = try decode(#"{"id":"6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F","name":"Short","primary":"elapsed","secondary":"distance","tiles":["grade"]}"#)

        #expect(screen.tiles == [.grade, .heartRate, .elevation, .cadence])
    }

    @Test func extraTilesAreLeftOut() throws {
        let screen = try decode(#"{"id":"6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F","name":"Long","primary":"elapsed","secondary":"distance","tiles":["grade","altitude","daylight","calories","cadence"]}"#)

        #expect(screen.tiles == [.grade, .altitude, .daylight, .calories])
    }

    @Test func batteryIsSwappedForTheStandardSpot() throws {
        let tile = try decode(#"{"id":"6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F","name":"Hills","primary":"elapsed","secondary":"distance","tiles":["grade","battery","altitude","cadence"]}"#)
        #expect(tile.tiles == [.grade, .heartRate, .altitude, .cadence])

        let headline = try decode(#"{"id":"6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F","name":"Odd","primary":"battery","secondary":"distance","tiles":["currentPace","heartRate","heightFromStart","cadence"]}"#)
        #expect(headline.primary == .elapsed)
        #expect(Set(headline.metrics).count == 6)

        let taken = try decode(#"{"id":"6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F","name":"Full","primary":"elapsed","secondary":"distance","tiles":["currentPace","battery","heartRate","cadence"]}"#)
        #expect(!taken.metrics.contains { $0.rawValue == "battery" })
        #expect(Set(taken.metrics).count == 6)
    }

    @Test func batteryIsNotCountedAsUnknown() {
        let json = #"{"primary":"elapsed","secondary":"distance","tiles":["battery","new1","grade","cadence"]}"#

        #expect(DisplayScreen.unknownMetrics(in: Data(json.utf8)) == 1)
    }

    @Test func ascentAndDescentBecomeElevation() throws {
        let one = try decode(#"{"id":"6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F","name":"Hills","primary":"elapsed","secondary":"distance","tiles":["grade","totalAscent","altitude","cadence"]}"#)
        #expect(one.tiles == [.grade, .elevation, .altitude, .cadence])

        let both = try decode(#"{"id":"6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F","name":"Hills","primary":"elapsed","secondary":"distance","tiles":["totalAscent","totalDescent","grade","cadence"]}"#)
        #expect(both.tiles == [.elevation, .heartRate, .grade, .cadence])

        let json = #"{"primary":"elapsed","secondary":"distance","tiles":["totalAscent","totalDescent","heightFromStart","cadence"]}"#
        #expect(DisplayScreen.unknownMetrics(in: Data(json.utf8)) == 0)
    }

    @Test func elevationKeepsTheOldStoredName() {
        #expect(DisplayMetric(rawValue: "heightFromStart") == .elevation)
    }

    @Test func noMetricIsCalledBattery() {
        #expect(DisplayMetric(rawValue: "battery") == nil)
        #expect(DisplayMetric.allCases.allSatisfy { !DisplayScreen.retiredMetrics.contains($0.rawValue) })
    }

    @Test func unknownMetricsAreCountedInTheSixSpotsOnly() {
        let json = #"{"primary":"new1","secondary":"distance","tiles":["grade","later","other","cadence","alsoNew"]}"#

        #expect(DisplayScreen.unknownMetrics(in: Data(json.utf8)) == 3)
        #expect(DisplayScreen.unknownMetrics(in: Data("not json".utf8)) == 0)
    }

    @Test func readingsFromTheAppDecodeInTheLiveActivity() throws {
        let json = #"""
        {"primary":{"metric":"elapsed","value":"32:48","label":"ELAPSED","clockStart":100,"isDimmed":false,"spoken":"Elapsed time, 32:48"},
         "secondary":{"metric":"distance","value":"6.40","unit":"km","label":"DISTANCE","isDimmed":false,"spoken":"Distance, 6.40 km"},
         "tiles":[{"metric":"heartRate","value":"148","unit":"bpm","label":"HEART RATE","symbol":"heart.fill","tint":"heartRate","isDimmed":true,"spoken":"Heart rate, 148 beats per minute"}]}
        """#

        let readings = try JSONDecoder().decode(DisplayScreenReadings.self, from: Data(json.utf8))

        #expect(readings.primary.metric == .elapsed)
        #expect(readings.primary.unit == nil)
        #expect(readings.primary.clockStart == Date(timeIntervalSinceReferenceDate: 100))
        #expect(readings.secondary.unit == "km")
        #expect(readings.tiles.count == 1)
        #expect(readings.tiles[0].symbol == "heart.fill")
        #expect(readings.tiles[0].tint == .heartRate)
        #expect(readings.tiles[0].isDimmed)
        #expect(readings.tiles[0].spoken == "Heart rate, 148 beats per minute")
    }

    // MARK: Stored keys

    @Test func theStoredKeysStayTheSame() {
        #expect(DisplayScreen.storageKey == "displayScreen")
        #expect(DisplayLibrary.screensKey == "displayScreens")
        #expect(DisplayLibrary.defaultKey == "defaultDisplayScreen")
        #expect(DisplayRunKind.storageKeys == ["displayScreenFree", "displayScreenCycling", "displayScreenHike", "displayScreenDistance", "displayScreenTimed", "displayScreenCoach"])
        #expect(DisplayScreen.standard.id == UUID(uuidString: "6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F"))
    }

    @Test func theStoredMetricNamesStayTheSame() {
        #expect(DisplayMetric.allCases.map(\.rawValue) == [
            "elapsed", "distance", "currentPace", "averagePace", "heartRate", "heightFromStart", "cadence",
            "splitPace", "lastSplit", "rollingPace", "stepLeft", "goalLeft", "projectedFinish", "aheadBehind",
            "heartRateZone", "averageHeartRate", "altitude", "grade", "verticalSpeed",
            "gradeAdjustedPace", "timeOfDay", "totalTime", "calories", "daylight", "distanceToStart",
            "strideLength", "runningPower", "cyclingCadence", "cyclingPower",
        ])
    }

    // MARK: Library

    @Test func anEmptyListStartsWithEveryday() {
        let library = DisplayLibrary(screens: [])

        #expect(library.screens.count == 1)
        #expect(library.defaultScreen.name == DisplayLibrary.firstName)
        #expect(library.defaultID == DisplayScreen.standard.id)
        #expect(!library.contains(nil))
        #expect(library.contains(DisplayScreen.standard.id))
    }

    @Test func theDefaultSortsFirstAndTheRestKeepTheirOrder() {
        var library = DisplayLibrary(screens: [hills])
        let second = library.add()!
        let third = library.add()!
        library.makeDefault(third.id)

        #expect(library.sorted.map(\.id) == [third.id, hills.id, second.id])
        #expect(library.screen(id: nil).id == third.id)
    }

    @Test func changesToADisplayNotInTheListDoNothing() {
        var library = DisplayLibrary(screens: [hills])
        let before = library

        library.makeDefault(UUID())
        library.update(DisplayScreen(name: "Stranger", primary: .elapsed, secondary: .distance, tiles: []))

        #expect(library == before)
    }

    @Test func uniqueNamesIgnoreCaseAndLeaveRoomForANumber() {
        let library = DisplayLibrary(screens: [hills])

        #expect(library.uniqueName("hills") == "hills 2")
        #expect(library.uniqueName("Hills") == "Hills 2")
        #expect(library.uniqueName("Tempo") == "Tempo")
        #expect(library.uniqueName(String(repeating: "a", count: 40)).count == DisplayLibrary.nameLimit - 3)
    }

    @Test func typingANameCutsKeepsOrRenames() {
        let long = String(repeating: "a", count: DisplayLibrary.nameLimit + 1)

        #expect(DisplayLibrary.nameEdit(typed: long, current: "Hills") == .cut(String(repeating: "a", count: DisplayLibrary.nameLimit)))
        #expect(DisplayLibrary.nameEdit(typed: "  ", current: "Hills") == .keep)
        #expect(DisplayLibrary.nameEdit(typed: " Hills ", current: "Hills") == .keep)
        #expect(DisplayLibrary.nameEdit(typed: "Hills 2 ", current: "Hills") == .rename("Hills 2"))
        #expect(DisplayLibrary.nameEdit(typed: String(repeating: "a", count: DisplayLibrary.nameLimit), current: "Hills") == .rename(String(repeating: "a", count: DisplayLibrary.nameLimit)))
    }

    // MARK: Adding and what uses each

    @Test func addingACopySavesIt() {
        let defaults = defaults()
        var library = DisplayLibrary(screens: [hills])

        let copy = DisplayActions.add(copying: hills, to: &library, traced: false, defaults: defaults)

        #expect(copy?.name == "Hills Copy")
        #expect(copy?.metrics == hills.metrics)
        #expect(DisplayLibrary.current(in: defaults).screens.map(\.name) == ["Hills", "Hills Copy"])
    }

    @Test func aFullLibraryAddsNothingAndSavesNothing() {
        let defaults = defaults()
        var library = DisplayLibrary(screens: [hills])
        while library.add() != nil {}

        #expect(DisplayActions.add(to: &library, traced: false, defaults: defaults) == nil)
        #expect(defaults.string(forKey: DisplayLibrary.screensKey) == nil)
    }

    @Test func usageSaysWhatShowsEachDisplay() {
        let defaults = defaults()
        var library = DisplayLibrary(screens: [.standard, hills])
        let unused = library.add()!
        DisplayRunKind.free.setPick(hills.id, in: defaults)
        let workouts: [(id: UUID?, name: String)] = [(id: hills.id, name: "Hill Repeats"), (id: nil, name: "Tempo")]

        #expect(DisplayActions.usage(of: .standard, in: library, workouts: workouts, defaults: defaults) == "Shows on any run that doesn't pick another")
        #expect(DisplayActions.usage(of: hills, in: library, workouts: workouts, defaults: defaults) == "Hill Repeats, Free Run")
        #expect(DisplayActions.usage(of: unused, in: library, workouts: workouts, defaults: defaults) == "Not used yet")
    }

    // MARK: What settings leave blank

    @Test func caloriesNeedAWeight() {
        let defaults = defaults()
        #expect(DisplayMetric.calories.missingRequirement(in: defaults) == "Shows a dash until you add your weight in Settings.")

        BodyWeight.save(70, in: defaults)
        #expect(DisplayMetric.calories.missingRequirement(in: defaults) == nil)
    }

    @Test func cadenceAndStrideNeedSteps() {
        let defaults = defaults()
        #expect(DisplayMetric.cadence.missingRequirement(in: defaults) == "Shows a dash until Steps and cadence is on in Settings.")
        #expect(DisplayMetric.strideLength.missingRequirement(in: defaults) == "Shows a dash until Steps and cadence is on in Settings.")

        defaults.set(true, forKey: MotionMonitor.stepsKey)
        #expect(DisplayMetric.cadence.missingRequirement(in: defaults) == nil)
        #expect(DisplayMetric.strideLength.missingRequirement(in: defaults) == nil)
    }

    @Test func heartRateZonesNeedHeartRateThenARunWithIt() {
        let defaults = defaults()
        let off = "Shows a dash until heart rate is on in Settings."
        #expect(DisplayMetric.heartRate.missingRequirement(in: defaults) == off)
        #expect(DisplayMetric.averageHeartRate.missingRequirement(in: defaults) == off)
        #expect(DisplayMetric.heartRateZone.missingRequirement(in: defaults) == off)

        defaults.set(true, forKey: HeartRateMonitor.storageKey)
        #expect(DisplayMetric.heartRate.missingRequirement(in: defaults) == nil)
        #expect(DisplayMetric.heartRateZone.missingRequirement(in: defaults) == "Shows a dash until you've run with heart rate once.")

        defaults.set(185.0, forKey: HeartRateMax.storageKey)
        #expect(DisplayMetric.heartRateZone.missingRequirement(in: defaults) == nil)
    }

    @Test func mostMetricsNeedNothing() {
        let defaults = defaults()

        #expect(DisplayMetric.elapsed.missingRequirement(in: defaults) == nil)
        #expect(DisplayMetric.grade.missingRequirement(in: defaults) == nil)
    }

    // MARK: Heights and the sun

    @Test func heightsGoWithTheDistanceUnit() {
        #expect(DistanceUnit.miles.height(fromMeters: 0.3048) == 1)
        #expect(DistanceUnit.kilometers.height(fromMeters: 12) == 12)
        #expect(DistanceUnit.miles.heightSymbol == "ft")
        #expect(DistanceUnit.kilometers.heightSymbol == "m")
        #expect(DistanceUnit.miles.spokenHeightUnit == "feet")
        #expect(DistanceUnit.kilometers.spokenHeightUnit == "meters")
    }

    @Test func thePolarSummerSunNeverSets() {
        // The June solstice is day 172.
        #expect(SunTimes.hoursUTC(dayOfYear: 172, latitude: 89, longitude: 0, rising: true) == nil)
        #expect(SunTimes.hoursUTC(dayOfYear: 172, latitude: 89, longitude: 0, rising: false) == nil)
    }

    @Test func sydneysJuneSunsetIsEarlyInTheUTCMorning() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let midnight = try #require(utc.date(from: DateComponents(year: 2026, month: 6, day: 21)))

        let event = try #require(SunTimes.next(after: midnight, latitude: -33.87, longitude: 151.21))

        #expect(event.isSunset)
        #expect([6, 7].contains(utc.component(.hour, from: event.date)))
    }
}
