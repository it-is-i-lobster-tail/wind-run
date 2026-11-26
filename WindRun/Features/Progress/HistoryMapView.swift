import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct HistoryMapView: View {
    let openSearch: () -> Void
    @Query(sort: \Run.startDateValue, order: .reverse) private var history: [Run]
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @Namespace private var mapScope
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
            guard let point = run.startLocation?.coordinate else { return nil }
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
            Map(position: $camera, selection: $selection, scope: mapScope) {
                UserAnnotation()
                ForEach(groups.keys.compactMap { $0 }, id: \.self) { start in
                    if let visits = groups[start], let first = visits.first {
                        workoutMarker(visits.count == 1 ? "1 workout" : "\(visits.count) workouts",
                                      symbol: workoutSymbol(for: first), coordinate: start.coordinate)
                            .tint(.indigo)
                            .tag(start)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    Button {
                        withAnimation { camera = .userLocation(fallback: .automatic) }
                    } label: {
                        Image(systemName: "location")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Center on my location")
                    MapCompass(scope: mapScope)
                }
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            .mapScope(mapScope)
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
                    .padding()
                    .glassEffect(.clear.tint(Color(uiColor: .systemBackground).opacity(0.45)).interactive(), in: .rect(cornerRadius: 22))
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
                    } icon: { WorkoutGlyph(value: workoutSymbol(for: run)) }
                }
            }
        }
    }

    private func workoutSymbol(for run: Run) -> String {
        run.intervalPlan?.workoutSymbol ?? run.sport.systemImage
    }

    @MapContentBuilder
    private func workoutMarker(_ title: String, symbol: String, coordinate: CLLocationCoordinate2D) -> some MapContent {
        if symbol.hasPrefix("workout.") {
            Marker(title, image: symbol, coordinate: coordinate)
        } else {
            Marker(title, systemImage: symbol, coordinate: coordinate)
        }
    }
}
