//
//  RouteSample.swift
//  Wind Run
//

import CoreLocation
import Foundation
import SwiftData

/// One GPS fix along a run's route.
@Model
final class RouteSample {
    var timestampValue: Date = Date.now
    var latitudeValue: Double = 0
    var longitudeValue: Double = 0
    var altitudeValue: Double = 0
    var horizontalAccuracyValue: Double = 0
    var verticalAccuracyValue: Double = 0
    /// Meters per second, negative when unknown.
    var speedValue: Double = -1
    /// Degrees from true north, negative when unknown.
    var courseValue: Double = -1

    var runValue: Run?

    init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        horizontalAccuracy: Double = 0,
        verticalAccuracy: Double = 0,
        speed: Double = -1,
        course: Double = -1
    ) {
        self.timestampValue = timestamp
        self.latitudeValue = latitude
        self.longitudeValue = longitude
        self.altitudeValue = altitude
        self.horizontalAccuracyValue = horizontalAccuracy
        self.verticalAccuracyValue = verticalAccuracy
        self.speedValue = speed
        self.courseValue = course
    }

    convenience init(_ location: CLLocation) {
        self.init(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            course: location.course
        )
    }
}

extension RouteSample {
    var timestamp: Date { timestampValue }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitudeValue, longitude: longitudeValue)
    }

    var location: CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitudeValue,
            horizontalAccuracy: horizontalAccuracyValue,
            verticalAccuracy: verticalAccuracyValue,
            course: courseValue,
            speed: speedValue,
            timestamp: timestampValue
        )
    }
}
