import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct HistoryMapView: View {
    let openSearch: () -> Void
    @Query(sort: \Run.startDateValue, order: .reverse) private var history: [Run]
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var locationManager = CLLocationManager()
    @State private var selection: Start?
    private var runs: [Run] { history.filter { $0.status == .complete } }

    // Group nearby starts to keep repeat visits to the same spot selectable.
    private struct Start: Hashable, Identifiable {
        let lat: Int
        let lon: Int
        var id: Self { self }

        init?(_ run: Run) {
            guard let point = run.routeSamplesValue?.min(by: { $0.timestamp < $1.timestamp })?.coordinate,
                  CLLocationCoordinate2DIsValid(point) else { return nil }
            lat = Int((point.latitude * 10_000).rounded())
            lon = Int((point.longitude * 10_000).rounded())
        }

        var coordinate: CLLocationCoordinate2D {
            .init(latitude: Double(lat) / 10_000, longitude: Double(lon) / 10_000)
        }
    }

    var body: some View {
        let completed = runs
        let groups = Dictionary(grouping: completed, by: { Start($0) })
        NavigationStack {
            Map(position: $camera, selection: $selection) {
                UserAnnotation()
                ForEach(groups.keys.compactMap { $0 }, id: \.self) { start in
                    if let visits = groups[start], let first = visits.first {
                        Marker(visits.count == 1 ? "1 workout" : "\(visits.count) workouts",
                               systemImage: first.sport.systemImage, coordinate: start.coordinate)
                            .tint(.indigo)
                            .tag(start)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton(); MapCompass() }
            .safeAreaInset(edge: .bottom) {
                Button(action: openSearch) {
                    HStack {
                        Image(systemName: "list.bullet")
                        VStack(alignment: .leading) {
                            Text("History").font(.title2.bold())
                            Text(completed.isEmpty ? "No completed workouts yet" : "\(completed.count) workouts")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain).padding(.horizontal).padding(.bottom, 6)
            }
            .navigationDestination(item: $selection) { start in
                let visits = groups[start] ?? []
                if visits.count == 1, let run = visits.first {
                    RunDetailView(run: run)
                } else {
                    workoutList(visits).navigationTitle("Workouts here")
                }
            }
            .onAppear {
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestWhenInUseAuthorization()
                }
            }
        }
    }

    private func workoutList(_ visits: [Run]) -> some View {
        List {
            ForEach(visits) { run in
                NavigationLink { RunDetailView(run: run) } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(RunFormat.distance(run.distanceMeters, unit: unit)).font(.headline)
                            Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: run.sport.systemImage) }
                }
            }
        }
    }
}
