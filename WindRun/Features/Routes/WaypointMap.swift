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

extension EnvironmentValues {
    @Entry var waypointSlots: [WaypointSlot] = []
    @Entry var waypointOrigin: RoutePoint?
    @Entry var waypointSport: WorkoutSport = .running
}

/// The phase or repeat position identifies a pin even when names or coordinates coincide.
struct WaypointSlot: Identifiable {
    let id: String
    let phaseName: String?
    let value: WorkoutWaypoint
    let placed: Bool
    let save: (WorkoutWaypoint) -> Void
    var remove: (() -> Void)?

    init(phase: String, end: WaypointEnd?, save: @escaping (WaypointEnd) -> Void) {
        id = phase
        phaseName = phase
        placed = end?.point != nil
        value = WorkoutWaypoint(name: end?.name ?? phase, point: end?.point ?? .poolStart, effort: .work)
        self.save = { save(.init(name: $0.name, point: $0.point)) }
    }

    init(leg: WorkoutWaypoint, placed: Bool, save: @escaping (WorkoutWaypoint) -> Void, remove: (() -> Void)?) {
        id = leg.id.uuidString
        phaseName = nil
        value = leg
        self.placed = placed
        self.save = save
        self.remove = remove
    }
}

/// Map edits update the workout draft as each pin changes.
struct WorkoutWaypointPicker: View {
    let slots: [WaypointSlot]
    @State private var selected: String
    @State private var edits: [String: WorkoutWaypoint] = [:]

    init(slots: [WaypointSlot], selected: String) {
        self.slots = slots
        _selected = State(initialValue: selected)
    }

    private func placed(_ slot: WaypointSlot) -> WorkoutWaypoint? {
        edits[slot.id] ?? (slot.placed ? slot.value : nil)
    }

    var body: some View {
        if let index = slots.firstIndex(where: { $0.id == selected }) {
            let slot = slots[index]
            let current = placed(slot)
            let previous = slots[..<index].compactMap(placed).last
            let others = slots.filter { $0.id != selected }.compactMap(placed)
            WaypointEditor(waypoint: current ?? slot.value, showsEffort: slot.phaseName == nil,
                           existingPin: current != nil, phaseName: slot.phaseName, remove: slot.remove,
                           otherPins: others, previous: previous ?? others.last,
                           choices: slots.map { ($0.id, placed($0)?.name ?? $0.value.name) },
                           selected: selected, change: { waypoint in
                edits[slot.id] = waypoint
                slot.save(waypoint)
            }, select: { selected = $0 })
            .environment(\.waypointOrigin, previous?.point)
            .id(selected)
        }
    }
}

private enum WaypointCheck {
    static func water(at pin: CLLocation) async -> String? {
        do {
            let place = try await CLGeocoder().reverseGeocodeLocation(pin).first
            if place?.ocean != nil || place?.inlandWater != nil {
                return "This pin appears to be on water."
            }
            return nil
        } catch {
            if (error as? CLError)?.code == .geocodeFoundNoResult { return nil }
            return "The water check is unavailable."
        }
    }

    static func route(to pin: CLLocation, from origin: CLLocation?, previous: Bool, sport: WorkoutSport) async -> String? {
        guard let origin else { return "Your current location is unavailable for a route check." }
        let from = previous ? "the previous waypoint" : "your current location"
        let mode = sport == .cycling ? "cycling" : "walking"
        let request = MKDirections.Request()
        request.source = MKMapItem(location: origin, address: nil)
        request.destination = MKMapItem(location: pin, address: nil)
        request.transportType = sport == .cycling ? .cycling : .walking
        do {
            guard let line = try await MKDirections(request: request).calculate().routes.first?.polyline,
                  line.pointCount > 0 else { return "Maps couldn’t find a \(mode) route from \(from)." }
            let end = line.points()[line.pointCount - 1].coordinate
            let gap = CLLocation(latitude: end.latitude, longitude: end.longitude).distance(from: pin)
            guard gap > WaypointProgress.passingWidth else { return nil }
            let distance = Measurement(value: gap, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road))
            return "The \(mode) route from \(from) ends \(distance) from this pin."
        } catch {
            if (error as? MKError)?.code == .directionsNotFound {
                return "Maps couldn’t find a \(mode) route from \(from)."
            }
            return "Maps couldn’t check the route from \(from)."
        }
    }
}

@MainActor
private final class WaypointLocation: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var center: ((CLLocationCoordinate2D) -> Void)?
    var report: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func locate() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: report?("Allow location access in Settings to center the map.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if center != nil && manager.authorizationStatus != .notDetermined { locate() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last, location.horizontalAccuracy >= 0 { center?(location.coordinate) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        report?("Your location is unavailable. Try again.")
    }
}

/// The map keeps its own camera while the runner places or moves a waypoint.
struct WaypointEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.waypointOrigin) private var origin
    @Environment(\.waypointSport) private var sport
    @State private var location = WaypointLocation()
    @State private var map = MKMapView()
    @State private var heading = 0.0
    @FocusState private var searching: Bool
    @State private var optionsOpen = false
    @State private var renaming = false
    @FocusState private var nameFocused: Bool
    @State private var newName = ""
    let otherPins: [WorkoutWaypoint]
    let choices: [(String, String)]
    let selected: String
    @State private var warning = ""
    @State private var changedPoint: RoutePoint?
    @State var waypoint: WorkoutWaypoint
    let phaseName: String?
    var showsEffort = true
    let remove: (() -> Void)?
    let change: (WorkoutWaypoint) -> Void
    let select: (String) -> Void
    @State private var hasPin: Bool
    @State private var query = ""
    @State private var searchMessage: String?
    @State private var searchTask: Task<Void, Never>?

    init(waypoint: WorkoutWaypoint, showsEffort: Bool, existingPin: Bool, phaseName: String?, remove: (() -> Void)?,
         otherPins: [WorkoutWaypoint], previous: WorkoutWaypoint?, choices: [(String, String)],
         selected: String, change: @escaping (WorkoutWaypoint) -> Void, select: @escaping (String) -> Void) {
        _waypoint = State(initialValue: waypoint)
        self.showsEffort = showsEffort
        self.phaseName = phaseName
        self.remove = remove
        self.otherPins = otherPins
        self.choices = choices
        self.selected = selected
        self.change = change
        self.select = select
        _hasPin = State(initialValue: existingPin)
        initialPoint = existingPin ? waypoint.point : previous?.point
    }

    private let initialPoint: RoutePoint?

    private var title: String {
        switch phaseName {
        case "Warm-Up End": return "Warmup End Waypoint"
        case let name?: return name.replacingOccurrences(of: " - ", with: "-") + " Waypoint"
        case nil: return showsEffort ? waypoint.name : "Main End Waypoint"
        }
    }

    var body: some View {
        PinPlacementMap(point: hasPin ? waypoint.point : nil, name: waypoint.name, map: map,
                        initialCenter: initialPoint?.coordinate, others: otherPins, headingChanged: { heading = $0 }) { coordinate in
            location.center = nil
            searchTask?.cancel()
            searchMessage = nil
            searching = false
            update(coordinate)
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
                mapControls
                searchBar
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .overlay(alignment: .top) { floatingHeader }
        .allowsHitTesting(!renaming)
        .accessibilityHidden(renaming)
        .overlay {
            if renaming { renameDialog }
        }
        .toolbarVisibility(.hidden, for: .navigationBar, .tabBar)
        .onAppear {
            if [.authorizedAlways, .authorizedWhenInUse].contains(location.manager.authorizationStatus) {
                map.showsUserLocation = true
            }
            if initialPoint == nil {
                if let fix = recentLocation { moveCamera(to: fix.coordinate) }
                else { locateUser() }
            }
        }
        .onDisappear {
            location.center = nil
            location.report = nil
            map.showsUserLocation = false
            searchTask?.cancel()
        }
        .onChange(of: hasPin ? waypoint : nil) { _, value in
            if let value { change(value) }
        }
        .task(id: changedPoint) {
            guard let changedPoint else { return }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            let pin = changedPoint.location
            let start = origin?.location ?? recentLocation
            async let water = WaypointCheck.water(at: pin)
            async let route = WaypointCheck.route(to: pin, from: start,
                                                 previous: origin != nil, sport: sport)
            let messages = await [water, route].compactMap { $0 }
            if !Task.isCancelled { warning = messages.joined(separator: " ") }
        }
    }

    private var floatingHeader: some View {
        HStack(spacing: 6) {
            // Match the trailing control's intrinsic width to center the title on the map.
            Button("Done") {}
                .hidden()
                .overlay(alignment: .leading) {
                    Button("Back", systemImage: "chevron.backward") { dismiss() }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                }
                .fixedSize()
            Text(waypoint.name == phaseName ? title : waypoint.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .glassEffect(in: .capsule)
                .accessibilityAddTraits(.isHeader)
            Button("Done") { dismiss() }
                .fixedSize()
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var optionsButton: some View {
        Button("Waypoint options", systemImage: "ellipsis") {
            searching = false
            optionsOpen = true
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .popover(isPresented: $optionsOpen) {
            optionsContent.presentationCompactAdaptation(.popover)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }

    private var mapControls: some View {
        VStack(spacing: 0) {
            Button {
                let camera = map.camera
                camera.heading = 0
                map.setCamera(camera, animated: true)
            } label: {
                Image(systemName: "location.north.line.fill")
                    .rotationEffect(.degrees(-heading))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Orient map north")
            Button(action: locateUser) {
                Image(systemName: "location")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Center on my location")
            Button(action: centerOnProgram) {
                Image(systemName: "scope")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Center on workout waypoints")
            .disabled(otherPins.isEmpty && !hasPin)
        }
        .font(.body.weight(.semibold))
        .buttonStyle(.plain)
        .glassEffect(in: .capsule)
    }

    private func locateUser() {
        searching = false
        location.center = { coordinate in
            map.showsUserLocation = true
            moveCamera(to: coordinate)
            location.center = nil
            location.report = nil
        }
        location.report = { message in
            searchMessage = message
            location.center = nil
            location.report = nil
        }
        location.locate()
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !warning.isEmpty {
                HStack {
                    Text(warning).font(.footnote)
                    Button("Keep Pin") { warning = "" }.font(.footnote.bold())
                }
                .padding(10)
                .glassEffect(in: .rect(cornerRadius: 14))
            }
            if let searchMessage {
                Text(searchMessage).font(.footnote).padding(10).glassEffect()
            }
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Place or address", text: $query)
                        .focused($searching).submitLabel(.search).onSubmit { search() }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .glassEffect(.regular.interactive(), in: .capsule)
                optionsButton
            }
        }
    }

    private var renameDialog: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Rename Waypoint").font(.headline)
                TextField(phaseName ?? "Waypoint name", text: $newName, axis: .vertical)
                    .lineLimit(1...2)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                HStack(spacing: 12) {
                    Button("Cancel") { renaming = false }
                        .buttonStyle(.glass)
                        .tint(.gray)
                    Button("Done", action: applyName)
                        .buttonStyle(.glassProminent)
                        .tint(.blue)
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .controlSize(.large)
            }
            .padding(20)
            .frame(maxWidth: 330)
            .background(.regularMaterial, in: .rect(cornerRadius: 24))
            .padding(.horizontal)
            .onAppear { nameFocused = true }
            .accessibilityAddTraits(.isModal)
        }
    }

    private var optionsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Waypoint Selector").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(choices, id: \.0) { id, name in
                        Button {
                            optionsOpen = false
                            guard id != selected else { return }
                            select(id)
                        } label: {
                            HStack {
                                Text(id == selected ? waypoint.name : name)
                                    .lineLimit(2).truncationMode(.tail)
                                Spacer()
                                if id == selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(id == selected ? .isSelected : [])
                    }
                }
            }
            .frame(maxHeight: min(CGFloat(choices.count) * 44, 220))
            Rectangle().fill(.secondary.opacity(0.45)).frame(height: 1).padding(.vertical, 4)
            Button {
                optionsOpen = false
                newName = waypoint.name
                renaming = true
            } label: {
                Label("Rename Waypoint", systemImage: "pencil").frame(minHeight: 44)
            }
            Text("Waypoint changes are saved to this workout draft automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsEffort {
                Picker("Effort to here", selection: $waypoint.effort) {
                    ForEach(IntervalStepKind.allCases, id: \.self) { Text($0.name).tag($0) }
                }
            }
            if let remove {
                Button("Remove waypoint", role: .destructive) { remove(); dismiss() }
            }
        }
        .buttonStyle(.plain)
        .padding()
        .frame(width: 265)
    }

    private func applyName() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        waypoint.name = name
        renaming = false
    }

    private func moveCamera(to coordinate: CLLocationCoordinate2D) {
        map.setRegion(.init(center: coordinate, latitudinalMeters: 650, longitudinalMeters: 650), animated: true)
    }

    private func centerOnProgram() {
        searching = false
        let points = otherPins.map(\.point) + (hasPin ? [waypoint.point] : [])
        guard let region = Self.programRegion(points) else { return }
        map.setRegion(region, animated: true)
    }

    static func programRegion(_ points: [RoutePoint]) -> MKCoordinateRegion? {
        guard let first = points.first else { return nil }
        // Unwrap around the first pin so routes across the date line stay together.
        let offsets = points.map { ($0.longitude - first.longitude + 540).truncatingRemainder(dividingBy: 360) - 180 }
        let count = Double(points.count)
        let meanOffset = offsets.reduce(0, +) / count
        let latitude = points.map(\.latitude).reduce(0, +) / count
        let longitude = (first.longitude + meanOffset + 540).truncatingRemainder(dividingBy: 360) - 180
        let latRadius = points.map { abs($0.latitude - latitude) }.max() ?? 0
        let lonRadius = offsets.map { abs($0 - meanOffset) }.max() ?? 0
        return .init(center: .init(latitude: latitude, longitude: longitude),
                     span: .init(latitudeDelta: min(180, max(0.006, latRadius * 2.8)),
                                 longitudeDelta: min(360, max(0.006, lonRadius * 2.8))))
    }

    private var recentLocation: CLLocation? {
        [location.manager.location, map.userLocation.location].compactMap { $0 }
            .filter { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 300 }
            .max { $0.timestamp < $1.timestamp }
    }

    private func update(_ coordinate: CLLocationCoordinate2D) {
        warning = ""
        hasPin = true
        waypoint.point = .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
        changedPoint = waypoint.point
    }

    private func center(on coordinate: CLLocationCoordinate2D) {
        update(coordinate)
        moveCamera(to: coordinate)
    }

    private func search() {
        searchTask?.cancel()
        searching = false
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = map.region
        searchMessage = "Searching…"
        searchTask = Task {
            let result = try? await MKLocalSearch(request: request).start().mapItems.first
            guard !Task.isCancelled else { return }
            if let result {
                center(on: result.location.coordinate)
                if phaseName == nil { waypoint.name = result.name ?? query }
                searchMessage = "Suggested pin · \(result.name ?? query)."
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

struct WaypointLocationDetail: View {
    let point: RoutePoint
    @State private var resolved: (point: RoutePoint, address: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let resolved, resolved.point == point {
                Text(resolved.address).font(.subheadline).foregroundStyle(.primary)
            }
            Text(verbatim: "\(point.latitude.formatted(.number.precision(.fractionLength(5)))), \(point.longitude.formatted(.number.precision(.fractionLength(5))))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .task(id: point) {
            resolved = nil
            guard let request = MKReverseGeocodingRequest(location: point.location),
                  let item = try? await request.mapItems.first, !Task.isCancelled else { return }
            if let address = item.address?.shortAddress ?? item.name ?? item.address?.fullAddress, !address.isEmpty {
                resolved = (point, address)
            }
        }
    }
}

struct WaypointEndField: View {
    @Binding var end: WaypointEnd?
    var phaseName: String?
    @Environment(\.waypointSlots) private var slots
    @Environment(\.waypointSport) private var sport
    @State private var editing = false

    private var pin: WaypointEnd? { end?.point == nil ? nil : end }

    var body: some View {
        Button {
            editing = true
        } label: {
            HStack {
                Image(systemName: pin == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    if let pin, let point = pin.point {
                        Text(pin.name).lineLimit(2).truncationMode(.tail)
                        WaypointLocationDetail(point: point)
                    } else {
                        Text("Set location on map")
                    }
                }
                Spacer()
                if pin != nil { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityHidden(true) }
            }
        }
        .fullScreenCover(isPresented: $editing) {
            let field = WaypointSlot(phase: phaseName ?? "Main End", end: end) { end = $0 }
            let ordered = slots.contains { $0.id == field.id } ? slots.map { $0.id == field.id ? field : $0 } : slots + [field]
            NavigationStack {
                WorkoutWaypointPicker(slots: ordered, selected: field.id)
                    .environment(\.waypointSport, sport)
            }
        }
    }
}
