import Foundation

struct FeedItem: Identifiable, Codable {
    let id: String
    let feedID: UUID
    var title: String
    var link: URL?
    var content: String
    var pubDate: Date?
    var author: String?

    init(id: String? = nil, feedID: UUID, title: String, link: URL? = nil,
         content: String = "", pubDate: Date? = nil, author: String? = nil) {
        self.id = id ?? UUID().uuidString
        self.feedID = feedID
        self.title = title
        self.link = link
        self.content = content
        self.pubDate = pubDate
        self.author = author
    }
}
