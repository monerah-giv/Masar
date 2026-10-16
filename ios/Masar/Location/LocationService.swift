import Foundation
import CoreLocation
import Observation

/// One-shot "where am I" with When-In-Use permission. The location never leaves the device.
@MainActor
@Observable
final class LocationService: NSObject {
    enum Status: Equatable { case idle, locating, denied, failed, located }

    private(set) var status: Status = .idle
    private(set) var location: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waiters: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    var isDenied: Bool {
        [.denied, .restricted].contains(manager.authorizationStatus)
    }

    /// Asks for permission the first time, then returns one fresh fix (nil if denied or unavailable).
    func locate() async -> CLLocation? {
        if isDenied { status = .denied; return nil }
        status = .locating
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()   // the fix is requested once permission arrives
        } else {
            manager.requestLocation()
        }
        return await withCheckedContinuation { waiters.append($0) }
    }

    private func finish(_ loc: CLLocation?, _ s: Status) {
        if let loc { location = loc }
        status = s
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: loc) }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        Task { @MainActor in
            guard self.status == .locating else { return }
            switch auth {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.finish(nil, .denied)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.finish(loc, loc == nil ? .failed : .located) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in self.finish(nil, denied ? .denied : .failed) }
    }
}
