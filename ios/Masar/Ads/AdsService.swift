import Foundation
import Observation

/// One paid placement near one or more stations. Mirrors a campaign in data/ads.json after tools/build.py
/// expanded it (lines and the whole network become explicit station lists).
struct AdCampaign: Codable, Identifiable, Hashable {
    let id: String
    let name: [String: String]
    let category: String
    let title: [String: String]
    let body: [String: String]?
    let url: String?
    let phone: String?
    let lat: Double?
    let lng: Double?
    let start: String
    let end: String
    let stations: [String]
    let weight: Double
    /// Last day the advertiser has paid for; nil = nothing paid yet. Set from the admin page.
    let paidUntil: String?
    /// "active" or "suspended" (cancelled bookings never reach the feed).
    let status: String?

    /// Shown only while running, not suspended and paid for (plus grace days). An unpaid ad
    /// disappears by itself the day after its paid period, even before the feed refreshes.
    func isShown(on day: String, graceDays: Int) -> Bool {
        guard status != "suspended", start <= day, day <= end, let paid = paidUntil else { return false }
        return day <= AdsService.addDays(paid, graceDays)
    }
}

struct AdFeed: Codable {
    let version: Int
    let slotsPerStation: Int
    var graceDays: Int? = 0
    let feedUrl: String?
    let campaigns: [AdCampaign]
}

/// Contextual ads: chosen only by the station a rider is heading to, never by who the rider is.
/// The app ships with a copy of the feed and refreshes it from the website, so new campaigns
/// go live without an App Store release. Nothing about the rider is sent with the request.
@MainActor
@Observable
final class AdsService {
    private(set) var feed: AdFeed

    private static let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ads.json")
    private static let fetchedKey = "ads.fetchedAt"
    private static let refreshEvery: TimeInterval = 6 * 3600

    init(bundle: Bundle = .main) {
        if let data = try? Data(contentsOf: Self.cacheURL), let f = try? JSONDecoder().decode(AdFeed.self, from: data) {
            feed = f
        } else if let url = bundle.url(forResource: "ads", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(AdFeed.self, from: data) {
            feed = f
        } else {
            feed = AdFeed(version: 1, slotsPerStation: 0, feedUrl: nil, campaigns: [])
        }
    }

    /// Fetches the live feed at most every few hours; on any failure the current feed stays.
    func refresh(force: Bool = false) async {
        let last = UserDefaults.standard.double(forKey: Self.fetchedKey)
        guard force || Date().timeIntervalSince1970 - last > Self.refreshEvery,
              let s = feed.feedUrl, let url = URL(string: s) else { return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let f = try? JSONDecoder().decode(AdFeed.self, from: data) else { return }
        feed = f
        try? data.write(to: Self.cacheURL, options: .atomic)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.fetchedKey)
    }

    /// Active campaigns at a station in a weighted rotation that stays the same all day.
    /// Same hash as the web app, so a rider sees the same ad on both.
    func ads(at station: String, day: String = AdsService.today(), limit: Int = 1) -> [AdCampaign] {
        Self.rotate(feed.campaigns, at: station, day: day, limit: limit, graceDays: feed.graceDays ?? 0)
    }

    func freeSlots(at station: String, day: String = AdsService.today()) -> Int {
        let used = feed.campaigns.filter { $0.stations.contains(station) && $0.start <= day && day <= $0.end }.count
        return max(0, feed.slotsPerStation - used)
    }

    /// The website's «أعلن معنا» form, opened on a station when one is given.
    func advertiseURL(station: String?) -> URL? {
        guard let s = feed.feedUrl, s.hasSuffix("ads.json") else { return nil }
        return URL(string: String(s.dropLast("ads.json".count)) + "#advertise" + (station.map { ":" + $0 } ?? ""))
    }

    // MARK: pure helpers (unit-tested)

    nonisolated static func rotate(_ all: [AdCampaign], at station: String, day: String, limit: Int, graceDays: Int = 0) -> [AdCampaign] {
        all.filter { $0.stations.contains(station) && $0.isShown(on: day, graceDays: graceDays) }
            .map { (c: $0, k: -log(hash01("\($0.id)|\(station)|\(day)")) / $0.weight) }
            .sorted { $0.k < $1.k }
            .prefix(limit)
            .map(\.c)
    }

    /// FNV-1a over UTF-16 code units, mapped into (0, 1).
    nonisolated static func hash01(_ s: String) -> Double {
        var h: UInt32 = 2_166_136_261
        for u in s.utf16 { h ^= UInt32(u); h = h &* 16_777_619 }
        return (Double(h) + 0.5) / 4_294_967_296
    }

    nonisolated static func addDays(_ iso: String, _ n: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard n != 0, let d = f.date(from: iso), let r = cal.date(byAdding: .day, value: n, to: d) else { return iso }
        return f.string(from: r)
    }

    /// Today's date in Riyadh as YYYY-MM-DD (campaign dates are Riyadh calendar days).
    nonisolated static func today(_ now: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Riyadh")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }

    /// The text in the app's language, else English, else Arabic, else whatever the advertiser gave.
    nonisolated static func localized(_ d: [String: String]?) -> String {
        guard let d, !d.isEmpty else { return "" }
        let pref = Bundle.main.preferredLocalizations.first ?? "en"
        let code = pref.hasPrefix("zh") ? "zh" : String(pref.prefix { $0 != "-" && $0 != "_" })
        return d[code] ?? d["en"] ?? d["ar"] ?? d.values.sorted().first ?? ""
    }

    /// The advertiser's link with campaign tags, so they can count visits in their own analytics.
    nonisolated static func trackedURL(_ c: AdCampaign, station: String) -> URL? {
        guard let s = c.url, var parts = URLComponents(string: s) else { return nil }
        var items = parts.queryItems ?? []
        for (k, v) in [("utm_source", "masar"), ("utm_medium", "app"), ("utm_campaign", c.id), ("utm_content", station)]
            where !items.contains(where: { $0.name == k }) {
            items.append(URLQueryItem(name: k, value: v))
        }
        parts.queryItems = items
        return parts.url
    }
}
