//
//  LifeHappensView.swift
//  Wind Run
//

import SwiftUI

/// Life happens (AD-11): busy weeks, travel, a holiday or a big change. The plan bends around it
/// and nothing is made up afterwards. Sick asks the illness question; injured opens Report injury.
struct LifeHappensView: View {
    @Environment(\.dismiss) private var dismiss

    let actions: CoachActions
    let reportInjury: () -> Void

    @State private var kind: LifeEventKind?
    @State private var length: LifeEventLength?
    @State private var timeZones = 0
    @State private var eastward = true
    @State private var longHaulFlight = false

    init(kind: LifeEventKind?, actions: CoachActions, reportInjury: @escaping () -> Void) {
        self.actions = actions
        self.reportInjury = reportInjury
        _kind = State(initialValue: kind)
    }

    private var current: [LifeEvent] {
        guard let state = actions.state() else { return [] }
        return state.lifeEvents.filter { $0.isActive(on: .now, calendar: .current) }
    }

    private var asksLength: Bool {
        switch kind {
        case .busy, .travelling, .holiday, .bigLifeChange: true
        case .sick, .injured, nil: false
        }
    }

    private var canSave: Bool {
        guard let kind else { return false }
        return kind == .sick || kind == .injured || length != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if !current.isEmpty {
                    Section("Going on now") {
                        ForEach(current) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.kind.name)
                                    Text("Since \(event.start.formatted(.dateTime.month().day()))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Back to normal") { end(event) }
                                    .buttonStyle(.glass)
                            }
                        }
                    }
                }

                Section("What's going on?") {
                    ChoiceRows(choices: LifeEventKind.allCases, selection: $kind, title: \.name)
                }

                if asksLength {
                    Section("For about how long?") {
                        ChoiceRows(choices: LifeEventLength.allCases, selection: $length, title: \.name)
                    }
                }

                if kind == .travelling {
                    Section {
                        Stepper(value: $timeZones, in: 0...12) {
                            LabeledContent("Time zones", value: timeZones == 0 ? "None" : "\(timeZones)")
                        }
                        if timeZones > 0 {
                            Picker("Direction", selection: $eastward) {
                                Text("East").tag(true)
                                Text("West").tag(false)
                            }
                        }
                        Toggle("A flight over 6 hours", isOn: $longHaulFlight)
                    } footer: {
                        Text("Long flights and new time zones make the first days easier.")
                    }
                }

                if kind == .injured {
                    Section {
                        EmptyView()
                    } footer: {
                        Text("Next you'll say how bad it is, so the plan can change to fit.")
                    }
                } else if kind == .sick {
                    Section {
                        EmptyView()
                    } footer: {
                        Text("The coach will ask whether it's a head cold or more, and holds the plan until you're well.")
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Nothing is made up afterwards. Missed runs stay missed, and the plan picks up from where you are.")
                }
            }
            .navigationTitle("Life happens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(kind == .injured ? "Next" : "Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let kind else { return }
        if kind == .injured {
            dismiss()
            reportInjury()
            return
        }
        var event = LifeEvent(kind: kind, start: .now, length: asksLength ? length : nil)
        if kind == .travelling {
            event.timeZones = timeZones
            event.eastward = timeZones > 0 ? eastward : nil
            event.longHaulFlight = longHaulFlight
        }
        actions.perform { state, runs, now, calendar in
            CoachEngine.addLifeEvent(event, state: state, runs: runs, now: now, calendar: calendar)
        }
        dismiss()
    }

    private func end(_ event: LifeEvent) {
        actions.perform { state, runs, now, calendar in
            CoachEngine.endLifeEvent(id: event.id, state: state, runs: runs, now: now, calendar: calendar)
        }
    }
}
