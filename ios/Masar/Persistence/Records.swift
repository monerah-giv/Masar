import Foundation
import SwiftData

// CloudKit-compatible models: every property has a default, no unique constraints,
// no required relationships. Station ids refer to network.json.

enum PlaceKind: String, CaseIterable, Identifiable {
    case home, work, other
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .other: "mappin.circle.fill"
        }
    }
    var labelKey: String { "kind_\(rawValue)" }
}

@Model
final class FavoritePlace {
    var kindRaw: String = PlaceKind.other.rawValue
    var label: String = ""
    var stationID: String = ""
    var createdAt: Date = Date()

    init(kind: PlaceKind, label: String, stationID: String) {
        self.kindRaw = kind.rawValue
        self.label = label
        self.stationID = stationID
    }

    var kind: PlaceKind { PlaceKind(rawValue: kindRaw) ?? .other }
    var displayLabel: String { label.isEmpty ? L10n.t(kind.labelKey) : label }
}

@Model
final class SavedRoute {
    var fromID: String = ""
    var toID: String = ""
    var createdAt: Date = Date()

    init(fromID: String, toID: String) {
        self.fromID = fromID
        self.toID = toID
    }
}

@Model
final class TripRecord {
    var fromID: String = ""
    var toID: String = ""
    var plannedAt: Date = Date()

    init(fromID: String, toID: String) {
        self.fromID = fromID
        self.toID = toID
    }

    static let keep = 12

    /// Adds a trip to the history, moving a repeat to the top and trimming to `keep` entries.
    static func record(from: String, to: String, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<TripRecord>(sortBy: [SortDescriptor(\.plannedAt, order: .reverse)]))) ?? []
        for r in all where r.fromID == from && r.toID == to { context.delete(r) }
        context.insert(TripRecord(fromID: from, toID: to))
        let rest = all.filter { !($0.fromID == from && $0.toID == to) }
        for r in rest.dropFirst(keep - 1) { context.delete(r) }
    }
}
