//
//  SunTimes.swift
//  Wind Run
//

import Foundation

/// Sunrise and sunset worked out on the device from where the run started, with no network. Used only for
/// the run screen's "Daylight left": the place is never kept, logged or exported.
enum SunTimes {
    /// The next sunrise or sunset.
    struct Event: Equatable {
        var isSunset: Bool
        var date: Date
    }

    /// The first sunrise or sunset after `date` at the place, or nil when there's none in the next two days,
    /// as in a polar summer or winter.
    static func next(after date: Date, latitude: Double, longitude: Double) -> Event? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let today = utc.startOfDay(for: date)
        var events: [Event] = []
        for offset in -1...2 {
            guard let day = utc.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayOfYear = utc.ordinality(of: .day, in: .year, for: day) ?? 1
            if let hours = hoursUTC(dayOfYear: dayOfYear, latitude: latitude, longitude: longitude, rising: true) {
                events.append(Event(isSunset: false, date: day.addingTimeInterval(hours * 3600)))
            }
            if let hours = hoursUTC(dayOfYear: dayOfYear, latitude: latitude, longitude: longitude, rising: false) {
                events.append(Event(isSunset: true, date: day.addingTimeInterval(hours * 3600)))
            }
        }
        return events.filter { $0.date > date }.min { $0.date < $1.date }
    }

    /// Hours after midnight UTC of the sun rising or setting on that day of the year, by the US Naval
    /// Observatory's almanac method, good to a minute or two. Nil when the sun doesn't rise or set that day.
    static func hoursUTC(dayOfYear: Int, latitude: Double, longitude: Double, rising: Bool) -> Double? {
        let zenith = 90.833
        let radians = Double.pi / 180
        let longitudeHour = longitude / 15
        let t = Double(dayOfYear) + ((rising ? 6 : 18) - longitudeHour) / 24
        let meanAnomaly = 0.9856 * t - 3.289
        let trueLongitude = normalized(meanAnomaly + 1.916 * sin(meanAnomaly * radians) + 0.020 * sin(2 * meanAnomaly * radians) + 282.634, 360)
        var rightAscension = normalized(atan(0.91764 * tan(trueLongitude * radians)) / radians, 360)
        rightAscension += (floor(trueLongitude / 90) - floor(rightAscension / 90)) * 90
        rightAscension /= 15
        let sinDeclination = 0.39782 * sin(trueLongitude * radians)
        let cosDeclination = cos(asin(sinDeclination))
        let cosHour = (cos(zenith * radians) - sinDeclination * sin(latitude * radians)) / (cosDeclination * cos(latitude * radians))
        guard cosHour >= -1, cosHour <= 1 else { return nil }
        let hourAngle = (rising ? 360 - acos(cosHour) / radians : acos(cosHour) / radians) / 15
        let localTime = hourAngle + rightAscension - 0.06571 * t - 6.622
        return normalized(localTime - longitudeHour, 24)
    }

    private static func normalized(_ value: Double, _ range: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: range)
        return result < 0 ? result + range : result
    }
}
