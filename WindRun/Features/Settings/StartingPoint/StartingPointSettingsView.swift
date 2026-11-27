//
//  StartingPointSettingsView.swift
//  Wind Run
//
//  Settings → Your Data → Starting Point: what Export Runs hides, the start and finish of each run or the
//  places pinned on a map, and how far around them.
//

import MapKit
import SwiftUI

struct StartingPointSettingsView: View {
    private static let screen = "Starting Point"

    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    @State private var privacy = ExportPrivacy.load()
    @State private var camera: MapCameraPosition
    /// The middle of the map as it last settled, for Add Pin at Map Center.
    @State private var mapCenter: CLLocationCoordinate2D?
    @State private var pinToDelete: ExportPrivacy.Pin?

    init() {
        let privacy = ExportPrivacy.load()
        _privacy = State(initialValue: privacy)
        // Pins already there fill the map; otherwise it starts where the runner is.
        _camera = State(initialValue: Self.framing(privacy.pins, meters: privacy.meters))
    }

    var body: some View {
        Form {
            Section {
                ForEach(ExportPrivacy.Mode.allCases) { mode in
                    Button {
                        Trace.tap(Self.screen, mode.title)
                        privacy.mode = mode
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title)
                                        .foregroundStyle(.primary)
                                    Text(mode.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: mode.systemImage)
                            }
                            Spacer()
                            if privacy.mode == mode {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(privacy.mode == mode ? .isSelected : [])
                }
            } header: {
                Text("Hide")
            } footer: {
                Text("Exports leave out the GPS points in these areas. Your runs and their totals stay as they are.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Distance", value: ExportPrivacy.text(privacy.meters, unit: unit))
                    Slider(
                        value: $privacy.meters,
                        in: ExportPrivacy.meterRange,
                        step: ExportPrivacy.meterStep
                    ) {
                        Text("Distance")
                    } onEditingChanged: { editing in
                        if !editing {
                            Trace.changed(Self.screen, "Distance", to: privacy.meters)
                        }
                    }
                    .accessibilityValue(ExportPrivacy.text(privacy.meters, unit: unit))
                }
            } footer: {
                Text(distanceFooter)
            }

            if privacy.mode == .pins {
                pinsSection
            }
        }
        .navigationTitle("Starting Point")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: privacy) { _, privacy in
            privacy.save()
        }
        .alert("Delete \(pinToDelete.map(pinName(for:)) ?? "Pin")?", isPresented: isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                Trace.tap(Self.screen, "Delete pin confirmed")
                if let pin = pinToDelete {
                    privacy.pins.removeAll { $0.id == pin.id }
                }
                pinToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                Trace.tap(Self.screen, "Delete pin cancelled")
                pinToDelete = nil
            }
        } message: {
            if privacy.pins.count == 1 {
                Text("With no pins, exports hide the start and finish of each run again.")
            }
        }
        .traceScreen(Self.screen)
    }

    private var distanceFooter: String {
        let distance = ExportPrivacy.text(privacy.meters, unit: unit)
        // Pinned Places with no pins still hides the ends.
        return switch privacy.usesPins ? ExportPrivacy.Mode.pins : .startAndFinish {
        case .startAndFinish: "GPS points within \(distance) of where each run starts or finishes are left out."
        case .pins: "GPS points within \(distance) of a pin are left out, wherever they fall in a run."
        }
    }

    @ViewBuilder
    private var pinsSection: some View {
        Section {
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(Array(privacy.pins.enumerated()), id: \.element.id) { index, pin in
                        MapCircle(center: pin.coordinate, radius: privacy.meters)
                            .foregroundStyle(Color.accentColor.opacity(0.2))
                            .stroke(Color.accentColor, lineWidth: 2)
                        Annotation(pinName(at: index), coordinate: pin.coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(Color.onAccent, Color.accentColor)
                                .shadow(radius: 2)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .mapControls {
                    MapUserLocationButton()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    mapCenter = context.region.center
                }
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        addPin(at: coordinate, how: "Tap map")
                    }
                }
            }
            .frame(height: 320)
            .listRowInsets(EdgeInsets())
            .accessibilityLabel("Map of your pins")

            Button("Add Pin at Map Center", systemImage: "plus") {
                if let mapCenter {
                    addPin(at: mapCenter, how: "Add Pin at Map Center")
                }
            }
            .disabled(mapCenter == nil || isFull)

            ForEach(Array(privacy.pins.enumerated()), id: \.element.id) { index, pin in
                Button {
                    Trace.tap(Self.screen, "Show pin")
                    withAnimation {
                        camera = .region(MKCoordinateRegion(
                            center: pin.coordinate,
                            latitudinalMeters: privacy.meters * 6,
                            longitudinalMeters: privacy.meters * 6
                        ))
                    }
                } label: {
                    Label(pinName(at: index), systemImage: "mappin")
                        .foregroundStyle(.primary)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Trace.tap(Self.screen, "Delete pin")
                        pinToDelete = pin
                    }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Trace.tap(Self.screen, "Delete pin")
                        pinToDelete = pin
                    }
                }
            }
        } header: {
            Text("Pins")
        } footer: {
            Text(pinsFooter)
        }
    }

    private var pinsFooter: String {
        if privacy.pins.isEmpty {
            return "Tap the map to drop a pin on a place to hide, such as home. Until you add one, exports hide the start and finish of each run."
        }
        if isFull {
            return "You've added the most pins there's room for, \(ExportPrivacy.pinLimit). Delete one to add another."
        }
        return "Tap the map to drop another pin. Swipe a pin to delete it. Pins stay on this iPhone, and in your private iCloud when iCloud Sync is on."
    }

    /// Fits every pin and its circle, or starts where the runner is when there are none yet.
    private static func framing(_ pins: [ExportPrivacy.Pin], meters: CLLocationDistance) -> MapCameraPosition {
        guard let first = pins.first else { return .userLocation(fallback: .automatic) }
        var rect = MKMapRect.null
        for pin in pins {
            let point = MKMapPoint(pin.coordinate)
            let radius = meters * MKMapPointsPerMeterAtLatitude(pin.latitude)
            rect = rect.union(MKMapRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        guard !rect.isNull, !rect.isEmpty else {
            return .region(MKCoordinateRegion(center: first.coordinate, latitudinalMeters: meters * 6, longitudinalMeters: meters * 6))
        }
        // Room around the edges, so no pin sits under a map control.
        let padded = rect.insetBy(dx: -rect.width * 0.25, dy: -rect.height * 0.25)
        return .rect(padded)
    }

    private var isFull: Bool {
        privacy.pins.count >= ExportPrivacy.pinLimit
    }

    private func addPin(at coordinate: CLLocationCoordinate2D, how: String) {
        guard !isFull, CLLocationCoordinate2DIsValid(coordinate) else { return }
        // Never the place itself.
        Trace.tap(Self.screen, how, ["pins": privacy.pins.count + 1])
        privacy.pins.append(ExportPrivacy.Pin(coordinate))
    }

    private func pinName(at index: Int) -> String {
        "Pin \(index + 1)"
    }

    private func pinName(for pin: ExportPrivacy.Pin) -> String {
        privacy.pins.firstIndex(of: pin).map { pinName(at: $0) } ?? "Pin"
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { pinToDelete != nil },
            set: { if !$0 { pinToDelete = nil } }
        )
    }
}

#Preview("Starting Point") {
    NavigationStack { StartingPointSettingsView() }
}
