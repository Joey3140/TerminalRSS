import Foundation

struct Feed: Identifiable, Codable {
    let id: UUID
    var title: String
    var url: URL
    var description: String
    var lastRefreshed: Date?
    var dateAdded: Date
    var isPremium: Bool

    init(id: UUID = UUID(), title: String, url: URL, description: String = "",
         lastRefreshed: Date? = nil, dateAdded: Date = Date(), isPremium: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.description = description
        self.lastRefreshed = lastRefreshed
        self.dateAdded = dateAdded
        self.isPremium = isPremium
    }

    // Custom decoding for backwards compatibility with existing feeds.json
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(URL.self, forKey: .url)
        description = try container.decode(String.self, forKey: .description)
        lastRefreshed = try container.decodeIfPresent(Date.self, forKey: .lastRefreshed)
        dateAdded = try container.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
    }
}
