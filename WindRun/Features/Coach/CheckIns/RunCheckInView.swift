//
//  RunCheckInView.swift
//  Wind Run
//

import SwiftUI

/// The after-run check-in (AD-1): how hard it was, and anything worth knowing about the run.
/// Every answer can be skipped; a skipped answer stays empty rather than being guessed.
struct RunCheckInView: View {
    @Environment(\.dismiss) private var dismiss

    let run: Run
    let actions: CoachActions?
    /// Opens Report injury for this run.
    let reportInjury: () -> Void

    @State private var checkIn = RunCheckIn()
    @State private var review: RunReview?

    private var state: CoachState? { actions?.state() }

    /// The anchor words show during the first two weeks of a plan (PZ-1).
    private var showsAnchors: Bool {
        guard let state else { return true }
        return state.weekIndex(on: run.startDate, calendar: .current) < 2
    }

    /// The planned session the run did, if any.
    private var session: PlannedSession? {
        guard let state, let id = run.coachWorkout?.sessionID else { return nil }
        return state.weeks.lazy.flatMap(\.plan.sessions).first { $0.id == id }
    }

    private var isEasyRun: Bool {
        session.map { $0.effort == .easy } ?? true
    }

    /// Event-prep runs over an hour ask about fuel (EV-5).
    private var asksFuel: Bool {
        state?.goal.flavor == .event && run.activeDuration() > 60 * 60
    }

    var body: some View {
        NavigationStack {
            Form {
                if let review {
                    RunReviewSection(review: review)
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Effort")
                            Spacer()
                            Text(checkIn.rpe.map { "\($0) out of 10" } ?? "Slide to rate")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(checkIn.rpe ?? 3) },
                            set: { checkIn.rpe = Int($0.rounded()) }
                        ), in: 0...10, step: 1)
                        .accessibilityLabel("Effort")
                        .accessibilityValue(checkIn.rpe.map { "\($0) out of 10" } ?? "Not rated")
                        if showsAnchors, let rpe = checkIn.rpe {
                            Text(Self.anchor(for: rpe))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("How hard was it?")
                } footer: {
                    Text("0 is resting, 10 is the hardest you could go.")
                }

                if isEasyRun {
                    Section("Could you talk in full sentences?") {
                        Picker("Talk test", selection: $checkIn.talkTest) {
                            Text("Skip").tag(Bool?.none)
                            Text("Yes").tag(Bool?.some(true))
                            Text("No").tag(Bool?.some(false))
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Optional") {
                    Picker("It felt", selection: $checkIn.feel) {
                        Text("Skip").tag(RunFeel?.none)
                        ForEach(RunFeel.allCases, id: \.self) { Text($0.name).tag(RunFeel?.some($0)) }
                    }
                    Picker("Cut short", selection: $checkIn.cutShort) {
                        Text("No").tag(CutShortReason?.none)
                        ForEach(CutShortReason.allCases, id: \.self) { Text($0.name).tag(CutShortReason?.some($0)) }
                    }
                    Toggle("Unplanned, or with friends", isOn: $checkIn.unplannedOrWithFriends)
                    Toggle("I walked parts of it", isOn: $checkIn.runWalk)
                    Toggle("On a treadmill", isOn: $checkIn.treadmill)
                    Toggle("The watch or GPS went wrong", isOn: $checkIn.badData)
                    Toggle("A race or all-out effort", isOn: $checkIn.raceOrAllOut)
                }

                if asksFuel {
                    Section("Fuel") {
                        Stepper("Carbohydrate: \(Int(checkIn.fuelGramsPerHour ?? 0)) g an hour", value: Binding(
                            get: { checkIn.fuelGramsPerHour ?? 0 },
                            set: { checkIn.fuelGramsPerHour = $0 }
                        ), in: 0...120, step: 10)
                        Picker("Stomach", selection: $checkIn.gutScore) {
                            Text("Skip").tag(Int?.none)
                            Text("Fine").tag(Int?.some(0))
                            Text("A little upset").tag(Int?.some(1))
                            Text("Upset").tag(Int?.some(2))
                            Text("Had to stop").tag(Int?.some(3))
                        }
                    }
                }

                Section {
                    Button("Something hurt? Report injury", systemImage: "bandage") {
                        save()
                        reportInjury()
                    }
                }
            }
            .navigationTitle("How was your run?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        // Something hurt goes straight on to Report injury.
                        if checkIn.cutShort == .somethingHurt { reportInjury() } else { dismiss() }
                    }
                }
            }
            .onAppear {
                checkIn = run.checkIn ?? RunCheckIn()
                if let actions, review == nil {
                    review = actions.logRun(run)
                }
            }
        }
    }

    private func save() {
        checkIn.answeredAt = .now
        if let actions {
            review = actions.saveCheckIn(checkIn, for: run) ?? review
        } else {
            run.saveCheckIn(checkIn)
        }
    }

    /// The CR-10 anchor for an effort.
    static func anchor(for rpe: Int) -> String {
        switch rpe {
        case 0: "Resting"
        case 1: "Very, very easy"
        case 2: "Easy"
        case 3: "Moderate: you could chat"
        case 4: "Somewhat hard"
        case 5, 6: "Hard"
        case 7, 8: "Very hard"
        case 9: "Very, very hard"
        default: "The hardest you could go"
        }
    }
}

/// What the coach noticed about the run: insights and milestones (FB, BD-1e).
struct RunReviewSection: View {
    let review: RunReview

    var body: some View {
        if !review.insights.isEmpty || !review.milestones.isEmpty || !review.notes.isEmpty {
            Section("From your coach") {
                ForEach(review.milestones, id: \.self) { milestone in
                    Label(milestone.text, systemImage: "star.fill")
                }
                ForEach(review.insights + review.notes, id: \.self) { note in
                    Text(note.text)
                }
                if review.showsSafetyLine {
                    Text(SafetyText.safetyLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension Milestone {
    var text: String {
        switch self {
        case .nonStopMinutes(let minutes): "\(minutes) minutes without stopping."
        case .firstDistance(let distance): "Your first \(distance.shortName)."
        case .longestRun(let meters): "Your longest run yet: \(CoachFormat.distance(meters, unit: .current))."
        }
    }
}
