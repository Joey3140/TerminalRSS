import XCTest
@testable import TerminalRSS

final class FeedParserTests: XCTestCase {
    private let feedURL = URL(string: "https://example.com/feed.xml")!
    private let feedID = UUID()

    private func build(_ xml: String) throws -> (feed: Feed, items: [FeedItem]) {
        try FeedParser.build(data: Data(xml.utf8), url: feedURL, feedID: feedID)
    }

    func testRSS() throws {
        let (feed, items) = try build("""
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title> Example News </title>
            <description>All the news</description>
            <link>https://example.com/</link>
            <item>
              <title>First story</title>
              <link>https://example.com/1</link>
              <description><![CDATA[<p>Short <b>summary</b></p>]]></description>
              <content:encoded><![CDATA[<p>Full body</p>]]></content:encoded>
              <pubDate>Tue, 10 Nov 2026 14:00:00 +0000</pubDate>
              <guid>story-1</guid>
              <dc:creator>Ada</dc:creator>
            </item>
            <item>
              <title>Second story</title>
              <link>https://example.com/2</link>
              <description>Only a description</description>
            </item>
          </channel>
        </rss>
        """)
        XCTAssertEqual(feed.id, feedID)
        XCTAssertEqual(feed.title, "Example News")
        XCTAssertEqual(feed.description, "All the news")
        XCTAssertEqual(items.count, 2)

        let first = items[0]
        XCTAssertEqual(first.id, "story-1")                  // guid wins
        XCTAssertEqual(first.title, "First story")
        XCTAssertEqual(first.link?.absoluteString, "https://example.com/1")
        XCTAssertEqual(first.content, "<p>Full body</p>")    // content:encoded beats description
        XCTAssertEqual(first.author, "Ada")
        XCTAssertEqual(first.pubDate, Date(timeIntervalSince1970: 1_794_319_200))
        XCTAssertEqual(first.feedID, feedID)

        let second = items[1]
        XCTAssertEqual(second.id, "https://example.com/2")   // no guid: the link is the id
        XCTAssertEqual(second.content, "Only a description")
        XCTAssertNil(second.author)
        XCTAssertNil(second.pubDate)
    }

    func testAtom() throws {
        let (feed, items) = try build("""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Blog</title>
          <subtitle>Notes</subtitle>
          <link href="https://example.com/" rel="alternate"/>
          <entry>
            <title>Hello</title>
            <link href="https://example.com/hello/comments" rel="replies"/>
            <link href="https://example.com/hello" rel="alternate"/>
            <id>tag:example.com,2026:hello</id>
            <published>2026-11-10T14:00:00Z</published>
            <updated>2026-11-11T09:00:00Z</updated>
            <author><name>Grace</name></author>
            <summary>A summary</summary>
          </entry>
        </feed>
        """)
        XCTAssertEqual(feed.title, "Atom Blog")
        XCTAssertEqual(feed.description, "Notes")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "tag:example.com,2026:hello")
        XCTAssertEqual(items[0].link?.absoluteString, "https://example.com/hello")  // rel=alternate wins
        XCTAssertEqual(items[0].author, "Grace")
        XCTAssertEqual(items[0].content, "A summary")
        XCTAssertEqual(items[0].pubDate, Date(timeIntervalSince1970: 1_794_319_200))  // first date seen, not <updated>
    }

    func testOnlyWebArticleLinksSurvive() throws {
        let (_, items) = try build("""
        <rss version="2.0"><channel><title>T</title>
          <item><title>a</title><link>https://ok.example/a</link></item>
          <item><title>b</title><link>file:///etc/passwd</link></item>
          <item><title>c</title><link>smb://nas/share</link></item>
          <item><title>d</title><link>javascript:alert(1)</link></item>
          <item><title>e</title><link>http://ok.example/e</link></item>
        </channel></rss>
        """)
        XCTAssertEqual(items.map { $0.link?.absoluteString }, ["https://ok.example/a", nil, nil, nil, "http://ok.example/e"])
    }

    func testUntitledFeedFallsBackToHost() throws {
        let (feed, _) = try build("<rss version=\"2.0\"><channel><item><title>x</title></item></channel></rss>")
        XCTAssertEqual(feed.title, "example.com")
    }

    func testMalformedXMLThrows() {
        XCTAssertThrowsError(try build("<rss><channel><item>"))
    }

    func testDateFormats() {
        let expected = Date(timeIntervalSince1970: 1_794_319_200)  // 2026-11-10 14:00:00 UTC
        for s in ["Tue, 10 Nov 2026 14:00:00 +0000", "Tue, 10 Nov 2026 14:00:00 GMT", "10 Nov 2026 14:00:00 +0000",
                  "2026-11-10T14:00:00Z", "2026-11-10T14:00:00.000Z", "2026-11-10T09:00:00-05:00", "  2026-11-10T14:00:00Z\n"] {
            XCTAssertEqual(FeedParser.parseDate(s), expected, s)
        }
        XCTAssertNotNil(FeedParser.parseDate("2026-11-10"))
        XCTAssertNil(FeedParser.parseDate(""))
        XCTAssertNil(FeedParser.parseDate("yesterday"))
    }

    func testIsWebURL() {
        XCTAssertTrue(URL(string: "https://example.com/x")!.isWebURL)
        XCTAssertTrue(URL(string: "HTTP://example.com")!.isWebURL)
        XCTAssertFalse(URL(string: "https:///no-host")!.isWebURL)
        XCTAssertFalse(URL(string: "file:///etc/passwd")!.isWebURL)
        XCTAssertFalse(URL(string: "mailto:a@example.com")!.isWebURL)
        XCTAssertFalse(URL(string: "terminalrss://open")!.isWebURL)
    }
}
