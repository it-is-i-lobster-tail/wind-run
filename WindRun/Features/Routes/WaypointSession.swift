import MapKit
import SwiftUI

enum RouteSessionMode: String, Identifiable {
    case preview, gps
    var id: Self { self }
}

struct WaypointSession: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    let mode: RouteSessionMode
    @State private var progress: WaypointProgress
    @State private var route: MKRoute?
    @State private var routing = false
    @State private var gpsStatus = "Finding your starting point…"
    @State private var previewPaused = false
    @State private var endRequested = false

    init(workout: WaypointWorkout, mode: RouteSessionMode) {
        self.mode = mode
        _progress = State(initialValue: WaypointProgress(workout: workout))
    }

    private var workout: WaypointWorkout { progress.workout }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if progress.finished {
                        complete
                    } else if let start = progress.start {
                        HStack {
                            Label(progress.effort.name, systemImage: IntervalStepChoice(kind: progress.effort, isWalk: false).systemImage)
                                .font(.headline).foregroundStyle(progress.effort.routeTint)
                            Spacer()
                            Text("Leg \(progress.leg + 1) of \(workout.legCount)")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("To \(progress.destination)").font(.largeTitle.bold())
                            if let position = progress.position, let target = progress.target {
                                let meters = position.location.distance(from: target.location)
                                Text("\(RunFormat.distance(meters, unit: unit)) to waypoint")
                                    .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        WaypointMap(workout: workout, start: start, progress: progress, route: route)
                            .frame(height: 285)
                        Label(mapCaption, systemImage: mode == .preview ? "play.circle" : "location")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if mode == .gps, !gpsStatus.isEmpty { Text(gpsStatus).font(.footnote) }
                        if progress.leg + 1 < workout.legCount {
                            let next = progress.leg + 1
                            Divider()
                            Text("Up next").font(.subheadline).foregroundStyle(.secondary)
                            let point = workout.points.indices.contains(next) ? workout.points[next] : nil
                            Text("\((point?.effort ?? workout.returnEffort).name) to \(point?.name ?? "starting point")")
                                .font(.headline)
                        }
                    } else {
                        ContentUnavailableView("Waiting for GPS", systemImage: "location.viewfinder",
                                               description: Text(gpsStatus))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle(mode == .preview ? "Workout preview" : "\(workout.activity.rawValue) guidance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        if mode == .gps && !progress.finished && progress.start != nil { endRequested = true }
                        else { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if mode == .preview && !progress.finished {
                    HStack {
                        Button(previewPaused ? "Play" : "Pause", systemImage: previewPaused ? "play.fill" : "pause.fill") {
                            previewPaused.toggle()
                        }.buttonStyle(.bordered)
                        Button("Pass waypoint", systemImage: "forward.end.fill") {
                            if let from = progress.position, let target = progress.target {
                                let travel = previewHeading(from: from, to: target)
                                progress.receive(travel.offset(target, forward: 65, sideways: 0))
                            }
                        }.prominentAccentButton().disabled(progress.target == nil)
                    }.controlSize(.large).padding()
                }
            }
            .confirmationDialog("End route guidance?", isPresented: $endRequested, titleVisibility: .visible) {
                Button("End guidance", role: .destructive) { dismiss() }
            }
        }
        .task { if mode == .gps { await followGPS() } }
        .task(id: previewPaused) {
            guard mode == .preview, !previewPaused else { return }
            await playPreview()
        }
        .task(id: progress.target) { await fetchDirections() }
        .sensoryFeedback(.success, trigger: progress.leg)
    }

    private var mapCaption: String {
        if mode == .preview { return "Simulated movement between waypoints." }
        if routing { return "Finding a path to the waypoint…" }
        if route != nil { return workout.activity == .ride ? "Cycling path to the next waypoint." : "Walking path to the next waypoint." }
        return "Path unavailable. Dashed lines show waypoint direction."
    }

    private var complete: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Route complete").font(.largeTitle.bold())
            Text(workout.name).font(.title3)
            Text("\(workout.legCount) legs completed").foregroundStyle(.secondary)
            Button("Back to route") { dismiss() }.prominentAccentButton().controlSize(.large)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func followGPS() async {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                guard !Task.isCancelled, !progress.finished else { return }
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    gpsStatus = "Allow location access in Settings, or try the workout preview."
                    continue
                }
                guard let fix = update.location else { continue }
                guard (0...RunRecorder.maximumHorizontalAccuracy).contains(fix.horizontalAccuracy),
                      abs(fix.timestamp.timeIntervalSinceNow) < 15 else {
                    gpsStatus = "Waiting for a more accurate location."
                    continue
                }
                gpsStatus = ""
                progress.receive(.init(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude),
                                 accuracy: fix.horizontalAccuracy, at: fix.timestamp)
                if progress.finished { return }
            }
        } catch { gpsStatus = "Location is unavailable. Close guidance and try again." }
    }

    private func fetchDirections() async {
        route = nil
        routing = false
        guard mode == .gps, let target = progress.target, let position = progress.position else { return }
        let request = MKDirections.Request()
        request.transportType = workout.activity == .ride ? .cycling : .walking
        request.source = MKMapItem(location: position.location, address: nil)
        request.destination = MKMapItem(location: target.location, address: nil)
        routing = true
        let result = try? await MKDirections(request: request).calculate().routes.first
        guard !Task.isCancelled else { return }
        route = result
        routing = false
    }

    private func previewHeading(from: RoutePoint, to target: RoutePoint) -> WaypointDirection {
        let heading = WaypointDirection(from: from, to: target)
        if heading.length > 0 { return heading }
        // Coincident pins still need movement to demonstrate crossing the next line.
        return WaypointDirection(from: .poolStart, to: WaypointWorkout.outAndBack.points[0].point)
    }

    private func playPreview() async {
        if progress.start == nil { progress.receive(workout.previewStart) }
        while !Task.isCancelled, !progress.finished {
            let leg = progress.leg
            guard let from = progress.position, let target = progress.target else { return }
            // Deliberately pass beside the pin so the preview demonstrates the same gate as GPS.
            let travel = previewHeading(from: from, to: target)
            let pass = travel.offset(target, forward: 20, sideways: min(40, travel.length * 0.25))
            for tick in 1...40 {
                do { try await Task.sleep(for: .milliseconds(275)) } catch { return }
                guard progress.leg == leg else { break }
                let fraction = Double(tick) / 40
                progress.receive(.init(latitude: from.latitude + (pass.latitude - from.latitude) * fraction,
                                       longitude: from.longitude + (pass.longitude - from.longitude) * fraction))
            }
        }
    }
}
