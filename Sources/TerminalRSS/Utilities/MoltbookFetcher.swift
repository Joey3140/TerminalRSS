import Foundation

/// Fetches posts from Moltbook's public API and converts them to FeedItems.
/// Moltbook is a social network for AI agents — "the front page of the agent internet."
struct MoltbookFetcher {
    static let feedTitle = "MOLTBOOK"
    static let baseURL = "https://www.moltbook.com/api/v1/submolts"
    static let postBaseURL = "https://www.moltbook.com/post"

    /// Submolts (communities) to fetch from
    private static let submolts = ["general"]

    /// Sort options: "comments", "upvotes", "new"
    private static let defaultSort = "comments"
    private static let defaultTime = "week"

    /// Fetches top posts from Moltbook and returns them as a Feed + [FeedItem] pair.
    /// Uses a stable feed ID so the feed persists across refreshes.
    static func fetch(feedID: UUID) async -> (Feed, [FeedItem])? {
        var allItems: [FeedItem] = []

        for submolt in submolts {
            guard let url = URL(string: "\(baseURL)/\(submolt)/feed?sort=\(defaultSort)&time=\(defaultTime)") else {
                continue
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { continue }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let posts = json?["posts"] as? [[String: Any]] else { continue }

                for post in posts {
                    guard let id = post["id"] as? String,
                          let title = post["title"] as? String else { continue }

                    let content = post["content"] as? String ?? ""
                    let authorObj = post["author"] as? [String: Any]
                    let authorName = authorObj?["name"] as? String
                    let karma = authorObj?["karma"] as? Int
                    let upvotes = post["upvotes"] as? Int ?? 0
                    let commentCount = post["comment_count"] as? Int ?? 0
                    let submoltName = post["submolt_name"] as? String ?? submolt

                    // Parse ISO date
                    var pubDate: Date?
                    if let dateStr = post["created_at"] as? String {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        pubDate = formatter.date(from: dateStr)
                    }

                    // Build post URL
                    let link = URL(string: "\(postBaseURL)/\(id)")

                    // Build rich content with metadata
                    let stats = "↑\(upvotes) | \(commentCount) comments | m/\(submoltName)"
                    let authorLine = authorName.map { "Posted by \($0)" + (karma.map { " (karma: \($0))" } ?? "") } ?? ""
                    let richContent = "\(authorLine)\n\(stats)\n\n\(content)"

                    let item = FeedItem(
                        id: "moltbook-\(id)",
                        feedID: feedID,
                        title: title,
                        link: link,
                        content: richContent,
                        pubDate: pubDate,
                        author: authorName
                    )
                    allItems.append(item)
                }
            } catch {
                print("MoltbookFetcher error for \(submolt): \(error)")
            }
        }

        // Sort by comment count (most discussed first) — already sorted by API but ensure
        allItems.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }

        let feed = Feed(
            id: feedID,
            title: feedTitle,
            url: URL(string: "https://www.moltbook.com")!,
            description: "The front page of the agent internet — top posts from Moltbook"
        )

        return (feed, allItems)
    }
}
