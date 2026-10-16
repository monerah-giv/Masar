import Foundation
import MapKit
import UIKit

/// Hand-off to Apple Maps or Google Maps for the walk to (or from) a station.
enum MapsLink {
    /// Walking directions in Apple Maps from the user's current location.
    @MainActor
    static func appleWalk(to station: Station, at c: CLLocationCoordinate2D) {
        appleWalk(from: nil, fromName: nil, to: c, toName: L10n.stationName(station))
    }

    /// Walking directions in Apple Maps between two points; a nil origin means "where I am now".
    @MainActor
    static func appleWalk(from: CLLocationCoordinate2D?, fromName: String?, to: CLLocationCoordinate2D, toName: String) {
        let dst = MKMapItem(placemark: MKPlacemark(coordinate: to))
        dst.name = toName
        let src: MKMapItem
        if let from {
            src = MKMapItem(placemark: MKPlacemark(coordinate: from))
            src.name = fromName
        } else {
            src = MKMapItem.forCurrentLocation()
        }
        MKMapItem.openMaps(with: [src, dst], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    /// Google Maps walking directions; with no origin Google Maps starts from the user's location.
    /// The https link opens the Google Maps app when it is installed, the website otherwise.
    static func googleWalk(from: CLLocationCoordinate2D? = nil, to c: CLLocationCoordinate2D) -> URL {
        var u = URLComponents(string: "https://www.google.com/maps/dir/")!
        var q = [URLQueryItem(name: "api", value: "1")]
        if let from { q.append(URLQueryItem(name: "origin", value: "\(from.latitude),\(from.longitude)")) }
        q.append(URLQueryItem(name: "destination", value: "\(c.latitude),\(c.longitude)"))
        q.append(URLQueryItem(name: "travelmode", value: "walking"))
        u.queryItems = q
        return u.url!
    }
}

/// Snaps estimated station positions to the matching metro-station place on Apple Maps, when Apple Maps has one.
/// Runs only for the few stations near the user, so it stays well inside MapKit's search limits.
enum StationRefiner {
    @MainActor
    static func refine(_ stations: [Station], in network: MetroNetwork) async {
        for st in stations where network.isApproximate(st.id) {
            guard let estimate = network.coordinate(of: st.id) else { continue }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "\(st.en) Metro Station"
            request.region = MKCoordinateRegion(center: estimate, latitudinalMeters: 3000, longitudinalMeters: 3000)
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
            guard let items = try? await MKLocalSearch(request: request).start().mapItems else { continue }

            let wanted = [StationSearch.normalize(st.en), StationSearch.normalize(st.ar)]
                .map { Set($0.split(separator: " ").map(String.init)) }
            let here = CLLocation(latitude: estimate.latitude, longitude: estimate.longitude)
            let match = items
                .filter { item in
                    let words = Set(StationSearch.normalize(item.name ?? "").split(separator: " ").map(String.init))
                    return wanted.contains { !$0.isEmpty && $0.isSubset(of: words) }
                }
                .min { here.distance(from: $0.placemark.location ?? here) < here.distance(from: $1.placemark.location ?? here) }
            if let loc = match?.placemark.location, here.distance(from: loc) < 1500 {
                network.setRefined(st.id, loc.coordinate)
            }
        }
    }
}
