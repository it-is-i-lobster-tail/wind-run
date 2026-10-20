//
//  WeeklyCheckInView.swift
//  Wind Run
//

import SwiftUI

/// The weekly check-in (AD-3), at the end of each plan week. About 30 seconds.
struct WeeklyCheckInView: View {
    @Environment(\.dismiss) private var dismiss

    let weekIndex: Int
    let actions: CoachActions
    let openLifeHappens: (LifeEventKind) -> Void

    @State private var checkIn = WeeklyCheckIn(answeredAt: .now)

    var body: some View {
        NavigationStack {
            Form {
                Section("The week") {
                    ChoiceRows(choices: WeekFeel.allCases, selection: $checkIn.week, title: \.name)
                }

                Section {
                    trend("Legs", selection: $checkIn.legs)
                    trend("Energy", selection: $checkIn.energy)
                    trend("Life stress", selection: $checkIn.lifeStress)
                    trend("Motivation", selection: $checkIn.motivation)
                } header: {
                    Text("Compared with normal")
                }

                Section {
                    Picker("Ill this week", selection: $checkIn.ill) {
                        Text("Skip").tag(Bool?.none)
                        Text("No").tag(Bool?.some(false))
                        Text("Yes").tag(Bool?.some(true))
                    }
                    Picker("Other training", selection: $checkIn.otherTraining) {
                        Text("Skip").tag(OtherTrainingChange?.none)
                        ForEach(OtherTrainingChange.allCases, id: \.self) { Text($0.name).tag(OtherTrainingChange?.some($0)) }
                    }
                    Picker("Travel this week or next", selection: $checkIn.travel) {
                        Text("Skip").tag(Bool?.none)
                        Text("No").tag(Bool?.some(false))
                        Text("Yes").tag(Bool?.some(true))
                    }
                }

                if checkIn.otherTraining == .more || checkIn.otherTraining == .new {
                    OtherSessionsSection(sessions: $checkIn.otherSessions)
                }
            }
            .navigationTitle("How was your week?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    private func trend(_ title: String, selection: Binding<WeeklyTrend?>) -> some View {
        Picker(title, selection: selection) {
            Text("Skip").tag(WeeklyTrend?.none)
            ForEach(WeeklyTrend.allCases, id: \.self) { Text($0.name).tag(WeeklyTrend?.some($0)) }
        }
    }

    private func save() {
        checkIn.answeredAt = .now
        let checkIn = checkIn
        actions.perform { state, runs, now, calendar in
            CoachEngine.submitWeeklyCheckIn(checkIn, week: weekIndex, state: state, runs: runs, now: now, calendar: calendar)
        }
        // A yes to travel goes on to Life happens, so the coach knows the trip.
        if checkIn.travel == true {
            openLifeHappens(.travelling)
        } else {
            dismiss()
        }
    }
}

/// The follow-up for more or new training: what it was, this week (RB-6).
private struct OtherSessionsSection: View {
    @Binding var sessions: [OtherSession]

    var body: some View {
        Section {
            ForEach($sessions) { $session in
                VStack(alignment: .leading) {
                    Picker("Activity", selection: $session.kind) {
                        ForEach(ActivityKind.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    Stepper("\(Int(session.minutes)) min", value: $session.minutes, in: 10...240, step: 5)
                    Stepper("Effort \(session.effort) out of 10", value: $session.effort, in: 0...10)
                    Toggle("Worked the legs", isOn: $session.worksLegs)
                }
            }
            .onDelete { sessions.remove(atOffsets: $0) }
            Button("Add a session", systemImage: "plus") {
                sessions.append(OtherSession(date: .now, kind: .legStrength, minutes: 45, effort: 6, worksLegs: true))
            }
        } header: {
            Text("What did you add this week?")
        }
    }
}

extension OtherTrainingChange {
    var name: String {
        switch self {
        case .same: "Same"
        case .more: "More"
        case .new: "Something new"
        case .less: "Less"
        }
    }
}
