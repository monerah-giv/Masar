import XCTest
@testable import Masar

final class AdsTests: XCTestCase {
    private func camp(_ id: String, stations: [String] = ["qasrhokm"], start: String = "2026-10-01",
                      end: String = "2026-12-31", weight: Double = 1, url: String? = nil,
                      paidUntil: String? = "2026-12-31", status: String? = "active") -> AdCampaign {
        AdCampaign(id: id, name: ["ar": "اسم", "en": "Name"], category: "cafe", title: ["ar": "عرض"], body: nil,
                   url: url, phone: nil, lat: nil, lng: nil, start: start, end: end, stations: stations, weight: weight,
                   paidUntil: paidUntil, status: status)
    }

    func testUnpaidAndSuspendedAdsAreHidden() {
        let all = [camp("paid"), camp("oct", paidUntil: "2026-10-31"), camp("never", paidUntil: nil),
                   camp("off", status: "suspended")]
        XCTAssertEqual(Set(AdsService.rotate(all, at: "qasrhokm", day: "2026-10-31", limit: 9).map(\.id)), ["paid", "oct"])
        XCTAssertEqual(AdsService.rotate(all, at: "qasrhokm", day: "2026-11-01", limit: 9).map(\.id), ["paid"])
        XCTAssertEqual(Set(AdsService.rotate(all, at: "qasrhokm", day: "2026-11-02", limit: 9, graceDays: 2).map(\.id)), ["paid", "oct"])
        XCTAssertEqual(AdsService.addDays("2026-12-31", 1), "2027-01-01")
        XCTAssertEqual(AdsService.addDays("2028-02-28", 1), "2028-02-29")
    }

    /// The web app computes the same values (tests/ads.test.mjs), so both apps rotate ads identically.
    func testHashMatchesTheWebApp() {
        XCTAssertEqual(AdsService.hash01("demo-qasr-1|qasrhokm|2026-10-20"), 0.95095232955645770, accuracy: 1e-15)
        XCTAssertEqual(AdsService.hash01("مقهى|kafd|2027-01-01"), 0.57876523805316538, accuracy: 1e-15)
    }

    func testOnlyRunningCampaignsAtTheStationAreShown() {
        let all = [camp("a"), camp("b", start: "2026-10-10", end: "2026-11-30"), camp("c", stations: ["malaz"])]
        XCTAssertEqual(AdsService.rotate(all, at: "qasrhokm", day: "2026-09-30", limit: 5).count, 0)
        XCTAssertEqual(AdsService.rotate(all, at: "qasrhokm", day: "2026-10-05", limit: 5).map(\.id), ["a"])
        XCTAssertEqual(AdsService.rotate(all, at: "qasrhokm", day: "2026-10-20", limit: 5).count, 2)
        XCTAssertEqual(AdsService.rotate(all, at: "malaz", day: "2026-10-20", limit: 5).map(\.id), ["c"])
        XCTAssertEqual(AdsService.rotate(all, at: "kafd", day: "2026-10-20", limit: 5).count, 0)
    }

    func testRotationIsStableForADay() {
        let all = [camp("a"), camp("b", weight: 2)]
        let first = AdsService.rotate(all, at: "qasrhokm", day: "2026-10-20", limit: 1).first?.id
        for _ in 0..<5 { XCTAssertEqual(AdsService.rotate(all, at: "qasrhokm", day: "2026-10-20", limit: 1).first?.id, first) }
    }

    func testTrackedLinkKeepsTheAdvertisersOwnTags() {
        let u = AdsService.trackedURL(camp("x", url: "https://example.com/menu?utm_source=own"), station: "kafd")!
        let items = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "utm_source" }?.value, "own")
        XCTAssertEqual(items.first { $0.name == "utm_campaign" }?.value, "x")
        XCTAssertEqual(items.first { $0.name == "utm_content" }?.value, "kafd")
    }

    /// The same numbers as tests/intent.test.mjs, so both apps rank ads identically.
    func testRelevanceMatchesTheWebApp() {
        let rules = AdRules(momentCats: ["morning": ["cafe"]], weekendCats: ["fun"], placeCats: ["work": ["cafe"]],
                            kindOf: ["qasrhokm": ["heritage"]], kindCats: ["heritage": ["shop"]])
        let cafe = camp("cafe")
        var grill = camp("grill"); grill.moments = ["evening", "night"]
        let morning = AdContext(moment: "morning", weekend: false, place: nil, kinds: ["heritage"])
        let evening = AdContext(moment: "evening", weekend: false, place: nil, kinds: ["heritage"])
        XCTAssertEqual(AdsService.relevance(cafe, context: morning, rules: rules, taste: AdTaste()).m, 1.3, accuracy: 1e-9)
        XCTAssertEqual(AdsService.relevance(grill, context: morning, rules: rules, taste: AdTaste()).m, 0.7, accuracy: 1e-9)
        XCTAssertEqual(AdsService.relevance(grill, context: evening, rules: rules, taste: AdTaste()).m, 1.6, accuracy: 1e-9)
        XCTAssertEqual(AdsService.relevance(grill, context: evening, rules: rules, taste: AdTaste()).why, ["time"])
        XCTAssertEqual(AdsService.relevance(cafe, context: AdContext(moment: "midday", weekend: false, place: "work", kinds: []),
                                            rules: rules, taste: AdTaste()).m, 1.2, accuracy: 1e-9)
        // Bounded whatever the rider did, and switched off on request.
        let fan = AdTaste(on: true, cats: ["cafe": 3], hide: [])
        let all = AdContext(moment: "morning", weekend: true, place: "work", kinds: ["heritage"])
        XCTAssertLessThanOrEqual(AdsService.relevance(cafe, context: all, rules: rules, taste: fan).m, 3)
        XCTAssertEqual(AdsService.relevance(cafe, context: evening, rules: rules, taste: fan).m, 1.5, accuracy: 1e-9)
        XCTAssertEqual(AdsService.relevance(cafe, context: evening, rules: rules, taste: AdTaste(on: false, cats: ["cafe": 3], hide: [])).m, 1, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(AdsService.relevance(grill, context: morning, rules: rules, taste: AdTaste(on: true, cats: ["cafe": -3], hide: [])).m, 0.5)
    }

    func testMomentsAndHiddenAds() {
        XCTAssertEqual([0, 299, 300, 659, 660, 899, 900, 1079, 1080, 1319, 1320, 1439].map(AdsService.moment(minutes:)),
                       ["night", "night", "morning", "morning", "midday", "midday", "afternoon", "afternoon", "evening", "evening", "night", "night"])
        let all = [camp("a"), camp("b")]
        let cx = AdContext(moment: "midday", weekend: false, place: nil, kinds: [])
        let hid = AdTaste(on: true, cats: [:], hide: ["b"])
        XCTAssertEqual(AdsService.rotate(all, at: "qasrhokm", day: "2026-10-20", limit: 5, context: cx, taste: hid).map(\.id), ["a"])
        XCTAssertEqual(AdsService.rotate(all, at: "qasrhokm", day: "2026-10-20", limit: 5, taste: hid).count, 2)   // the booking itself is untouched
    }

    func testRiyadhCalendarDay() {
        // 22:30 UTC on 31 Dec is already 1 Jan in Riyadh (UTC+3).
        let d = ISO8601DateFormatter().date(from: "2026-12-31T22:30:00Z")!
        XCTAssertEqual(AdsService.today(d), "2027-01-01")
    }

    @MainActor
    func testBundledFeedLoadsAndPointsToTheSite() {
        let s = AdsService(bundle: Bundle(for: AdsService.self))
        XCTAssertGreaterThan(s.feed.slotsPerStation, 0)
        XCTAssertEqual(s.advertiseURL(station: "kafd")?.absoluteString.hasSuffix("#advertise:kafd"), true)
    }
}
