//
//  WorkoutMainPage.swift
//  Wind Run
//

import SwiftUI

/// The main part: a time, a distance, a free run, or intervals. Each change goes straight into the workout.
struct WorkoutMainPage: View {
    let sport: WorkoutSport
    let hasCooldown: Bool
    let unit: DistanceUnit
    let apply: (WorkoutMain) -> Void

    @State private var type: WorkoutType
    // Each type keeps what was set on it, so trying another type and coming back loses nothing.
    @State private var end = WaypointEnd.startingPoint
    @State private var time: IntervalGoal?
    @State private var timeEnding = WorkoutEnding.time
    @State private var distance: IntervalGoal?
    @State private var distanceEnding = WorkoutEnding.distance
    // All time or all distance, with what was typed for each kept.
    @State private var intervals: IntervalSetEntry
    @State private var repeats: Int

    init(main: WorkoutMain, hasCooldown: Bool, unit: DistanceUnit, sport: WorkoutSport = .running, apply: @escaping (WorkoutMain) -> Void) {
        self.hasCooldown = hasCooldown
        self.sport = sport
        self.unit = unit
        self.apply = apply
        _type = State(initialValue: main.type)
        var time = IntervalGoal.time(30 * 60)
        var distance = IntervalGoal.distance(meters: Self.defaultDistanceMeters(unit))
        var intervals = WorkoutMain.Intervals.starter
        switch main {
        case .time(let seconds): time = .time(seconds)
        case .distance(let meters): distance = .distance(meters: meters)
        case .waypoint(let end): _end = State(initialValue: end)
        case .free: break
        case .intervals(let set): intervals = set
        }
        _time = State(initialValue: time)
        _distance = State(initialValue: distance)
        _intervals = State(initialValue: IntervalSetEntry(intervals, unit: unit))
        _repeats = State(initialValue: intervals.repeats)
    }

    /// What a distance run starts at in each unit: 3 mi or 5 km.
    static func defaultDistanceMeters(_ unit: DistanceUnit) -> Double {
        unit == .miles ? 3 * DistanceUnit.miles.meters : 5_000
    }

    /// The main part as set, or nil while a number is missing.
    private var main: WorkoutMain? {
        switch type {
        case .time:
            if case .time(let seconds) = time { return .time(seconds) }
            return nil
        case .distance:
            if case .distance(let meters) = distance { return .distance(meters: meters) }
            return nil
        case .waypoint: return .waypoint(end)
        case .free:
            return .free
        case .intervals:
            return intervals.intervals(repeats: repeats).map { .intervals($0) }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Main workout", selection: $type.traced("Main workout", "Type") { $0.rawValue }) {
                    Text("Distance").tag(WorkoutType.distance)
                    Text("Free").tag(WorkoutType.free)
                    Text("Intervals").tag(WorkoutType.intervals)
                    Text("Time").tag(WorkoutType.time)
                    Text("Waypoint").tag(WorkoutType.waypoint)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                WorkoutSheetQuestion(text: "What's the main part?")
            }

            switch type {
            case .time:
                WorkoutEndFields(goal: $time, ending: $timeEnding, unit: unit, endings: [.time], defaultSeconds: 30 * 60, trace: "Main time") { _ in
                    hasCooldown ? "Continue for this long, then the cooldown starts." : "You'll hear when you reach this. Keep going after it if you like."
                }
            case .distance:
                WorkoutEndFields(goal: $distance, ending: $distanceEnding, unit: unit, endings: [.distance], defaultMeters: { Self.defaultDistanceMeters($0) }, trace: "Main distance") { _ in
                    hasCooldown ? "Cover this distance, then the cooldown starts." : "You'll hear when you reach this. Keep going after it if you like."
                }
            case .waypoint:
                Section("End waypoint") { WaypointEndField(end: $end) }
            case .free:
                Section {
                    Label(sport == .cycling ? "Ride as long as you like." : "Run as long as you like.", systemImage: sport.systemImage)
                } footer: {
                    Text(hasCooldown
                        ? "Tap Next on the run screen, your Lock Screen or your Apple Watch to start the cooldown."
                        : "Finish the workout when you're done.")
                }
            case .intervals:
                Section {
                    Stepper(value: $repeats.traced("Main workout", "Repeats"), in: IntervalBlock.repeatRange) {
                        Text(repeats == 1 ? "Repeat once" : "Repeat \(repeats) times")
                            .monospacedDigit()
                    }
                }
                Section {
                    Picker("Intervals by", selection: $intervals.kind.traced("Main workout", "Intervals by") { $0.rawValue }) {
                        Text("Time").tag(IntervalSetEntry.Kind.time)
                        Text("Distance").tag(IntervalSetEntry.Kind.distance)
                        Text("Waypoint").tag(IntervalSetEntry.Kind.waypoint)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    switch intervals.kind {
                    case .waypoint:
                        Text("Work").font(.headline)
                        WaypointEndField(end: $intervals.workEnd)
                        Text("Recovery").font(.headline)
                        WaypointEndField(end: $intervals.recoveryEnd)
                    case .time:
                        IntervalAmountRow(title: "Work", text: $intervals.workTime, kind: .time)
                        IntervalAmountRow(title: "Recovery", text: $intervals.recoveryTime, kind: .time)
                    case .distance:
                        IntervalAmountRow(title: "Work", text: $intervals.workDistance, kind: .distance)
                        IntervalAmountRow(title: "Recovery", text: $intervals.recoveryDistance, kind: .distance)
                    }
                } header: {
                    HStack {
                        Spacer()
                        switch intervals.kind {
                        case .waypoint: EmptyView()
                        case .time:
                            Text("min : sec")
                        case .distance:
                            Text(unit.name)
                        }
                    }
                    .font(.footnote)
                    .textCase(nil)
                } footer: {
                    if let total = intervals.total(repeats: repeats) {
                        Text("\(total) total")
                    }
                }
            }
        }
        .navigationTitle("Main workout")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Main workout")
        // While a box is empty the workout keeps its last main part.
        .onChange(of: main) { _, main in
            if let main { apply(main) }
        }
    }
}

/// "Work" or "Recovery" with a filled box on the right to type the amount in.
private struct IntervalAmountRow: View {
    let title: String
    @Binding var text: String
    let kind: IntervalSetEntry.Kind

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(kind == .time ? "0:00" : "0", text: $text)
                .keyboardType(kind == .time ? .numbersAndPunctuation : .decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 88)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                .accessibilityLabel(title)
        }
    }
}
