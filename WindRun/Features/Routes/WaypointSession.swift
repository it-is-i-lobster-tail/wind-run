import MapKit
import SwiftUI

struct WaypointSession: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var progress: WaypointProgress
    @State private var previewPaused = false

    init(workout: WaypointWorkout) {
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
                        WaypointMap(workout: workout, start: start, progress: progress)
                            .frame(height: 285)
                        Label("Simulated movement between waypoints.", systemImage: "play.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if progress.leg + 1 < workout.legCount {
                            let next = progress.leg + 1
                            Divider()
                            Text("Up next").font(.subheadline).foregroundStyle(.secondary)
                            let point = workout.points.indices.contains(next) ? workout.points[next] : nil
                            Text("\((point?.effort ?? workout.returnEffort).name) to \(point?.name ?? "starting point")")
                                .font(.headline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle("Workout preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !progress.finished {
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
        }
        .task(id: previewPaused) {
            guard !previewPaused else { return }
            await playPreview()
        }
        .sensoryFeedback(.success, trigger: progress.leg)
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
