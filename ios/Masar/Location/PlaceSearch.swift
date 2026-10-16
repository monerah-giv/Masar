import Foundation
import MapKit
import Observation

/// Type-ahead search for any place in Riyadh (malls, hospitals, universities, addresses) on Apple Maps.
/// MKLocalSearchCompleter throttles itself, so it is safe to feed every keystroke.
@MainActor
@Observable
final class PlaceSearch: NSObject {
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var resolving = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    static let riyadh = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 24.72, longitude: 46.70),
                                           latitudinalMeters: 70_000, longitudinalMeters: 70_000)

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        completer.region = Self.riyadh
    }

    func update(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.count < 2 {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = q
        }
    }

    /// Turns a suggestion into a point on the map.
    func resolve(_ completion: MKLocalSearchCompletion) async -> PlacePoint? {
        resolving = true
        defer { resolving = false }
        let request = MKLocalSearch.Request(completion: completion)
        request.region = Self.riyadh
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first,
              let c = item.placemark.location?.coordinate else { return nil }
        return PlacePoint(name: item.name ?? completion.title, subtitle: completion.subtitle,
                          lat: c.latitude, lng: c.longitude)
    }
}

extension PlaceSearch: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let top = Array(completer.results.prefix(6))
        Task { @MainActor in self.results = top }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
