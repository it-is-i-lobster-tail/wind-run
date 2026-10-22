//
//  RaceAnswerViews.swift
//  Wind Run
//

import SwiftUI

/// "Yes, recorded elsewhere" (EV-9): the race's distance and time, both optional.
struct RaceRecordedElsewhereView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let actions: CoachActions

    @State private var distance: Double?
    @State private var seconds: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    OptionalNumberField(title: "Distance (\(unit.symbol))", value: $distance)
                    OptionalDuration(title: "I know my time", seconds: $seconds, showsHours: true)
                } footer: {
                    Text("Both are optional. With a time, your paces update from the race.")
                }
            }
            .navigationTitle("Your race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear {
                if distance == nil, let race = actions.state()?.goal.distance {
                    distance = race.meters / unit.meters
                }
            }
        }
    }

    private func save() {
        let meters = distance.map { $0 * unit.meters }
        _ = actions.answer(.didYouRace(.recordedElsewhere(meters: meters, seconds: seconds)))
        dismiss()
    }
}

/// "Race moved" (RC-10): the new date, today or later.
struct RaceMovedView: View {
    @Environment(\.dismiss) private var dismiss

    let actions: CoachActions

    @State private var date = Calendar.current.date(byAdding: .weekOfYear, value: 4, to: .now) ?? .now

    private var range: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        return today...(Calendar.current.date(byAdding: .weekOfYear, value: 52, to: today) ?? today)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("New race day", selection: $date, in: range, displayedComponents: .date)
                } footer: {
                    Text("The coach checks your goal again for the new date and moves your plan to fit.")
                }
            }
            .navigationTitle("Race moved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = actions.answer(.didYouRace(.raceMoved(to: date)))
                        dismiss()
                    }
                }
            }
        }
    }
}

/// A new goal after this one (BD-1g, SW-7c, EV-9), from the same goal screen as setup. The coach
/// checks it again before switching.
struct NewGoalView: View {
    @Environment(\.dismiss) private var dismiss

    let actions: CoachActions
    @State private var model: CoachIntakeModel

    init(flavor: CoachGoal, distance: RaceDistance?, actions: CoachActions) {
        self.actions = actions
        let model = CoachIntakeModel(flavor: flavor, unit: .current)
        if let distance, flavor.distances.contains(distance) {
            model.intake.goal.distance = distance
        }
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                IntakeStepView(model: model, step: .goal)
            }
            .navigationTitle("Your next goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Switch") {
                        model.settleGoalTime()
                        _ = actions.answer(.nextGoal(.newGoal(model.intake.goal)))
                        dismiss()
                    }
                    .disabled(!model.goalIsComplete)
                }
            }
        }
    }
}
