import Foundation
import Observation
import CoreLocation

/// A place found on Apple Maps (mall, hospital, address…), used as a trip end.
struct PlacePoint: Codable, Hashable {
    let name: String
    let subtitle: String
    let lat: Double
    let lng: Double
    var location: CLLocation { CLLocation(latitude: lat, longitude: lng) }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// Where a trip starts or ends, as the user chose it.
enum Endpoint: Hashable {
    case station(String)
    case currentLocation
    case place(PlacePoint)
}

/// App-wide navigation and the trip being planned. Station and place choices persist so the app
/// reopens where the person left off; the current location is never stored.
@Observable
final class AppRouter {
    enum Tab: Hashable { case plan, saved, fares, account }

    var tab: Tab = .plan
    private(set) var fromCurrentLocation = false
    private(set) var fromID: String? { didSet { save(fromID, Keys.from) } }
    private(set) var toID: String? { didSet { save(toID, Keys.to) } }
    private(set) var fromPlace: PlacePoint? { didSet { saveJSON(fromPlace, Keys.fromPlace) } }
    private(set) var toPlace: PlacePoint? { didSet { saveJSON(toPlace, Keys.toPlace) } }
    var preference: RoutePreference = .fastest {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: Keys.pref) }
    }

    private enum Keys {
        static let from = "plan.from", to = "plan.to", pref = "plan.preference"
        static let fromPlace = "plan.fromPlace", toPlace = "plan.toPlace"
    }

    init() {
        let d = UserDefaults.standard
        fromID = d.string(forKey: Keys.from) ?? "t12"          // sample: airport T1-2
        toID = d.string(forKey: Keys.to) ?? "qasrhokm"         // sample: Qasr Al Hokm
        fromPlace = Self.loadJSON(Keys.fromPlace)
        toPlace = Self.loadJSON(Keys.toPlace)
        preference = RoutePreference(rawValue: d.string(forKey: Keys.pref) ?? "") ?? .fastest
    }

    var origin: Endpoint? {
        if fromCurrentLocation { return .currentLocation }
        if let fromPlace { return .place(fromPlace) }
        return fromID.map(Endpoint.station)
    }

    var destination: Endpoint? {
        if let toPlace { return .place(toPlace) }
        return toID.map(Endpoint.station)
    }

    func setFrom(_ e: Endpoint) {
        switch e {
        case .station(let id): fromID = id; fromPlace = nil; fromCurrentLocation = false
        case .currentLocation: fromPlace = nil; fromCurrentLocation = true
        case .place(let p): fromPlace = p; fromCurrentLocation = false
        }
    }

    func setTo(_ e: Endpoint) {
        switch e {
        case .station(let id): toID = id; toPlace = nil
        case .place(let p): toPlace = p
        case .currentLocation: break        // a location can't be a destination
        }
    }

    /// Swap the ends. "Current location" can't become a destination, so `boarding` takes its place.
    func swap(boarding: String?) {
        guard let o = origin, let d = destination else { return }
        setFrom(d)
        if case .currentLocation = o {
            if let boarding { setTo(.station(boarding)) }
        } else {
            setTo(o)
        }
    }

    func open(from: String?, to: String?) {
        if let from { setFrom(.station(from)) }
        if let to { setTo(.station(to)) }
        tab = .plan
    }

    private func save(_ v: String?, _ k: String) { UserDefaults.standard.set(v, forKey: k) }
    private func saveJSON(_ v: PlacePoint?, _ k: String) {
        UserDefaults.standard.set(v.flatMap { try? JSONEncoder().encode($0) }, forKey: k)
    }
    private static func loadJSON(_ k: String) -> PlacePoint? {
        UserDefaults.standard.data(forKey: k).flatMap { try? JSONDecoder().decode(PlacePoint.self, from: $0) }
    }
}
