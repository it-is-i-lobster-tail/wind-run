import MapKit
import SwiftUI

struct WaypointBadge: View {
    let number: Int?
    var tint = Color.accentColor

    var body: some View {
        Group {
            if let number { Text("\(number)").font(.caption.bold().monospacedDigit()) }
            else { Image(systemName: "flag.fill").font(.caption2.bold()) }
        }
        .foregroundStyle(.white)
        .frame(width: 25, height: 25)
        .background(tint, in: .circle)
        .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
        .accessibilityHidden(true)
    }
}

struct WaypointMap: View {
    let workout: WaypointWorkout
    let start: RoutePoint?
    var progress: WaypointProgress?
    var route: MKRoute?

    private var coordinates: [CLLocationCoordinate2D] {
        let origin = start.map { [$0.coordinate] } ?? []
        return origin + workout.points.map(\.point.coordinate) + (workout.returnsToStart ? origin : [])
    }

    private var region: MKCoordinateRegion {
        let points = (coordinates.isEmpty ? [workout.previewStart.coordinate] : coordinates).map(MKMapPoint.init)
        let bounds = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: $1, size: .init(width: 1, height: 1))) }
        let center = MKMapPoint(x: bounds.midX, y: bounds.midY)
        return MKCoordinateRegion(center: center.coordinate,
                                  latitudinalMeters: max(350, bounds.height * MKMetersPerMapPointAtLatitude(center.coordinate.latitude) * 1.6),
                                  longitudinalMeters: max(450, bounds.width * MKMetersPerMapPointAtLatitude(center.coordinate.latitude) * 1.3))
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: [.pan, .zoom]) {
            MapPolyline(coordinates: coordinates)
                .stroke(.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [3, 6]))
            if let route { MapPolyline(route.polyline).stroke(.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round)) }
            if let position = progress?.position, let target = progress?.target, route == nil {
                MapPolyline(coordinates: [position.coordinate, target.coordinate])
                    .stroke(.accent, style: StrokeStyle(lineWidth: 4, dash: [7, 4]))
            }
            if let start { Annotation("Start", coordinate: start.coordinate) {
                WaypointBadge(number: nil, tint: .black)
            }.annotationTitles(.hidden) }
            ForEach(Array(workout.points.enumerated()), id: \.element.id) { index, waypoint in
                Annotation(waypoint.name, coordinate: waypoint.point.coordinate) {
                    WaypointBadge(number: index + 1, tint: progress?.leg == index ? .black : .accentColor)
                }.annotationTitles(.hidden)
            }
            if let position = progress?.position {
                Annotation("Current position", coordinate: position.coordinate) {
                    Circle().fill(.blue).frame(width: 15, height: 15)
                        .overlay { Circle().stroke(.white, lineWidth: 3) }
                        .shadow(radius: 2)
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapScaleView() }
        .clipShape(.rect(cornerRadius: 18))
    }
}

/// Pan the map beneath the pin or tap a specific position. Changes commit only on Save.
struct WaypointEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var waypoint: WorkoutWaypoint
    var showsEffort = true
    let remove: (() -> Void)?
    let save: (WorkoutWaypoint) -> Void
    @State private var camera: MapCameraPosition
    @State private var query = ""
    @State private var searchMessage: String?
    @State private var searchTask: Task<Void, Never>?

    init(waypoint: WorkoutWaypoint, showsEffort: Bool = true, remove: (() -> Void)?, save: @escaping (WorkoutWaypoint) -> Void) {
        _waypoint = State(initialValue: waypoint)
        self.showsEffort = showsEffort
        self.remove = remove
        self.save = save
        _camera = State(initialValue: .region(MKCoordinateRegion(center: waypoint.point.coordinate, latitudinalMeters: 800, longitudinalMeters: 800)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Place or address", text: $query)
                        .submitLabel(.search).onSubmit { search() }
                    if let searchMessage { Text(searchMessage).font(.footnote).foregroundStyle(.secondary) }
                    MapReader { proxy in
                        Map(position: $camera, interactionModes: [.pan, .zoom])
                            .onMapCameraChange { update($0.region.center) }
                            .onTapGesture { position in
                                if let coordinate = proxy.convert(position, from: .local) { center(on: coordinate) }
                            }
                            .overlay {
                                Image(systemName: "plus.circle.fill").font(.title2)
                                    .foregroundStyle(.white, Color.accentColor).allowsHitTesting(false)
                            }
                    }
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Move the map under the pin, tap a spot, or search for a place.")
                }
                Section {
                    TextField("Waypoint name", text: $waypoint.name)
                    if showsEffort {
                        Picker("Effort to here", selection: $waypoint.effort) {
                            ForEach(IntervalStepKind.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                    }
                }
                if let remove {
                    Button("Remove waypoint", systemImage: "trash", role: .destructive) {
                        remove()
                        dismiss()
                    }
                }
            }
            .navigationTitle(remove == nil ? "Add waypoint" : "Edit waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(waypoint); dismiss() }
                        .disabled(waypoint.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func update(_ coordinate: CLLocationCoordinate2D) {
        waypoint.point = .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func center(on coordinate: CLLocationCoordinate2D) {
        update(coordinate)
        camera = .region(.init(center: coordinate, latitudinalMeters: 650, longitudinalMeters: 650))
    }

    private func search() {
        searchTask?.cancel()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = .init(center: waypoint.point.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000)
        searchMessage = "Searching…"
        searchTask = Task {
            let result = try? await MKLocalSearch(request: request).start().mapItems.first
            guard !Task.isCancelled else { return }
            if let result {
                center(on: result.location.coordinate)
                waypoint.name = result.name ?? query
                searchMessage = nil
            } else { searchMessage = "No place found. Try another name or move the pin." }
        }
    }
}

struct ActiveWaypointLeg: View {
    let progress: WaypointProgress
    @State private var path: MKRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if progress.finished {
                Label("Route complete", systemImage: "flag.checkered")
            } else {
                Text("\(progress.effort.name) to \(progress.destination)").font(.headline)
                if let start = progress.start {
                    WaypointMap(workout: progress.workout, start: start, progress: progress, route: path)
                        .frame(height: 160)
                }
            }
        }
        .task(id: progress.target) {
            path = nil
            guard let target = progress.target, let origin = progress.position else { return }
            let request = MKDirections.Request()
            request.source = MKMapItem(location: origin.location, address: nil)
            request.destination = MKMapItem(location: target.location, address: nil)
            request.transportType = progress.workout.activity == .ride ? .cycling : .walking
            let result = try? await MKDirections(request: request).calculate().routes.first
            if !Task.isCancelled { path = result }
        }
    }
}

struct WaypointEndField: View {
    @Binding var end: WaypointEnd
    @State private var editing: WorkoutWaypoint?

    var body: some View {
        Button {
            editing = WorkoutWaypoint(name: end.point == nil ? "Waypoint" : end.name,
                                      point: end.point ?? .poolStart, effort: .work)
        } label: {
            Label(end.point == nil ? "Choose on Map" : end.name, systemImage: "mappin.and.ellipse")
        }
        Button {
            end = .startingPoint
        } label: {
            HStack {
                Label("Starting point", systemImage: "flag")
                Spacer()
                if end.point == nil { Image(systemName: "checkmark") }
            }
        }
        .sheet(item: $editing) { point in
            WaypointEditor(waypoint: point, showsEffort: false, remove: nil) {
                end = WaypointEnd(name: $0.name, point: $0.point)
            }
        }
    }
}
