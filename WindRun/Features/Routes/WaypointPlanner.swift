import SwiftUI

struct WaypointPlanner: View {
    @Binding var plan: WaypointWorkout
    @State private var editing: WorkoutWaypoint?
    @State private var preview = false

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Start at your current location", systemImage: "location.fill").font(.headline)
                    WaypointMap(workout: plan, start: nil)
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
                                effortMenu($plan.returnEffort)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(.background, in: .rect(cornerRadius: 14))
                    Toggle("Return to starting point", isOn: $plan.returnsToStart)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Route workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Menu("Route examples", systemImage: "map") {
                    ForEach(examples) { example in
                        Button(example.name) {
                            plan.points = example.points
                            plan.returnsToStart = example.returnsToStart
                            plan.returnEffort = example.returnEffort
                        }
                    }
                }
                Button("Preview") { preview = true }.disabled(plan.points.isEmpty)
            }
        }
        .sheet(item: $editing) { point in
            let canRemove = plan.points.contains { $0.id == point.id }
            WaypointEditor(waypoint: point, remove: canRemove ? {
                plan.points.removeAll { $0.id == point.id }
            } : nil) { saved in
                if let offset = plan.points.firstIndex(where: { $0.id == saved.id }) {
                    plan.points[offset] = saved
                } else { plan.points.append(saved) }
            }
        }
        .fullScreenCover(isPresented: $preview) { WaypointSession(workout: plan) }
    }

    private var examples: [WaypointWorkout] {
        if let data = UserDefaults.standard.data(forKey: "waypointWorkouts.v1"),
           let routes = try? JSONDecoder().decode([WaypointWorkout].self, from: data), !routes.isEmpty { return routes }
        return [.pool, .outAndBack]
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
                        Text("From " + (offset == 0 ? "your starting location" : plan.points[offset - 1].name))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(point.name).font(.subheadline.weight(.semibold))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Edit waypoint", systemImage: "pencil") { editing = point }
                if offset > 0 {
                    Button("Move earlier", systemImage: "arrow.up") { plan.points.swapAt(offset, offset - 1) }
                }
                if offset + 1 < plan.points.count {
                    Button("Move later", systemImage: "arrow.down") { plan.points.swapAt(offset, offset + 1) }
                }
                Button("Remove waypoint", systemImage: "trash", role: .destructive) {
                    plan.points.removeAll { $0.id == point.id }
                }
            }
            effortMenu($plan.points[offset].effort)
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
