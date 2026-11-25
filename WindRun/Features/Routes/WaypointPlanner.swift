import SwiftUI

struct WaypointPlanner: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workouts: [WaypointWorkout]
    @AppStorage("waypointWorkoutSelection") private var selection = ""
    @State private var editing: WorkoutWaypoint?
    @State private var session: RouteSessionMode?
    @State private var renaming = false
    @State private var name = ""

    private static let storageKey = "waypointWorkouts.v1"

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([WaypointWorkout].self, from: $0) }
        _workouts = State(initialValue: saved.flatMap { $0.isEmpty ? nil : $0 } ?? [.pool, .outAndBack])
    }

    private var index: Int { workouts.firstIndex { $0.id.uuidString == selection } ?? 0 }
    private var plan: WaypointWorkout { workouts[index] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    title
                    WaypointMap(workout: plan, start: plan.previewStart)
                        .id(plan.points.map(\.point.coordinateKey))
                        .frame(height: 214)
                    HStack {
                        Text("Workout legs").font(.title3.bold())
                        Spacer()
                        Button("Add waypoint", systemImage: "plus") { addPoint() }
                            .font(.subheadline.weight(.semibold))
                    }
                    VStack(spacing: 0) {
                        if plan.points.isEmpty {
                            ContentUnavailableView("Add your first waypoint", systemImage: "mappin.and.ellipse",
                                description: Text("Choose where the first leg ends."))
                        }
                        ForEach(Array(plan.points.enumerated()), id: \.element.id) { offset, point in
                            legRow(offset: offset, point: point)
                            if offset + 1 < plan.points.count || plan.returnsToStart { Divider().padding(.leading, 46) }
                        }
                        if plan.returnsToStart && !plan.points.isEmpty {
                            HStack {
                                WaypointBadge(number: nil, tint: .black)
                                Text("Starting point").font(.subheadline.weight(.semibold))
                                Spacer()
                                effortMenu($workouts[index].returnEffort)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(.background, in: .rect(cornerRadius: 14))
                    Toggle("Return to starting point", isOn: $workouts[index].returnsToStart)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Route workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(workouts) { workout in
                            Button { selection = workout.id.uuidString } label: {
                                if plan.id == workout.id { Label(workout.name, systemImage: "checkmark") }
                                else { Text(workout.name) }
                            }
                        }
                        Divider()
                        Button("New route", systemImage: "plus") {
                            let workout = WaypointWorkout(name: "Custom route", points: [])
                            workouts.append(workout)
                            selection = workout.id.uuidString
                        }
                        Button("Rename route", systemImage: "pencil") { name = plan.name; renaming = true }
                    } label: { Label("Routes", systemImage: "map") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button { session = .preview } label: {
                        Label("Preview", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { session = .gps } label: {
                        Label("Start with GPS", systemImage: "location.fill").frame(maxWidth: .infinity)
                    }
                    .prominentAccentButton()
                }
                .controlSize(.large).disabled(plan.points.isEmpty)
                .padding(.horizontal).padding(.vertical, 8)
                .background(.bar)
            }
        }
        .alert("Route name", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Save") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { workouts[index].name = trimmed }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: workouts, initial: true) { _, value in
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: Self.storageKey) }
        }
        .sheet(item: $editing) { point in
            let canRemove = plan.points.contains { $0.id == point.id }
            WaypointEditor(waypoint: point, remove: canRemove ? {
                workouts[index].points.removeAll { $0.id == point.id }
            } : nil) { saved in
                if let offset = plan.points.firstIndex(where: { $0.id == saved.id }) {
                    workouts[index].points[offset] = saved
                } else { workouts[index].points.append(saved) }
            }
        }
        .fullScreenCover(item: $session) { mode in WaypointSession(workout: plan, mode: mode) }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.name).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                Menu {
                    Picker("Activity", selection: $workouts[index].activity) {
                        ForEach(RouteActivity.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: plan.activity.symbol)
                        Text(plan.activity.rawValue)
                        Image(systemName: "chevron.down").font(.caption2.bold())
                    }
                }
                Text("·").accessibilityHidden(true)
                Text("\(plan.points.count) \(plan.points.count == 1 ? "waypoint" : "waypoints")")
                if plan.returnsToStart {
                    Image(systemName: "arrow.uturn.backward").accessibilityLabel("Returns to start")
                }
            }.font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }

    private func addPoint() {
        let last = plan.points.last?.point ?? plan.previewStart
        editing = WorkoutWaypoint(name: "Waypoint \(plan.points.count + 1)", point: last, effort: .work)
    }

    private func legRow(offset: Int, point: WorkoutWaypoint) -> some View {
        HStack(spacing: 8) {
            Button { editing = point } label: {
                HStack(spacing: 10) {
                    WaypointBadge(number: offset + 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From " + (offset == 0 ? "start" : plan.points[offset - 1].name))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(point.name).font(.subheadline.weight(.semibold))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Edit waypoint", systemImage: "pencil") { editing = point }
                if offset > 0 {
                    Button("Move earlier", systemImage: "arrow.up") { workouts[index].points.swapAt(offset, offset - 1) }
                }
                if offset + 1 < plan.points.count {
                    Button("Move later", systemImage: "arrow.down") { workouts[index].points.swapAt(offset, offset + 1) }
                }
                Button("Remove waypoint", systemImage: "trash", role: .destructive) {
                    workouts[index].points.removeAll { $0.id == point.id }
                }
            }
            effortMenu($workouts[index].points[offset].effort)
        }
        .padding(.vertical, 8)
    }

    private func effortMenu(_ effort: Binding<IntervalStepKind>) -> some View {
        Menu {
            Picker("Effort to waypoint", selection: effort) {
                ForEach(IntervalStepKind.allCases, id: \.self) { Text($0.name).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(effort.wrappedValue.routeTint).frame(width: 7, height: 7)
                Text(effort.wrappedValue.name)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.primary)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(.quaternary.opacity(0.6), in: .capsule)
        }
    }
}

private extension RoutePoint {
    var coordinateKey: [Double] { [latitude, longitude] }
}
