import Foundation
import CoreLocation

enum RoutePreference: String, CaseIterable, Identifiable {
    case fastest, fewestTransfers
    var id: String { rawValue }
}

struct JourneyLeg: Hashable {
    let line: Int
    let stops: [String]
    let toward: String
    let minutes: Double
    /// Another line that serves every stop of this leg (Yellow/Purple shared section).
    let alsoLine: Int?
    var rideCount: Int { stops.count - 1 }
    var boarding: String { stops[0] }
    var alighting: String { stops[stops.count - 1] }
}

struct Journey: Hashable {
    let legs: [JourneyLeg]
    let totalMinutes: Double
    var transfers: Int { max(0, legs.count - 1) }
    var rideCount: Int { legs.reduce(0) { $0 + $1.rideCount } }
}

/// Where a trip starts or ends.
enum RoutePoint {
    case station(String)
    case location(CLLocation)
}

/// A door-to-door trip: optional walk to a station, the metro journey, optional walk to the place.
struct DoorTrip: Hashable {
    /// Walk from the user's point to the boarding station (nil when the trip starts at a station).
    let access: NearbyStation?
    /// nil when no ride is needed (both ends use the same station, or walking all the way is quicker).
    let journey: Journey?
    /// Walk from the last station to the destination point (nil when the trip ends at a station).
    let egress: NearbyStation?
    /// Set when walking the whole way beats taking the metro.
    let walkOnlyMinutes: Double?

    var totalMinutes: Double {
        walkOnlyMinutes ?? ((access?.walkMinutes ?? 0) + (journey?.totalMinutes ?? 0) + (egress?.walkMinutes ?? 0))
    }
    var transfers: Int { journey?.transfers ?? 0 }
    var walkMinutes: Double { walkOnlyMinutes ?? ((access?.walkMinutes ?? 0) + (egress?.walkMinutes ?? 0)) }
    var boardingID: String? { journey?.legs.first?.boarding ?? access?.id }
}

/// Routing over (station, line) states. Riding costs the line's hop time; changing line costs
/// `transferMin` and counts one transfer.
///
/// One multi-source search answers door-to-door questions in a single pass: every station within
/// walking reach of the start is seeded with its walking time, and every station near the end adds
/// its walking time on arrival. A binary heap keeps it O(E log V).
struct RoutePlanner {
    let network: MetroNetwork

    /// Farthest walk considered to reach or leave a station.
    static let maxWalkMeters: Double = 2500
    /// Stations tried at each end of a door-to-door trip.
    static let candidates = 4

    struct Node: Hashable { let station: String; let line: Int }
    private struct Cost { var time: Double; var transfers: Int }

    // MARK: public API

    func plan(from: String, to: String, preference: RoutePreference) -> Journey? {
        guard from != to else { return nil }
        guard let path = search(sources: [from: 0], sinks: [to: 0], preference: preference) else { return nil }
        let j = build(path)
        return j.legs.isEmpty ? nil : j
    }

    func plan(fromLocation location: CLLocation, to destination: String, preference: RoutePreference) -> DoorTrip? {
        plan(.location(location), .station(destination), preference: preference)
    }

    func plan(_ origin: RoutePoint, _ destination: RoutePoint, preference: RoutePreference) -> DoorTrip? {
        let (sources, accessBy) = seeds(origin)
        let (sinks, egressBy) = seeds(destination)
        guard !sources.isEmpty, !sinks.isEmpty else { return nil }
        if case .station(let a) = origin, case .station(let b) = destination, a == b { return nil }

        var trip: DoorTrip?
        if let path = search(sources: sources, sinks: sinks, preference: preference),
           let first = path.first, let last = path.last {
            let j = build(path)
            trip = DoorTrip(access: accessBy[first.station], journey: j.legs.isEmpty ? nil : j,
                            egress: egressBy[last.station], walkOnlyMinutes: nil)
        }

        // Between two points that are close, walking the whole way may simply be quicker.
        if case .location(let a) = origin, case .location(let b) = destination {
            let meters = a.distance(from: b)
            let minutes = meters * 1.25 / 80
            if meters <= Self.maxWalkMeters, minutes <= (trip?.totalMinutes ?? .infinity) {
                return DoorTrip(access: nil, journey: nil, egress: nil, walkOnlyMinutes: minutes)
            }
        }
        return trip
    }

    // MARK: search

    private func seeds(_ p: RoutePoint) -> ([String: Double], [String: NearbyStation]) {
        switch p {
        case .station(let id):
            return network.linesAt[id] == nil ? ([:], [:]) : ([id: 0], [:])
        case .location(let loc):
            let near = network.nearest(to: loc, count: Self.candidates)
            let reach = near.filter { $0.meters <= Self.maxWalkMeters }
            let use = reach.isEmpty ? Array(near.prefix(1)) : reach
            return (Dictionary(uniqueKeysWithValues: use.map { ($0.id, $0.walkMinutes) }),
                    Dictionary(uniqueKeysWithValues: use.map { ($0.id, $0) }))
        }
    }

    private enum Item { case node(Node), arrive(Node) }
    private struct Entry: Comparable {
        let score: Double, seq: Int, item: Item, cost: Cost
        static func < (a: Entry, b: Entry) -> Bool { (a.score, a.seq) < (b.score, b.seq) }
        static func == (a: Entry, b: Entry) -> Bool { a.score == b.score && a.seq == b.seq }
    }

    /// Returns the (station, line) path of the best trip from any source to any sink.
    func search(sources: [String: Double], sinks: [String: Double], preference: RoutePreference) -> [Node]? {
        func score(_ c: Cost) -> Double {
            preference == .fastest ? c.time + Double(c.transfers) * 0.001
                                   : Double(c.transfers) * 10_000 + c.time
        }
        var heap = MinHeap<Entry>()
        var seq = 0
        var best: [Node: Double] = [:]
        var prev: [Node: Node] = [:]
        var settled = Set<Node>()

        func push(_ item: Item, _ c: Cost) { seq += 1; heap.push(Entry(score: score(c), seq: seq, item: item, cost: c)) }

        for (id, walk) in sources {
            for line in network.linesAt[id] ?? [] {
                let n = Node(station: id, line: line), c = Cost(time: walk, transfers: 0)
                if score(c) < best[n, default: .infinity] { best[n] = score(c); push(.node(n), c) }
            }
        }

        while let e = heap.pop() {
            switch e.item {
            case .arrive(let n):
                var path = [n], key = n
                while let p = prev[key] { path.append(p); key = p }
                return Array(path.reversed())
            case .node(let n):
                guard !settled.contains(n) else { continue }
                settled.insert(n)
                if let walkOut = sinks[n.station] {
                    push(.arrive(n), Cost(time: e.cost.time + walkOut, transfers: e.cost.transfers))
                }
                guard let line = network.lineByID[n.line], let i = line.stations.firstIndex(of: n.station) else { continue }
                let hop = network.hopMinutes[line.id] ?? 2
                var next: [(Node, Double, Int)] = []
                if i > 0 { next.append((Node(station: line.stations[i - 1], line: line.id), hop, 0)) }
                if i < line.stations.count - 1 { next.append((Node(station: line.stations[i + 1], line: line.id), hop, 0)) }
                for other in network.linesAt[n.station] ?? [] where other != line.id {
                    next.append((Node(station: n.station, line: other), network.params.transferMin, 1))
                }
                for (m, dt, dx) in next where !settled.contains(m) {
                    let c = Cost(time: e.cost.time + dt, transfers: e.cost.transfers + dx)
                    if score(c) < best[m, default: .infinity] { best[m] = score(c); prev[m] = n; push(.node(m), c) }
                }
            }
        }
        return nil
    }

    private func build(_ path: [Node]) -> Journey {
        var groups: [(line: Int, stops: [String])] = []
        for node in path {
            if let last = groups.last, last.line == node.line {
                groups[groups.count - 1].stops.append(node.station)
            } else {
                groups.append((node.line, [node.station]))
            }
        }
        let legs: [JourneyLeg] = groups.filter { $0.stops.count > 1 }.compactMap { g in
            guard let line = network.lineByID[g.line],
                  let a = line.stations.firstIndex(of: g.stops.first!),
                  let b = line.stations.firstIndex(of: g.stops.last!) else { return nil }
            let toward = b > a ? line.stations.last! : line.stations.first!
            let other = g.line == 4 ? 6 : (g.line == 6 ? 4 : nil)
            let also = other.flatMap { o in g.stops.allSatisfy { network.linesAt[$0]?.contains(o) == true } ? o : nil }
            return JourneyLeg(line: g.line, stops: g.stops, toward: toward,
                              minutes: Double(g.stops.count - 1) * (network.hopMinutes[g.line] ?? 2),
                              alsoLine: also)
        }
        let ride = legs.reduce(0) { $0 + $1.minutes }
        let total = legs.isEmpty ? 0
            : network.params.initialWaitMin + ride + Double(max(0, legs.count - 1)) * network.params.transferMin
        return Journey(legs: legs, totalMinutes: total)
    }
}

/// Minimal binary min-heap.
struct MinHeap<T: Comparable> {
    private var a: [T] = []
    var isEmpty: Bool { a.isEmpty }

    mutating func push(_ x: T) {
        a.append(x)
        var i = a.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            guard a[i] < a[p] else { break }
            a.swapAt(i, p); i = p
        }
    }

    mutating func pop() -> T? {
        guard !a.isEmpty else { return nil }
        a.swapAt(0, a.count - 1)
        let top = a.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < a.count, a[l] < a[m] { m = l }
            if r < a.count, a[r] < a[m] { m = r }
            if m == i { break }
            a.swapAt(i, m); i = m
        }
        return top
    }
}
