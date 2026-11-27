import CoreLocation
import Foundation

/// One GPS fix, copied out of the store so places can be worked out off the main thread.
nonisolated struct PlaceFix: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Meters, negative when unknown.
    var accuracy: Double
    var paused: Bool

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var isValid: Bool {
        CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            && !(latitude == 0 && longitude == 0)
    }
}

/// The places a workout went through, worked out on the iPhone from the offline pack.
nonisolated struct RoutePlaces: Equatable, Sendable {
    /// True when the workout started in a US state or territory the pack covers.
    var inUS: Bool
    /// The areas at the first point outside the start's privacy zone. Empty when the whole route is
    /// inside the zone.
    var start: [RouteArea]
    /// Every other area the route went through, in the order it reached them.
    var passed: [RouteArea]

    /// How far apart the looked-up points are.
    static let spacing: CLLocationDistance = 100
    /// Fixes less sure than this are skipped.
    static let worstAccuracy: CLLocationAccuracy = 50
    /// The same zone as `RunExport.privacyZoneMeters`, which a test keeps equal. Copied here so tagging can
    /// run off the main actor.
    static let privacyZone: CLLocationDistance = 250

    /// Works out the places along a route. Points inside the privacy zone at either end are skipped, the
    /// same zone exports use, so the start town never comes from home itself. Only the start point is
    /// used to tell whether the workout is in the US, and that answer never leaves the iPhone.
    static func of(_ fixes: [PlaceFix], pack: AreaPack,
                   privacyZone: CLLocationDistance = RoutePlaces.privacyZone) throws -> RoutePlaces? {
        let valid = fixes.filter(\.isValid)
        guard let first = valid.first, let last = valid.last else { return nil }
        let startAreas = try pack.areas(latitude: first.latitude, longitude: first.longitude)
        guard startAreas.contains(where: { $0.kind == .state || $0.kind == .territory }) else {
            return RoutePlaces(inUS: false, start: [], passed: [])
        }
        let firstLocation = first.location, lastLocation = last.location
        var start: [RouteArea]?
        var passed: [RouteArea] = []
        var seen = Set<RouteArea>()
        var previous: CLLocation?
        var sinceLast = Double.infinity
        for fix in valid {
            try Task.checkCancellation()
            let location = fix.location
            if let previous { sinceLast += location.distance(from: previous) }
            previous = location
            guard !fix.paused, (0...worstAccuracy).contains(fix.accuracy) else { continue }
            let margin = privacyZone + fix.accuracy
            guard location.distance(from: firstLocation) > margin,
                  location.distance(from: lastLocation) > margin else { continue }
            // The first point out of the zone always counts, then one about every 100 m.
            guard start == nil || sinceLast >= spacing else { continue }
            sinceLast = 0
            let here = try pack.areas(latitude: fix.latitude, longitude: fix.longitude)
            if start == nil {
                start = here
                seen.formUnion(here)
                continue
            }
            for area in here where seen.insert(area).inserted { passed.append(area) }
        }
        return RoutePlaces(inUS: true, start: start ?? [], passed: passed)
    }

    /// The search place: the start's park, neighborhood, city and state, plus every place passed through.
    /// Nil when no point was outside the privacy zone.
    @MainActor var searchPlace: WorkoutSearchPlace? {
        guard inUS, !start.isEmpty else { return nil }
        let order: [RouteArea.Kind] = [.park, .neighborhood, .city, .territory, .state]
        let sorted = start.sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
        let city = sorted.first { $0.kind == .city }
        let state = sorted.first { $0.kind == .state || $0.kind == .territory }
        let code = state?.stateCode ?? city?.stateCode ?? ""
        let names = sorted.filter { $0.kind != .state }.map(\.name)
        let address = (names + [code]).filter { !$0.isEmpty }.joined(separator: ", ")
        var seen = Set(sorted.map(\.name))
        let through = passed.filter { $0.kind != .state && seen.insert($0.name).inserted }.map(\.name)
            + passed.filter { $0.kind == .state }.map(\.name)
        return WorkoutSearchPlace(address: address, city: city?.name ?? sorted.first { $0.kind == .neighborhood }?.name ?? "",
                                  state: code, country: "US", passed: through.isEmpty ? nil : through)
    }

    /// The town shown under a workout, such as "Portland, OR".
    @MainActor var displayCity: String? {
        guard let place = searchPlace else { return nil }
        let text = place.cityAndState
        return text.isEmpty ? nil : text
    }
}

/// Where the Apple Maps lookup for a start outside the US is made: a random point 50 to 150 m from the
/// first GPS fix, in a random direction, so the exact start is never sent.
nonisolated enum StartLookupPoint {
    static let distances: ClosedRange<CLLocationDistance> = 50...150

    static func near(_ start: CLLocationCoordinate2D, using generator: inout some RandomNumberGenerator) -> CLLocationCoordinate2D {
        let distance = Double.random(in: distances, using: &generator)
        let bearing = Double.random(in: 0..<(2 * .pi), using: &generator)
        let earth = 6_371_000.0
        let angular = distance / earth
        let lat1 = start.latitude * .pi / 180, lon1 = start.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        var longitude = lon2 * 180 / .pi
        if longitude > 180 { longitude -= 360 } else if longitude < -180 { longitude += 360 }
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: longitude)
    }

    static func near(_ start: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        var generator = SystemRandomNumberGenerator()
        return near(start, using: &generator)
    }
}
