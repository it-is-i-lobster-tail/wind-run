//
//  GoalTimeWheels.swift
//  Wind Run
//

import SwiftUI

/// A Speed Work goal time on wheels: whole minutes inside the distance's limits, with an hours wheel only where the
/// limits reach an hour. A goal outside them shows at the nearest end, and the setup stores what it shows when the
/// runner moves on (`CoachIntakeModel.settleGoalTime`).
struct GoalTimeWheels: View {
    @Binding var seconds: Double?
    let distance: RaceDistance

    private var range: ClosedRange<Int> { distance.speedWorkMinutes }

    /// The goal in whole minutes, inside the range.
    private var total: Int {
        Int(distance.speedWorkTarget(seconds ?? Double(range.lowerBound * 60))) / 60
    }

    private var showsHours: Bool { range.upperBound >= 60 }

    /// The minutes this hour allows, so the wheels can't pass either end of the range.
    private func minutes(in hour: Int) -> ClosedRange<Int> {
        max(0, range.lowerBound - hour * 60) ... min(59, range.upperBound - hour * 60)
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsHours {
                wheel(range.lowerBound / 60 ... range.upperBound / 60, value: total / 60, label: "h", name: "Hours") { hour in
                    let allowed = minutes(in: hour)
                    set(hour * 60 + min(max(total % 60, allowed.lowerBound), allowed.upperBound))
                }
                wheel(minutes(in: total / 60), value: total % 60, label: "min", name: "Minutes") { set(total / 60 * 60 + $0) }
                    // A new minutes list for each hour, so the wheel doesn't keep the old hour's rows.
                    .id(total / 60)
            } else {
                wheel(range, value: total, label: "min", name: "Minutes") { set($0) }
            }
        }
        .frame(height: 140)
    }

    private func set(_ minutes: Int) {
        seconds = Double(min(max(minutes, range.lowerBound), range.upperBound) * 60)
    }

    private func wheel(_ values: ClosedRange<Int>, value: Int, label: String, name: String, set: @escaping (Int) -> Void) -> some View {
        Picker(name, selection: Binding(get: { value }, set: set)) {
            ForEach(values, id: \.self) { number in
                Text(label == "h" ? "\(number) \(label)" : String(format: "%02d \(label)", number)).tag(number)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
