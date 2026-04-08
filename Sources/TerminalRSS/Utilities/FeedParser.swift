import Foundation

enum FeedParserError: Error, LocalizedError {
    case invalidData
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidData: return "Invalid feed data"
        case .parseFailed(let msg): return "Parse failed: \(msg)"
        }
    }
}

final class FeedParser: NSObject, XMLParserDelegate {
    private enum FeedType { case unknown, rss, atom }

    private var feedType: FeedType = .unknown
    private var currentPath: [String] = []
    private var currentText = ""
    private var isCapturingContent = false  // true when inside content/description elements

    // Feed-level
    private var feedTitle = ""
    private var feedDescription = ""
    private var feedLink = ""

    // Items
    private var items: [ParsedItem] = []
    private var currentItem: ParsedItem?

    private struct ParsedItem {
        var title = ""
        var link = ""
        var description = ""
        var content = ""
        var pubDate = ""
        var guid = ""
        var author = ""
    }

    // MARK: - Public API

    static func fetch(url: URL, feedID: UUID) async throws -> (feed: Feed, items: [FeedItem]) {
        let (data, _) = try await URLSession.shared.data(from: url)
        let parser = FeedParser()
        let parsed = try parser.parse(data: data)

        let feed = Feed(
            id: feedID,
            title: parsed.title.isEmpty ? (url.host ?? "Untitled") : parsed.title,
            url: url,
            description: parsed.description,
            lastRefreshed: Date()
        )

        let feedItems = parsed.items.map { item in
            let body = item.content.isEmpty ? item.description : item.content
            let id = item.guid.isEmpty ? (item.link.isEmpty ? UUID().uuidString : item.link) : item.guid
            return FeedItem(
                id: id,
                feedID: feedID,
                title: item.title,
                link: URL(string: item.link),
                content: body,
                pubDate: parseDate(item.pubDate),
                author: item.author.isEmpty ? nil : item.author
            )
        }

        return (feed, feedItems)
    }

    // MARK: - Parsing

    private func parse(data: Data) throws -> (title: String, description: String, items: [ParsedItem]) {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.shouldResolveExternalEntities = false
        guard xmlParser.parse() else {
            let msg = xmlParser.parserError?.localizedDescription ?? "Unknown error"
            throw FeedParserError.parseFailed(msg)
        }
        return (
            feedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            feedDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            items
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let el = elementName.lowercased()
        currentPath.append(el)

        // Content-bearing elements: accumulate text including nested HTML tags
        let contentElements: Set<String> = ["description", "summary", "content", "content:encoded", "encoded"]
        if currentItem != nil && contentElements.contains(el) {
            currentText = ""
            isCapturingContent = true
        } else if isCapturingContent {
            // Inside content: preserve nested HTML tags by appending them as text
            var tag = "<\(elementName)"
            for (key, value) in attributeDict {
                tag += " \(key)=\"\(value)\""
            }
            tag += ">"
            currentText += tag
        } else {
            currentText = ""
        }

        if el == "rss" { feedType = .rss }
        else if el == "feed" && feedType == .unknown { feedType = .atom }

        if (feedType == .rss && el == "item") || (feedType == .atom && el == "entry") {
            currentItem = ParsedItem()
        }

        // Atom: link href is in attributes
        if feedType == .atom && el == "link" {
            let href = attributeDict["href"] ?? ""
            let rel = attributeDict["rel"] ?? "alternate"
            if currentItem != nil {
                if rel == "alternate" || currentItem!.link.isEmpty {
                    currentItem?.link = href
                }
            } else if rel == "alternate" || feedLink.isEmpty {
                feedLink = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let str = String(data: CDATABlock, encoding: .utf8) {
            currentText += str
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let el = elementName.lowercased()

        // If we're capturing content and this isn't the content element itself,
        // append the closing tag to preserve HTML structure
        let contentElements: Set<String> = ["description", "summary", "content", "content:encoded", "encoded"]
        if isCapturingContent && !contentElements.contains(el) {
            currentText += "</\(elementName)>"
            if !currentPath.isEmpty { currentPath.removeLast() }
            return
        }

        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if contentElements.contains(el) {
            isCapturingContent = false
        }

        if (feedType == .rss && el == "item") || (feedType == .atom && el == "entry") {
            if let item = currentItem { items.append(item) }
            currentItem = nil
        } else if currentItem != nil {
            switch el {
            case "title":
                currentItem?.title = text
            case "link":
                if feedType == .rss { currentItem?.link = text }
            case "description", "summary":
                currentItem?.description = text
            case "content", "content:encoded":
                currentItem?.content = text
            case "encoded":
                if currentPath.count >= 2 {
                    currentItem?.content = text
                }
            case "pubdate", "published", "updated", "dc:date", "date":
                if currentItem?.pubDate.isEmpty ?? true {
                    currentItem?.pubDate = text
                }
            case "guid", "id":
                currentItem?.guid = text
            case "author", "dc:creator", "creator":
                currentItem?.author = text
            case "name":
                if currentPath.contains("author") {
                    currentItem?.author = text
                }
            default:
                break
            }
        } else {
            switch el {
            case "title":
                if feedTitle.isEmpty { feedTitle = text }
            case "description", "subtitle":
                if feedDescription.isEmpty { feedDescription = text }
            case "link":
                if feedType == .rss && feedLink.isEmpty { feedLink = text }
            default:
                break
            }
        }

        if !currentPath.isEmpty { currentPath.removeLast() }
    }

    // MARK: - Date Parsing

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssxxxxx",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ]
        return formats.map { fmt in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            return df
        }
    }()

    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}
