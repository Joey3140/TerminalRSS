import XCTest
@testable import TerminalRSS

final class RankingTests: XCTestCase {
    private let regular = Feed(title: "Regular", url: URL(string: "https://a.example/feed")!)
    private let premium = Feed(title: "Premium", url: URL(string: "https://b.example/feed")!, isPremium: true)

    private func item(_ title: String, _ feed: Feed, hoursAgo: Double? = nil) -> FeedItem {
        FeedItem(id: title + feed.title, feedID: feed.id, title: title,
                 pubDate: hoursAgo.map { Date().addingTimeInterval(-$0 * 3600) })
    }

    func testNormalizeTitleDropsStopWordsAndShortTokens() {
        XCTAssertEqual(ArticleRanker.normalizeTitle("The Fed raises rates: what it means for a mortgage"),
                       ["fed", "raises", "rates", "means", "mortgage"])
    }

    func testJaccard() {
        XCTAssertEqual(ArticleRanker.jaccardSimilarity(["a", "b"], ["b", "c"]), 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(ArticleRanker.jaccardSimilarity(["a"], ["a"]), 1)
        XCTAssertEqual(ArticleRanker.jaccardSimilarity([], []), 0)
    }

    func testRecencyBands() {
        let now = Date()
        XCTAssertEqual(ArticleRanker.recencyScore(now.addingTimeInterval(-30 * 60)), 1.0)
        XCTAssertEqual(ArticleRanker.recencyScore(now.addingTimeInterval(-3 * 3600)), 0.8)
        XCTAssertEqual(ArticleRanker.recencyScore(now.addingTimeInterval(-12 * 3600)), 0.5)
        XCTAssertEqual(ArticleRanker.recencyScore(now.addingTimeInterval(-48 * 3600)), 0.2)
        XCTAssertEqual(ArticleRanker.recencyScore(now.addingTimeInterval(-100 * 3600)), 0.0)
        XCTAssertEqual(ArticleRanker.recencyScore(nil), 0.0)
    }

    func testAdDetection() {
        XCTAssertTrue(ArticleRanker.isLikelyAd("Best Deals of the week: 40% OFF headphones"))
        XCTAssertTrue(ArticleRanker.isLikelyAd("Newegg promo code for November"))
        XCTAssertFalse(ArticleRanker.isLikelyAd("Apple reports record quarter"))
    }

    func testSameStoryFromTwoFeedsClustersAndOutranksASingleton() {
        let clusters = ArticleRanker.rank(articles: [
            item("Nvidia unveils new Blackwell GPU lineup", regular, hoursAgo: 5),
            item("Local bakery wins award", regular, hoursAgo: 0.5),
            item("Nvidia unveils Blackwell GPU lineup at GTC", premium, hoursAgo: 2),
        ], feeds: [regular, premium], readIDs: [])
        XCTAssertEqual(clusters.count, 2)
        let top = clusters[0]
        XCTAssertEqual(top.sourceCount, 2)
        XCTAssertTrue(top.hasPremiumSource)
        XCTAssertEqual(top.primaryArticle.title, "Nvidia unveils Blackwell GPU lineup at GTC")  // the most recent
        XCTAssertEqual(top.sources.map(\.title).first, "Nvidia unveils Blackwell GPU lineup at GTC")
        XCTAssertEqual(top.score, 2 * 2.0 + 0.8 + 3.0, accuracy: 1e-9)
        XCTAssertEqual(clusters[1].score, 1 * 2.0 + 1.0, accuracy: 1e-9)
    }

    func testAdsSinkToTheBottom() {
        let clusters = ArticleRanker.rank(articles: [
            item("Huge sale: 50% off everything today only", premium, hoursAgo: 0.1),
            item("Quiet policy change at the city council", regular, hoursAgo: 90),
        ], feeds: [regular, premium], readIDs: [])
        XCTAssertEqual(clusters.last?.primaryArticle.title, "Huge sale: 50% off everything today only")
        XCTAssertLessThan(clusters.last!.score, 0)
    }

    func testOneWordTitlesNeverCluster() {
        let clusters = ArticleRanker.rank(articles: [item("Update", regular), item("Update", premium)],
                                          feeds: [regular, premium], readIDs: [])
        XCTAssertEqual(clusters.count, 2)
    }

    func testClassify() {
        typealias T = TopicClassifier.Topic
        XCTAssertEqual(TopicClassifier.classify("Anthropic ships a new Claude model"), T.ai)
        XCTAssertEqual(TopicClassifier.classify("Ransomware gang claims hospital breach"), T.security)
        XCTAssertEqual(TopicClassifier.classify("Bitcoin tops a new high"), T.crypto)
        XCTAssertEqual(TopicClassifier.classify("Something unrelated happened"), T.other)
        // No keyword: the feed's name decides.
        XCTAssertEqual(TopicClassifier.classify("Something unrelated happened", feedName: "Krebs on Security"), T.security)
        XCTAssertEqual(TopicClassifier.classify("Something unrelated happened", feedName: "BBC News"), T.world)
        // A keyword beats the feed hint.
        XCTAssertEqual(TopicClassifier.classify("Bitcoin tops a new high", feedName: "BBC News"), T.crypto)
    }

    func testGroupSortsTopicsByArticleCount() {
        let groups = TopicClassifier.group(articles: [
            item("Bitcoin tops a new high", regular),
            item("Ethereum upgrade lands", regular),
            item("Ransomware gang claims hospital breach", regular),
        ], feeds: [regular, premium], readIDs: [])
        XCTAssertEqual(groups.map(\.topic), [TopicClassifier.Topic.crypto.rawValue, TopicClassifier.Topic.security.rawValue])
        XCTAssertEqual(groups.map(\.articleCount), [2, 1])
    }
}
