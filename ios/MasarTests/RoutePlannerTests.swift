import XCTest
import CoreLocation
@testable import Masar

final class RoutePlannerTests: XCTestCase {
    private var network: MetroNetwork!
    private var planner: RoutePlanner!

    override func setUp() {
        network = MetroNetwork.load(bundle: Bundle(for: MetroNetwork.self))
        planner = RoutePlanner(network: network)
    }

    func testNetworkShape() {
        XCTAssertEqual(network.lines.count, 6)
        XCTAssertEqual(network.lines.map(\.stations.count), [25, 15, 22, 9, 12, 11])
        XCTAssertEqual(network.linesAt["kafd"], [1, 4, 6])
    }

    func testAirportToQasrAlHokmChangesOnceAtKAFD() throws {
        let j = try XCTUnwrap(planner.plan(from: "t12", to: "qasrhokm", preference: .fastest))
        XCTAssertEqual(j.legs.map(\.line), [4, 1])
        XCTAssertEqual(j.legs.first?.alighting, "kafd")
        XCTAssertEqual(j.legs.first?.toward, "kafd")
        XCTAssertEqual(j.legs.last?.toward, "darbaida")
    }

    func testFewestTransfersPrefersFewerChanges() throws {
        let fast = try XCTUnwrap(planner.plan(from: "jeddahrd", to: "kfstadium", preference: .fastest))
        let few = try XCTUnwrap(planner.plan(from: "jeddahrd", to: "kfstadium", preference: .fewestTransfers))
        XCTAssertLessThanOrEqual(few.transfers, fast.transfers)
        XCTAssertLessThanOrEqual(fast.totalMinutes, few.totalMinutes)
    }

    func testSharedYellowPurpleSectionIsFlagged() throws {
        let j = try XCTUnwrap(planner.plan(from: "rabi", to: "sabic", preference: .fastest))
        XCTAssertEqual(j.transfers, 0)
        XCTAssertNotNil(j.legs.first?.alsoLine)
    }

    func testSameStationHasNoJourney() {
        XCTAssertNil(planner.plan(from: "stc", to: "stc", preference: .fastest))
    }

    func testEveryPairIsReachable() {
        let ids = network.stations.map(\.id)
        for a in stride(from: 0, to: ids.count, by: 3).map({ ids[$0] }) {   // every third origin keeps the test quick
            for b in ids where a != b {
                XCTAssertNotNil(planner.plan(from: a, to: b, preference: .fastest), "\(a) → \(b)")
            }
        }
    }

    func testEveryStationHasCoordinatesInsideRiyadh() {
        for st in network.stations {
            let c = try? XCTUnwrap(network.coordinate(of: st.id))
            XCTAssertNotNil(c, st.id)
            XCTAssert((24.4...25.1).contains(c?.latitude ?? 0) && (46.4...47.1).contains(c?.longitude ?? 0), st.id)
        }
    }

    func testNearestStationToQasrAlHokmIsItself() throws {
        let here = CLLocation(latitude: 24.6287, longitude: 46.7162)
        let near = network.nearest(to: here, count: 3)
        XCTAssertEqual(near.first?.id, "qasrhokm")
        XCTAssertLessThan(try XCTUnwrap(near.first).meters, 50)
        XCTAssertEqual(near.count, 3)
        XCTAssertTrue(zip(near, near.dropFirst()).allSatisfy { $0.meters <= $1.meters })
    }

    func testDoorTripFromLocationWalksThenRides() throws {
        // Standing at Qasr Al Hokm, going to the airport: a tiny walk, then the change at KAFD.
        let here = CLLocation(latitude: 24.6290, longitude: 46.7165)
        let trip = try XCTUnwrap(planner.plan(fromLocation: here, to: "t12", preference: .fastest))
        XCTAssertLessThan(try XCTUnwrap(trip.access).meters, 300)
        XCTAssertEqual(trip.journey?.legs.last?.line, 4)
        XCTAssertNil(trip.egress)
        XCTAssertEqual(trip.totalMinutes, (trip.access?.walkMinutes ?? 0) + (trip.journey?.totalMinutes ?? 0), accuracy: 0.001)
    }

    func testOnePassEqualsTryingEveryStationPair() throws {
        // The seeded single search must find exactly the best of all (access, egress) combinations.
        let a = CLLocation(latitude: 24.6990, longitude: 46.6820)
        let b = CLLocation(latitude: 24.7880, longitude: 46.8300)
        for pref in RoutePreference.allCases {
            let fast = try XCTUnwrap(planner.plan(.location(a), .location(b), preference: pref))
            var bruteBest = Double.infinity, bruteBestX = Int.max
            for s in network.nearest(to: a, count: RoutePlanner.candidates) where s.meters <= RoutePlanner.maxWalkMeters {
                for e in network.nearest(to: b, count: RoutePlanner.candidates) where e.meters <= RoutePlanner.maxWalkMeters {
                    let ride = s.id == e.id ? nil : planner.plan(from: s.id, to: e.id, preference: pref)
                    if s.id != e.id, ride == nil { continue }
                    let total = s.walkMinutes + (ride?.totalMinutes ?? 0) + e.walkMinutes
                    let x = ride?.transfers ?? 0
                    let better = pref == .fastest ? total < bruteBest : (x, total) < (bruteBestX, bruteBest)
                    if better { bruteBest = total; bruteBestX = x }
                }
            }
            XCTAssertEqual(fast.totalMinutes, bruteBest, accuracy: 0.01, "\(pref)")
        }
    }

    func testPlaceToPlaceWalksAtBothEnds() throws {
        let a = CLLocation(latitude: 24.6990, longitude: 46.6820)
        let b = CLLocation(latitude: 24.7880, longitude: 46.8300)
        let trip = try XCTUnwrap(planner.plan(.location(a), .location(b), preference: .fastest))
        XCTAssertNotNil(trip.access)
        XCTAssertNotNil(trip.egress)
        XCTAssertNotNil(trip.journey)
    }

    func testShortHopIsWalkOnly() throws {
        let a = CLLocation(latitude: 24.6990, longitude: 46.6820)
        let b = CLLocation(latitude: 24.7010, longitude: 46.6840)   // ~300 m away
        let trip = try XCTUnwrap(planner.plan(.location(a), .location(b), preference: .fastest))
        XCTAssertNotNil(trip.walkOnlyMinutes)
        XCTAssertNil(trip.journey)
    }

    func testDoorTripToTheNearestStationIsWalkOnly() throws {
        let here = CLLocation(latitude: 24.6290, longitude: 46.7165)
        let trip = try XCTUnwrap(planner.plan(fromLocation: here, to: "qasrhokm", preference: .fastest))
        XCTAssertNil(trip.journey)
        XCTAssertEqual(trip.access?.id, "qasrhokm")
    }

    func testMinHeapOrders() {
        var h = MinHeap<Int>()
        [5, 1, 4, 1, 9, 2, 6].forEach { h.push($0) }
        var out: [Int] = []
        while let x = h.pop() { out.append(x) }
        XCTAssertEqual(out, [1, 1, 2, 4, 5, 6, 9])
    }

    func testWalkingTimeUsesStreetFactor() {
        let n = NearbyStation(station: network.stations[0], meters: 800, approximate: true)
        XCTAssertEqual(n.walkMinutes, 12.5, accuracy: 0.01)
    }

    func testSearchMatchesArabicWithoutHamza() {
        let hits = StationSearch.filter("الاندلس", in: network).map(\.id)
        XCTAssertTrue(hits.contains("andalus"))
        XCTAssertTrue(StationSearch.filter("malaz", in: network).map(\.id).contains("malaz"))
    }
}

final class FareBookTests: XCTestCase {
    func testDiscountAppliesToStandardShortTicketsOnly() throws {
        let fares = FareBook.load(bundle: Bundle(for: FareBook.self))
        XCTAssertEqual(fares.price("t_2h", fareClass: .standard, discountEligible: true)?.now, 2)
        XCTAssertEqual(fares.price("t_2h", fareClass: .first, discountEligible: true)?.now, 10)
        XCTAssertEqual(fares.price("t_year", fareClass: .standard, discountEligible: true)?.now, 1260)
        XCTAssertNil(fares.price("t_sem", fareClass: .first, discountEligible: false))
    }

    func testFridayOpensLater() throws {
        let fares = FareBook.load(bundle: Bundle(for: FareBook.self))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let friday7am = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 7)))
        let saturday6am = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 6)))
        XCTAssertFalse(fares.hours.isOpen(at: friday7am))
        XCTAssertTrue(fares.hours.isOpen(at: saturday6am))
    }
}
