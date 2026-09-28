import CoreLocation
import Foundation
import MarqetCore

enum LocationAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
}

/// Optional location (KONZEPT §14.1): only "when in use", only for branches nearby and distance sorting.
@MainActor
protocol LocationProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    /// Asks for "when in use" access if not decided yet; returns the resulting state.
    func requestAuthorization() async -> LocationAuthorization
    /// One current position, `nil` without access or on failure.
    func currentLocation() async -> GeoPoint?
    /// "Immer": needed to report arrivals at a store in the background (KONZEPT-WIDGETS §13).
    var isAlwaysAuthorized: Bool { get }
    /// Asks for "Immer" (first time: the system prompt, later only Settings can change it).
    func requestAlwaysAuthorization() async -> Bool
}

extension LocationProviding {
    var isAlwaysAuthorized: Bool { false }
    func requestAlwaysAuthorization() async -> Bool { false }
}

@MainActor
final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationContinuations: [CheckedContinuation<LocationAuthorization, Never>] = []
    private var alwaysContinuations: [CheckedContinuation<Bool, Never>] = []
    private var locationContinuations: [CheckedContinuation<GeoPoint?, Never>] = []
    private var lastLocation: (point: GeoPoint, date: Date)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorization: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    func requestAuthorization() async -> LocationAuthorization {
        guard manager.authorizationStatus == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    var isAlwaysAuthorized: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    func requestAlwaysAuthorization() async -> Bool {
        let status = manager.authorizationStatus
        if status == .authorizedAlways { return true }
        guard status == .notDetermined || status == .authorizedWhenInUse else { return false }
        return await withCheckedContinuation { continuation in
            alwaysContinuations.append(continuation)
            manager.requestAlwaysAuthorization()
            // iOS asks for the upgrade to "Immer" only once; afterwards no callback comes.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                self.resolveAlways()
            }
        }
    }

    private func resolveAlways() {
        let waiting = alwaysContinuations
        alwaysContinuations = []
        waiting.forEach { $0.resume(returning: manager.authorizationStatus == .authorizedAlways) }
    }

    func currentLocation() async -> GeoPoint? {
        guard authorization == .authorized else { return nil }
        // A fix from the last two minutes is good enough for distances between stores.
        if let lastLocation, Date.now.timeIntervalSince(lastLocation.date) < 120 { return lastLocation.point }
        return await withCheckedContinuation { continuation in
            locationContinuations.append(continuation)
            if locationContinuations.count == 1 { manager.requestLocation() }
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = Self.map(manager.authorizationStatus)
        guard status != .notDetermined else { return }
        Task { @MainActor in
            self.resolveAlways()
            let waiting = self.authorizationContinuations
            self.authorizationContinuations = []
            waiting.forEach { $0.resume(returning: status) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Task { @MainActor in
            self.lastLocation = (point, .now)
            self.resolveLocation(point)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in self.resolveLocation(nil) }
    }

    private func resolveLocation(_ point: GeoPoint?) {
        let waiting = locationContinuations
        locationContinuations = []
        waiting.forEach { $0.resume(returning: point) }
    }

    private nonisolated static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        default: .denied
        }
    }
}
