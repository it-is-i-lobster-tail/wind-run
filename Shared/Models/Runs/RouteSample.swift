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
    /// How sure the speed is, in meters per second, negative when unknown. Runs recorded before it was
    /// kept have -1 here.
    var speedAccuracyValue: Double = -1

    var runValue: Run?

    init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        horizontalAccuracy: Double = 0,
        verticalAccuracy: Double = 0,
        speed: Double = -1,
        course: Double = -1,
        speedAccuracy: Double = -1
    ) {
        self.timestampValue = timestamp
        self.latitudeValue = latitude
        self.longitudeValue = longitude
        self.altitudeValue = altitude
        self.horizontalAccuracyValue = horizontalAccuracy
        self.verticalAccuracyValue = verticalAccuracy
        self.speedValue = speed
        self.courseValue = course
        self.speedAccuracyValue = speedAccuracy
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
            course: location.course,
            speedAccuracy: location.speedAccuracy
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
            courseAccuracy: -1,
            speed: speedValue,
            speedAccuracy: speedAccuracyValue,
            timestamp: timestampValue
        )
    }
}

/// One GPS fix copied out of the store. Each read of a stored model's property goes through SwiftData and
/// costs far more than reading a plain value, and a long run has thousands of fixes, so the run summary,
/// the charts and the comparisons read each fix once into one of these and work from that. The names match
/// `RouteSample`'s, so code can take either.
nonisolated struct RouteReading: Equatable {
    let timestamp: Date
    let latitudeValue: Double
    let longitudeValue: Double
    let altitudeValue: Double
    let horizontalAccuracyValue: Double
    let verticalAccuracyValue: Double
    let speedValue: Double
    let courseValue: Double
    let speedAccuracyValue: Double

    init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        horizontalAccuracy: Double = 0,
        verticalAccuracy: Double = 0,
        speed: Double = -1,
        course: Double = -1,
        speedAccuracy: Double = -1
    ) {
        self.timestamp = timestamp
        latitudeValue = latitude
        longitudeValue = longitude
        altitudeValue = altitude
        horizontalAccuracyValue = horizontalAccuracy
        verticalAccuracyValue = verticalAccuracy
        speedValue = speed
        courseValue = course
        speedAccuracyValue = speedAccuracy
    }

    init(_ sample: RouteSample) {
        timestamp = sample.timestampValue
        latitudeValue = sample.latitudeValue
        longitudeValue = sample.longitudeValue
        altitudeValue = sample.altitudeValue
        horizontalAccuracyValue = sample.horizontalAccuracyValue
        verticalAccuracyValue = sample.verticalAccuracyValue
        speedValue = sample.speedValue
        courseValue = sample.courseValue
        speedAccuracyValue = sample.speedAccuracyValue
    }

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
            courseAccuracy: -1,
            speed: speedValue,
            speedAccuracy: speedAccuracyValue,
            timestamp: timestamp
        )
    }
}
