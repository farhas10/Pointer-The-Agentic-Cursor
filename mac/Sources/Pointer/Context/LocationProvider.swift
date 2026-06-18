import CoreLocation
import Foundation

/// Best-effort device location for proximity queries ("nearby", "near me").
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var cached: UserLocation?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Prompt for location access (if not yet determined) and warm up a GPS fix.
    /// Call once at launch so the permission dialog appears up front and a fix
    /// is cached before the first nearby query.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    /// Returns GPS fix when authorized; falls back to saved city from UserDefaults.
    func currentLocation() -> UserLocation? {
        if let cached { return cached }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Kick off a refresh for next time; return saved city meanwhile.
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        return savedCityLocation()
    }

    func savedCity() -> String? {
        UserDefaults.standard.string(forKey: Self.savedCityKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    func setSavedCity(_ city: String?) {
        if let city, !city.isEmpty {
            UserDefaults.standard.set(city, forKey: Self.savedCityKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.savedCityKey)
        }
        cached = nil
    }

    private func savedCityLocation() -> UserLocation? {
        guard let city = savedCity() else { return nil }
        return UserLocation(city: city, source: .saved)
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.cached = UserLocation(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                accuracyMeters: loc.horizontalAccuracy,
                source: .gps
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Fall back to saved city; no-op.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // The first fix can only be requested after the user grants access, so
        // do it here once authorization flips to granted.
        Task { @MainActor in
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            default:
                break
            }
        }
    }

    private static let savedCityKey = "pointer.savedCity"
}

public struct UserLocation: Codable, Sendable, Equatable {
    var latitude: Double?
    var longitude: Double?
    var accuracyMeters: Double?
    var city: String?
    var source: Source

    public enum Source: String, Codable, Sendable {
        case gps
        case saved
    }

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracyMeters: Double? = nil,
        city: String? = nil,
        source: Source
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.city = city
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case accuracyMeters = "accuracy_meters"
        case city
        case source
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
