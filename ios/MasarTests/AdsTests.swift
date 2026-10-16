import XCTest
@testable import Masar

final class AdsTests: XCTestCase {
    private func camp(_ id: String, stations: [String] = ["qasrhokm"], start: String = "2026-10-01",
                      end: String = "2026-12-31", weight: Double = 1, url: String? = nil) -> AdCampaign {
        AdCampaign(id: id, name: ["ar": "اسم", "en": "Name"], category: "cafe", title: ["ar": "عرض"], body: nil,
                   url: url, phone: nil, lat: nil, lng: nil, start: start, end: end, stations: stations, weight: weight)
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
