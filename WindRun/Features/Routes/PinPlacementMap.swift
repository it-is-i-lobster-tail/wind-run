import MapKit
import SwiftUI

/// A tap or a stationary long press places a waypoint. Dragging pans the map.
struct PinPlacementMap: UIViewRepresentable {
    let point: RoutePoint?
    let name: String
    let map: MKMapView
    let initialCenter: CLLocationCoordinate2D?
    let others: [WorkoutWaypoint]
    let headingChanged: (Double) -> Void
    let place: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        map.showsCompass = false
        map.delegate = context.coordinator
        let labels = context.coordinator.labelOverlay
        labels.frame = map.bounds
        labels.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        labels.isUserInteractionEnabled = false
        labels.clipsToBounds = true
        map.addSubview(labels)
        if let center = initialCenter {
            var region = MKCoordinateRegion(center: center, latitudinalMeters: 800, longitudinalMeters: 800)
            for pin in others {
                let delta = abs((pin.point.longitude - center.longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
                region.span.longitudeDelta = min(360, max(region.span.longitudeDelta, delta * 2.8))
                region.span.latitudeDelta = min(180, max(region.span.latitudeDelta, abs(pin.point.latitude - center.latitude) * 2.8))
            }
            map.setRegion(region, animated: false)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dropPin))
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dropPin))
        for gesture in [tap, hold] {
            gesture.delegate = context.coordinator
            map.addGestureRecognizer(gesture)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.others != others {
            map.removeAnnotations(coordinator.otherPins)
            coordinator.others = others
            coordinator.otherPins = others.map { waypoint in
                let annotation = MKPointAnnotation()
                annotation.coordinate = waypoint.point.coordinate
                annotation.title = waypoint.name
                return annotation
            }
            map.addAnnotations(coordinator.otherPins)
        }
        defer { coordinator.layoutLabels(on: map) }
        guard let point else { return }
        let pin = coordinator.pin
        if pin.title != name { pin.title = name }

        if pin.coordinate.latitude != point.latitude || pin.coordinate.longitude != point.longitude {
            pin.coordinate = point.coordinate
        }
        if !map.annotations.contains(where: { $0 === pin }) { map.addAnnotation(pin) }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: PinPlacementMap
        let pin = MKPointAnnotation()
        var others: [WorkoutWaypoint] = []
        var otherPins: [MKPointAnnotation] = []
        let labelOverlay = UIView()
        private var labels: [ObjectIdentifier: InsetWaypointLabel] = [:]

        init(_ parent: PinPlacementMap) {
            self.parent = parent
            pin.title = "Waypoint"
        }

        @objc func dropPin(_ gesture: UIGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            if gesture is UILongPressGestureRecognizer, gesture.state != .began { return }
            let location = gesture.location(in: map)
            parent.place(map.convert(location, toCoordinateFrom: map))
        }

        private func hitsPin(_ location: CGPoint, in map: MKMapView) -> Bool {
            guard let marker = map.view(for: pin) else { return false }
            return marker.bounds.insetBy(dx: -7, dy: -7).contains(marker.convert(location, from: map))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let map = gestureRecognizer.view as? MKMapView else { return true }
            return !hitsPin(touch.location(in: map), in: map)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.headingChanged(mapView.camera.heading)
            layoutLabels(on: mapView)
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            layoutLabels(on: mapView)
        }

        func layoutLabels(on map: MKMapView) {
            let pins = (parent.point == nil ? [] : [pin]) + otherPins
            let keys = Set(pins.map(ObjectIdentifier.init))
            for key in labels.keys.filter({ !keys.contains($0) }) {
                labels.removeValue(forKey: key)?.removeFromSuperview()
            }
            let bounds = map.bounds.insetBy(dx: 4, dy: 4)
            guard bounds.width > 40 else { return }
            map.bringSubviewToFront(labelOverlay)
            var occupied: [CGRect] = []
            for annotation in pins {
                let anchor = map.convert(annotation.coordinate, toPointTo: map)
                let key = ObjectIdentifier(annotation)
                guard bounds.contains(anchor) else {
                    labels[key]?.isHidden = true
                    continue
                }
                let label: InsetWaypointLabel
                if let existing = labels[key] { label = existing }
                else {
                    label = InsetWaypointLabel()
                    label.backgroundColor = .systemBackground
                    label.textColor = .label
                    label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .boldSystemFont(ofSize: 15))
                    label.adjustsFontForContentSizeCategory = true
                    label.numberOfLines = 2
                    label.lineBreakMode = .byTruncatingTail
                    label.textAlignment = .center
                    label.layer.cornerRadius = 7
                    label.layer.borderWidth = 1.5
                    label.clipsToBounds = true
                    label.isAccessibilityElement = false
                    labels[key] = label
                    labelOverlay.addSubview(label)
                }
                label.layer.borderColor = (annotation === pin ? UIColor(Color.accentColor) : UIColor.secondaryLabel)
                    .resolvedColor(with: map.traitCollection).cgColor
                label.text = annotation.title
                label.isHidden = false
                let maxWidth = min(bounds.width, 230)
                let textSize = label.sizeThatFits(CGSize(width: maxWidth - 16, height: .greatestFiniteMagnitude))
                let width = min(maxWidth, ceil(textSize.width) + 16)
                let height = ceil(textSize.height) + 8
                let x = min(max(anchor.x - width / 2, bounds.minX), bounds.maxX - width)
                var frame = CGRect(x: x, y: anchor.y + 4, width: width, height: height)
                while let collision = occupied.first(where: { $0.intersects(frame) }) {
                    frame.origin.y = collision.maxY + 2
                }
                if frame.maxY > bounds.maxY {
                    frame.origin.y = anchor.y - height - 42
                    while let collision = occupied.first(where: { $0.intersects(frame) }) {
                        frame.origin.y = collision.minY - height - 2
                    }
                }
                label.frame = frame.integral
                occupied.append(frame.insetBy(dx: -2, dy: -2))
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
            view.markerTintColor = annotation === pin ? UIColor(Color.accentColor) : .secondaryLabel
            view.glyphTintColor = .white
            view.glyphImage = UIImage(systemName: "flag.fill")
            view.titleVisibility = .hidden
            view.displayPriority = .required
            view.animatesWhenAdded = true
            view.accessibilityLabel = annotation.title ?? "Waypoint"
            return view
        }

    }
}


private final class InsetWaypointLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 8, dy: 4))
    }
}
