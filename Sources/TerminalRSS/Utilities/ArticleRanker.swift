import Foundation

struct ArticleCluster: Identifiable {
    let id: String               // primary article ID
    let primaryArticle: FeedItem
    let sources: [FeedItem]      // all articles in cluster (including primary)
    let sourceCount: Int
    let score: Double
    let hasPremiumSource: Bool
}

struct ArticleRanker {
    private static let stopWords: Set<String> = [
        "the", "a", "an", "in", "on", "at", "to", "for", "of", "and", "or",
        "is", "it", "by", "with", "from", "as", "this", "that", "are", "was",
        "were", "be", "has", "had", "have", "will", "but", "not", "you", "your",
        "we", "they", "its", "new", "how", "why", "what"
    ]

    private static let adPatterns: [String] = [
        "promo code", "coupon code", "discount code", "% off",
        "promo codes", "coupon codes", "discount codes",
        "deal of", "deals of", "best deals",
        "affiliate", "sponsored",
    ]

    static func isLikelyAd(_ title: String) -> Bool {
        let lower = title.lowercased()
        return adPatterns.contains { lower.contains($0) }
    }

    static func normalizeTitle(_ title: String) -> Set<String> {
        let cleaned = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 1 }
        return Set(cleaned)
    }

    static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    static func recencyScore(_ date: Date?) -> Double {
        guard let date = date else { return 0 }
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 1 { return 1.0 }
        if hours < 6 { return 0.8 }
        if hours < 24 { return 0.5 }
        if hours < 72 { return 0.2 }
        return 0.0
    }

    static func rank(articles: [FeedItem], feeds: [Feed], readIDs: Set<String>) -> [ArticleCluster] {
        // Build feed lookup for premium status
        let feedMap = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })

        // Normalize all titles
        let normalized = articles.map { (article: $0, words: normalizeTitle($0.title)) }

        // Greedy clustering — threshold 0.3 for broader matching
        // Cluster vocabulary grows as articles join (union of all member words)
        var clusters: [(primary: FeedItem, members: [FeedItem], words: Set<String>)] = []

        for entry in normalized {
            guard entry.words.count >= 2 else {
                // Too few words to match meaningfully — give it its own cluster
                clusters.append((primary: entry.article, members: [entry.article], words: entry.words))
                continue
            }
            var matched = false
            for i in clusters.indices {
                if jaccardSimilarity(entry.words, clusters[i].words) >= 0.3 {
                    clusters[i].members.append(entry.article)
                    clusters[i].words = clusters[i].words.union(entry.words)
                    matched = true
                    break
                }
            }
            if !matched {
                clusters.append((primary: entry.article, members: [entry.article], words: entry.words))
            }
        }

        // Build ArticleCluster results
        return clusters.map { cluster in
            // Pick article with longest content as primary
            let primary = cluster.members.max(by: { $0.content.count < $1.content.count }) ?? cluster.primary

            let sourceCount = cluster.members.count
            let bestRecency = cluster.members.compactMap(\.pubDate).map { recencyScore($0) }.max() ?? 0
            let hasPremium = cluster.members.contains { feedMap[$0.feedID]?.isPremium == true }
            let premiumBoost: Double = hasPremium ? 3.0 : 0.0

            // Penalize ad/promo clusters — push them to the bottom
            let adPenalty: Double = isLikelyAd(primary.title) ? -20.0 : 0.0
            let score = Double(sourceCount) * 2.0 + bestRecency + premiumBoost + adPenalty

            return ArticleCluster(
                id: primary.id,
                primaryArticle: primary,
                sources: cluster.members.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) },
                sourceCount: sourceCount,
                score: score,
                hasPremiumSource: hasPremium
            )
        }
        .sorted { $0.score > $1.score }
    }
}
