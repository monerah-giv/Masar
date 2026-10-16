import Foundation
import Observation

enum FareClass: String, CaseIterable, Identifiable {
    case standard, first
    var id: String { rawValue }
}

struct Ticket: Codable, Identifiable, Hashable {
    let id: String
    let hours: Int?
    let standard: Double
    let first: Double?
    let studentsOnly: Bool?
}

struct FareFile: Codable {
    struct Discount: Codable { let rate: Double; let appliesTo: [String]; let `class`: String }
    struct Hours: Codable {
        struct Open: Codable { let `default`: String; let friday: String }
        let open: Open
        let close: String
        let timeZone: String
    }
    struct Darb: Codable { let appStore: String }
    let currency: String
    let asOf: String
    let tickets: [Ticket]
    let discount: Discount
    let hours: Hours
    let darb: Darb
}

struct TicketPrice: Hashable { let base: Double; let now: Double; let discounted: Bool }

struct PassOption: Identifiable, Hashable {
    let id: String          // ticket id, also the localization key
    let monthly: Double
}

@Observable
final class FareBook {
    let file: FareFile
    let hours: ServiceHours

    init(file: FareFile) {
        self.file = file
        self.hours = ServiceHours(file.hours)
    }

    static func load(bundle: Bundle = .main) -> FareBook {
        guard let url = bundle.url(forResource: "fares", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(FareFile.self, from: data) else {
            fatalError("fares.json is missing from the app bundle or invalid. Run tools/build.py.")
        }
        return FareBook(file: file)
    }

    var darbURL: URL? { URL(string: file.darb.appStore) }

    func price(_ id: String, fareClass: FareClass, discountEligible: Bool) -> TicketPrice? {
        guard let t = file.tickets.first(where: { $0.id == id }) else { return nil }
        guard let base = fareClass == .first ? t.first : t.standard else { return nil }
        let applies = discountEligible
            && fareClass.rawValue == file.discount.`class`
            && file.discount.appliesTo.contains(id)
        return TicketPrice(base: base, now: applies ? base * (1 - file.discount.rate) : base, discounted: applies)
    }

    /// Monthly cost of each way to pay for `tripsPerWeek` one-way trips. One 2-hour ticket per trip.
    func monthlyOptions(tripsPerWeek: Int, fareClass: FareClass, discountEligible: Bool) -> [PassOption] {
        let weeks = 52.0 / 12.0
        var out: [PassOption] = []
        func p(_ id: String) -> Double? { price(id, fareClass: fareClass, discountEligible: discountEligible)?.now }
        if let v = p("t_2h") { out.append(PassOption(id: "t_2h", monthly: Double(tripsPerWeek) * weeks * v)) }
        if let v = p("t_7d") { out.append(PassOption(id: "t_7d", monthly: weeks * v)) }
        if let v = p("t_30d") { out.append(PassOption(id: "t_30d", monthly: v)) }
        if let v = p("t_year") { out.append(PassOption(id: "t_year", monthly: v / 12)) }
        return out
    }
}

/// Operating hours in Riyadh time. Friday opens later.
struct ServiceHours {
    let openDefault: Int
    let openFriday: Int
    let close: Int
    let timeZone: TimeZone

    init(_ h: FareFile.Hours) {
        func minutes(_ s: String) -> Int {
            let p = s.split(separator: ":").compactMap { Int($0) }
            return (p.first ?? 0) * 60 + (p.count > 1 ? p[1] : 0)
        }
        openDefault = minutes(h.open.`default`)
        openFriday = minutes(h.open.friday)
        close = minutes(h.close)
        timeZone = TimeZone(identifier: h.timeZone) ?? .current
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    private func parts(_ date: Date) -> (minute: Int, friday: Bool) {
        let c = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        return ((c.hour ?? 0) * 60 + (c.minute ?? 0), c.weekday == 6)   // weekday: 1 = Sunday … 6 = Friday
    }

    func isOpen(at date: Date) -> Bool {
        let p = parts(date)
        return p.minute >= (p.friday ? openFriday : openDefault) && p.minute < close
    }

    /// Opening time on the calendar day of `date` (Riyadh time).
    func opening(on date: Date) -> Date {
        let m = parts(date).friday ? openFriday : openDefault
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: date) ?? date
    }

    func format(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
