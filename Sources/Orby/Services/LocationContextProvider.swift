import Foundation
import CoreLocation

final class LocationContextProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationContextProvider()

    @Published var locationEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(locationEnabled, forKey: "locationEnabled")
            if locationEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    /// Current location label based on clustering ("Place 1", "Place 2", etc.)
    private(set) var currentLocationLabel: String?

    private let manager = CLLocationManager()
    private var knownPlaces: [KnownPlace] = []
    private static let clusterRadius: CLLocationDistance = 500  // meters
    private static let maxPlaces = 5

    private struct KnownPlace: Codable {
        let label: String
        let latitude: Double
        let longitude: Double

        var location: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }
    }

    private override init() {
        super.init()
        locationEnabled = UserDefaults.standard.bool(forKey: "locationEnabled")
        loadPlaces()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if locationEnabled {
            startMonitoring()
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedAlways || status == .authorized {
            manager.startUpdatingLocation()
        }
    }

    private func stopMonitoring() {
        manager.stopUpdatingLocation()
        currentLocationLabel = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if locationEnabled && (status == .authorizedAlways || status == .authorized) {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateCurrentLabel(for: location)
    }

    // MARK: - Clustering

    private func updateCurrentLabel(for location: CLLocation) {
        // Check if location matches a known place
        for place in knownPlaces {
            if location.distance(from: place.location) < Self.clusterRadius {
                currentLocationLabel = place.label
                return
            }
        }

        // New place — add it if under limit
        if knownPlaces.count < Self.maxPlaces {
            let label = "Place \(knownPlaces.count + 1)"
            let newPlace = KnownPlace(
                label: label,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            knownPlaces.append(newPlace)
            currentLocationLabel = label
            savePlaces()
        } else {
            // Over limit — use nearest known place
            let nearest = knownPlaces.min(by: {
                location.distance(from: $0.location) < location.distance(from: $1.location)
            })
            currentLocationLabel = nearest?.label
        }
    }

    // MARK: - Persistence

    private var placesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let orbyDir = appSupport.appendingPathComponent("Orby")
        try? FileManager.default.createDirectory(at: orbyDir, withIntermediateDirectories: true)
        return orbyDir.appendingPathComponent("known_places.json")
    }

    private func loadPlaces() {
        guard let data = try? Data(contentsOf: placesURL),
              let places = try? JSONDecoder().decode([KnownPlace].self, from: data) else { return }
        knownPlaces = places
    }

    private func savePlaces() {
        guard let data = try? JSONEncoder().encode(knownPlaces) else { return }
        try? data.write(to: placesURL, options: .atomic)
    }
}
