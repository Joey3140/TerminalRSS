import XCTest
@testable import TerminalRSS

final class DateFilterTests: XCTestCase {
    func testRelativeRangesEndNow() {
        let cases: [(DateFilter, TimeInterval)] = [(.last1h, 3600), (.last3h, 3 * 3600), (.last8h, 8 * 3600),
                                                   (.last24h, 86400), (.last3d, 3 * 86400), (.last7d, 7 * 86400),
                                                   (.last30d, 30 * 86400)]
        for (filter, span) in cases {
            let r = filter.dateRange
            let start = try! XCTUnwrap(r.start), end = try! XCTUnwrap(r.end)
            XCTAssertEqual(end.timeIntervalSince(start), span, accuracy: 0.001, filter.label)
            XCTAssertEqual(end.timeIntervalSinceNow, 0, accuracy: 5, filter.label)
        }
        XCTAssertEqual(DateFilter.today.dateRange.start, Calendar.current.startOfDay(for: Date()))
        XCTAssertNil(DateFilter.all.dateRange.start)
        XCTAssertNil(DateFilter.all.dateRange.end)
    }

    func testYahooRange() {
        XCTAssertEqual(DateFilter.last8h.yahooFinanceRange, "1d")
        XCTAssertEqual(DateFilter.last7d.yahooFinanceRange, "5d")
        XCTAssertEqual(DateFilter.last30d.yahooFinanceRange, "1mo")
        XCTAssertEqual(DateFilter.all.yahooFinanceRange, "3mo")
        let start = Date(timeIntervalSince1970: 1_794_000_000)
        func custom(days: Double) -> String {
            DateFilter.custom(start: start, end: start.addingTimeInterval(days * 86400)).yahooFinanceRange
        }
        XCTAssertEqual(custom(days: 1), "1d")
        XCTAssertEqual(custom(days: 6), "5d")
        XCTAssertEqual(custom(days: 20), "1mo")
        XCTAssertEqual(custom(days: 60), "3mo")
    }

    func testCodableRoundTripAndUnknownFallsBackToAll() throws {
        let start = Date(timeIntervalSince1970: 1_794_000_000)
        for f in [DateFilter.last1h, .today, .last30d, .all, .custom(start: start, end: start.addingTimeInterval(3600))] {
            XCTAssertEqual(try JSONDecoder().decode(DateFilter.self, from: JSONEncoder().encode(f)), f)
        }
        XCTAssertEqual(try JSONDecoder().decode(DateFilter.self, from: Data(#"{"type":"fortnight"}"#.utf8)), .all)
    }

    func testOldFeedsJSONStillDecodes() throws {
        // feeds.json from before dateAdded / isPremium existed.
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Old","url":"https://example.com/rss","description":""}"#
        let feed = try JSONDecoder().decode(Feed.self, from: Data(json.utf8))
        XCTAssertEqual(feed.title, "Old")
        XCTAssertFalse(feed.isPremium)
        XCTAssertNil(feed.lastRefreshed)
    }
}
