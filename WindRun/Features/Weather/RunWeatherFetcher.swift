//
//  RunWeatherFetcher.swift
//  Wind Run
//
//  Asks Apple Weather once for a finished run's weather, with Weather for Runs on.
//

import CoreLocation
import Foundation
import SwiftData
import WeatherKit

@MainActor
enum RunWeatherFetcher {
    /// Weather for Runs, off until the runner turns it on. Synced with the other settings.
    nonisolated static let enabledKey = "runWeatherEnabled"
    /// Set once the runner answers the offer on a run's page, either way. Synced too, so a new iPhone
    /// doesn't offer again.
    nonisolated static let offerAnsweredKey = "runWeatherOfferAnswered"
    nonisolated static let syncedKeys = [enabledKey, offerAnsweredKey]

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Runs asked about since the app opened, so a run Apple Weather had nothing for isn't asked about
    /// again every time its page opens. Cleared when the app restarts, for a second try.
    private static var asked: Set<UUID> = []

    /// Whether a run could get its weather now: finished, without weather yet, from a time Apple Weather
    /// has history for, and not asked about already.
    static func needsWeather(_ run: Run, now: Date = .now) -> Bool {
        guard isEnabled, run.status == .complete, run.weatherDataValue == nil,
              let end = run.endDate, end <= now, run.startDate >= RunWeather.earliestHistory else { return false }
        return !asked.contains(run.runID)
    }

    /// Fetches and keeps the weather for `run`, which started at `start`. Only the middle of the 0.05° square
    /// around the start and the run's time are sent. Does nothing when `needsWeather` is false.
    static func fillIn(_ run: Run, start: CLLocation, context: ModelContext, now: Date = .now) async {
        guard needsWeather(run, now: now), let end = run.endDate else { return }
        asked.insert(run.runID)
        let place = RunWeather.roundedLocation(near: start.coordinate)
        let middle = run.startDate.addingTimeInterval(end.timeIntervalSince(run.startDate) / 2)
        let isCurrent = now.timeIntervalSince(end) < RunWeather.currentWindow
        do {
            let weather: RunWeather?
            if isCurrent {
                let current = try await WeatherService.shared.weather(for: place, including: .current)
                weather = RunWeather(current)
            } else {
                let (from, to) = hourWindow(around: middle)
                let hours = try await WeatherService.shared.weather(for: place, including: .hourly(startDate: from, endDate: to))
                weather = nearest(Array(hours), to: middle, date: \.date).map(RunWeather.init)
            }
            // The run may have been deleted while Apple Weather answered.
            guard let weather, !run.isDeleted else {
                Trace.log(.data, "Weather not found", ["kind": isCurrent ? "current" : "hourly"])
                return
            }
            run.saveWeather(weather)
            context.saveQuietly()
            Trace.log(.data, "Weather saved", ["kind": isCurrent ? "current" : "hourly"])
        } catch {
            // No connection, or the app isn't set up for WeatherKit: the next launch tries again.
            Trace.log(.error, "Weather failed", ["kind": isCurrent ? "current" : "hourly", "error": String(describing: type(of: error))])
        }
    }

    /// The hours to ask for: the hour the run's middle falls in and the one after, so the nearest hour start
    /// is always among them.
    nonisolated static func hourWindow(around date: Date, calendar: Calendar = .current) -> (Date, Date) {
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return (hour, hour.addingTimeInterval(2 * 3_600))
    }

    /// The item whose date is nearest `date`, or nil when there are none.
    nonisolated static func nearest<T>(_ items: [T], to date: Date, date key: (T) -> Date) -> T? {
        items.min { abs(key($0).timeIntervalSince(date)) < abs(key($1).timeIntervalSince(date)) }
    }
}

// MARK: - From WeatherKit

extension RunWeather {
    init(_ current: CurrentWeather) {
        self.init(
            temperature: current.temperature.converted(to: .celsius).value,
            feelsLike: current.apparentTemperature.converted(to: .celsius).value,
            humidity: current.humidity,
            cloudCover: current.cloudCover,
            windSpeed: current.wind.speed.converted(to: .metersPerSecond).value,
            windGust: current.wind.gust?.converted(to: .metersPerSecond).value,
            windFrom: current.wind.direction.converted(to: .degrees).value,
            symbolName: current.symbolName,
            condition: current.condition.description,
            isDaylight: current.isDaylight,
            date: current.date,
            isCurrent: true
        )
    }

    init(_ hour: HourWeather) {
        self.init(
            temperature: hour.temperature.converted(to: .celsius).value,
            feelsLike: hour.apparentTemperature.converted(to: .celsius).value,
            humidity: hour.humidity,
            cloudCover: hour.cloudCover,
            windSpeed: hour.wind.speed.converted(to: .metersPerSecond).value,
            windGust: hour.wind.gust?.converted(to: .metersPerSecond).value,
            windFrom: hour.wind.direction.converted(to: .degrees).value,
            symbolName: hour.symbolName,
            condition: hour.condition.description,
            isDaylight: hour.isDaylight,
            date: hour.date,
            isCurrent: false
        )
    }
}
