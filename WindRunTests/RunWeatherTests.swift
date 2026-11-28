//
//  RunWeatherTests.swift
//  Wind Run Tests
//

import CoreLocation
import Foundation
import Testing
@testable import WindRun

struct RunWeatherTests {
    private static let sample = RunWeather(
        temperature: 1.7, feelsLike: -3.4, humidity: 0.81, cloudCover: 0.92,
        windSpeed: 7.6, windGust: 11.2, windFrom: 270,
        symbolName: "cloud", condition: "Cloudy", isDaylight: true,
        date: Date(timeIntervalSince1970: 1_800_000_000), isCurrent: false
    )

    // MARK: The place sent

    @Test func startIsRoundedToTheMiddleOfItsSquare() {
        let sent = RunWeather.roundedLocation(near: CLLocationCoordinate2D(latitude: 39.7392, longitude: -104.9903))
        #expect(sent.coordinate.latitude == 39.725)
        #expect(sent.coordinate.longitude == -104.975)
    }

    @Test func startsInTheSameSquareSendTheSamePlace() {
        let a = RunWeather.roundedLocation(near: CLLocationCoordinate2D(latitude: 51.5007, longitude: -0.1246))
        let b = RunWeather.roundedLocation(near: CLLocationCoordinate2D(latitude: 51.5493, longitude: -0.1004))
        #expect(a.coordinate.latitude == b.coordinate.latitude)
        #expect(a.coordinate.longitude == b.coordinate.longitude)
    }

    @Test(arguments: [
        (37.7749, -122.4194), (-33.8688, 151.2093), (0.0001, -0.0001), (64.1466, -21.9426), (-54.8019, -68.303),
    ])
    func placeSentIsNeverFarFromTheStartButNeverTheStart(latitude: Double, longitude: Double) {
        let start = CLLocation(latitude: latitude, longitude: longitude)
        let sent = RunWeather.roundedLocation(near: start.coordinate)
        #expect(sent.distance(from: start) < 4_000)
        #expect(sent.coordinate.latitude != latitude || sent.coordinate.longitude != longitude)
    }

    // MARK: Which hour

    @Test func hourWindowCoversTheHourOfTheMiddleAndTheNext() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let middle = Date(timeIntervalSince1970: 1_800_000_000 + 40 * 60)
        let (from, to) = RunWeatherFetcher.hourWindow(around: middle, calendar: calendar)
        #expect(from <= middle)
        #expect(middle.timeIntervalSince(from) < 3_600)
        #expect(to.timeIntervalSince(from) == 7_200)
    }

    @Test func nearestHourIsPicked() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let hours = [base, base.addingTimeInterval(3_600)]
        #expect(RunWeatherFetcher.nearest(hours, to: base.addingTimeInterval(20 * 60), date: { $0 }) == base)
        #expect(RunWeatherFetcher.nearest(hours, to: base.addingTimeInterval(40 * 60), date: { $0 }) == hours[1])
        #expect(RunWeatherFetcher.nearest([Date](), to: base, date: { $0 }) == nil)
    }

    // MARK: Showing it

    @Test func temperatureFollowsTheDistanceUnit() {
        #expect(RunWeather.temperature(1.7, unit: .miles) == "35°")
        #expect(RunWeather.temperature(1.7, unit: .kilometers) == "2°")
        #expect(RunWeather.temperature(-0.3, unit: .kilometers) == "0°")
        #expect(RunWeather.temperature(-12.4, unit: .kilometers) == "-12°")
    }

    @Test func windFollowsTheDistanceUnit() {
        #expect(RunWeather.wind(7.6, unit: .miles) == "17 mph")
        #expect(RunWeather.wind(7.6, unit: .kilometers) == "27 km/h")
    }

    @Test func compassPoints() {
        #expect(RunWeather.compass(0) == "N")
        #expect(RunWeather.compass(359) == "N")
        #expect(RunWeather.compass(270) == "W")
        #expect(RunWeather.compass(202.5) == "SSW")
        #expect(RunWeather.compass(-45) == "NW")
    }

    @Test func percentsAreWholeAndClamped() {
        #expect(RunWeather.percent(0.814) == "81%")
        #expect(RunWeather.percent(1.2) == "100%")
    }

    @Test func spokenWords() {
        #expect(Self.sample.spoken(unit: .miles) == "35 degrees, Cloudy, wind 17 miles an hour from the west")
    }

    // MARK: Stored and exported

    @Test @MainActor func weatherIsKeptWithTheRun() {
        let run = Run()
        #expect(run.weather == nil)
        run.saveWeather(Self.sample)
        #expect(run.weather == Self.sample)
    }

    @Test func exportColumnsMatchTheirNames() {
        let fields = RunExport.Builder.weatherFields(Self.sample)
        let names = Array(RunExport.runColumns.suffix(fields.count))
        #expect(names.allSatisfy { $0.hasPrefix("weather_") })
        let row = Dictionary(uniqueKeysWithValues: zip(names, fields))
        #expect(row["weather_temp_c"] == "1.7")
        #expect(row["weather_humidity_pct"] == "81")
        #expect(row["weather_wind_from_deg"] == "270")
        #expect(row["weather_condition"] == "Cloudy")
        #expect(row["weather_at"] == "hour")
        // No time of day goes in.
        #expect(!fields.joined().contains(":"))
        #expect(RunExport.Builder.weatherFields(nil) == Array(repeating: "", count: fields.count))
    }

    @Test @MainActor func weatherSettingsSyncWithTheOthers() {
        #expect(CloudSettings.keys.contains(RunWeatherFetcher.enabledKey))
        #expect(CloudSettings.keys.contains(RunWeatherFetcher.offerAnsweredKey))
    }
}
