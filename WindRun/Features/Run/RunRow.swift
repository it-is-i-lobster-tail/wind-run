//
//  RunRow.swift
//  Wind Run
//

import SwiftData
import SwiftUI

struct RunRow: View {
    let run: Run
    let unit: DistanceUnit

    var body: some View {
        let active = run.activeDuration()
        let pace = run.pace()
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.when(run.startDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(RunFormat.distance(run.distanceMeters, unit: unit))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(RunFormat.duration(active))
                    .font(.body.monospacedDigit())
                Text(RunFormat.pace(pace, unit: unit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .windRunGlassCard(interactive: true)
        // Read as words: "32:10" could be a time of day, and "/km" a fraction.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(date: run.startDate, meters: run.distanceMeters, seconds: active, pace: pace, unit: unit))
    }

    /// "Today, 7:04 AM", "Tuesday, 7:04 AM" within the week, then "Tue, Oct 12, 7:04 AM", with the year
    /// when it isn't this one.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.wholeDays(from: date, to: now)
        let day = if days >= 0, days < 7 {
            RunFormat.day(date, now: now, calendar: calendar)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        } else {
            date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        }
        return "\(day), \(date.formatted(.dateTime.hour().minute()))"
    }

    /// "Tuesday, 7:04 AM. 5.02 kilometers in 32 minutes 10 seconds, 6 minutes 24 seconds per kilometer."
    static func spoken(date: Date, meters: Double, seconds: TimeInterval, pace: TimeInterval?, unit: DistanceUnit) -> String {
        let distance = "\(RunFormat.distance(meters, unit: unit, withUnit: false)) \(unit.pluralName)"
        var text = "\(when(date)). \(distance) in \(SpokenFormat.duration(seconds))"
        if let pace = SpokenFormat.pace(pace, unit: unit) {
            text += ", \(pace)"
        }
        return text + "."
    }
}
