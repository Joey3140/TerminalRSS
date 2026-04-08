import SwiftUI

// MARK: - Content Block Types

enum ContentBlock {
    case heading(level: Int, text: String)
    case paragraph(segments: [TextSegment])
    case codeBlock(code: String)
    case blockquote(text: String)
    case listItem(text: String, index: Int?)
    case horizontalRule
    case image(alt: String)
}

enum TextSegment {
    case plain(String)
    case bold(String)
    case italic(String)
    case code(String)
    case link(text: String, url: String)
}

// MARK: - HTML Parser

struct HTMLRenderer {

    static func parse(html: String) -> [ContentBlock] {
        guard !html.isEmpty else { return [] }

        let chunks = splitIntoBlocks(html)
        var blocks: [ContentBlock] = []

        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if let block = parseBlock(trimmed) {
                blocks.append(block)
            }
        }

        if blocks.isEmpty {
            let text = stripHTML(html)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.paragraph(segments: parseInlineElements(html)))
            }
        }

        return blocks
    }

    // MARK: - Block Splitting

    private static func splitIntoBlocks(_ html: String) -> [String] {
        var text = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let closingTags = [
            "</p>", "</div>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>",
            "</pre>", "</blockquote>", "</li>", "</ul>", "</ol>",
        ]

        for tag in closingTags {
            text = text.replacingOccurrences(of: tag, with: tag + "\n<<SPLIT>>\n",
                                             options: .caseInsensitive)
        }

        // <br> variants
        if let brRegex = try? NSRegularExpression(pattern: "<br\\s*/?>", options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            text = brRegex.stringByReplacingMatches(in: text, range: range,
                                                     withTemplate: "\n<<SPLIT>>\n")
        }

        // <hr> as its own block
        text = text.replacingOccurrences(of: "<hr", with: "\n<<SPLIT>>\n<hr",
                                         options: .caseInsensitive)

        return text.components(separatedBy: "<<SPLIT>>")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Block Classification

    private static func parseBlock(_ html: String) -> ContentBlock? {
        let lower = html.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for level in 1...6 {
            if lower.hasPrefix("<h\(level)") {
                let text = stripHTML(html)
                if !text.isEmpty { return .heading(level: level, text: text) }
            }
        }

        if lower.hasPrefix("<pre") || (lower.hasPrefix("<code") && html.contains("\n")) {
            return .codeBlock(code: stripHTML(html))
        }

        if lower.hasPrefix("<blockquote") {
            return .blockquote(text: stripHTML(html))
        }

        if lower.hasPrefix("<hr") {
            return .horizontalRule
        }

        if lower.hasPrefix("<img") {
            let alt = extractAttribute(html, name: "alt") ?? "image"
            return .image(alt: alt)
        }

        if lower.hasPrefix("<li") {
            return .listItem(text: stripHTML(html), index: nil)
        }

        let segments = parseInlineElements(html)
        let hasContent = segments.contains { seg in
            switch seg {
            case .plain(let t): return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default: return true
            }
        }
        return hasContent ? .paragraph(segments: segments) : nil
    }

    // MARK: - Inline Element Parsing

    static func parseInlineElements(_ html: String) -> [TextSegment] {
        var text = html

        // Strip block-level opening tags
        let blockOpeners = ["<p[^>]*>", "<div[^>]*>", "<span[^>]*>", "</span>",
                            "<li[^>]*>", "</li>", "</p>", "</div>"]
        for pattern in blockOpeners {
            if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                text = re.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            }
        }

        let pattern = #"<(strong|b|em|i|code|a)(\s[^>]*)?>(.+?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                    options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [.plain(decodeEntities(stripHTML(text)))]
        }

        var segments: [TextSegment] = []
        var lastEnd = text.startIndex
        let nsRange = NSRange(text.startIndex..., in: text)

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match = match,
                  let fullRange = Range(match.range, in: text),
                  let tagRange = Range(match.range(at: 1), in: text),
                  let contentRange = Range(match.range(at: 3), in: text) else { return }

            // Plain text before this match
            let before = decodeEntities(stripHTML(String(text[lastEnd..<fullRange.lowerBound])))
            if !before.isEmpty { segments.append(.plain(before)) }

            let tag = text[tagRange].lowercased()
            let content = decodeEntities(stripHTML(String(text[contentRange])))

            switch tag {
            case "strong", "b":
                segments.append(.bold(content))
            case "em", "i":
                segments.append(.italic(content))
            case "code":
                segments.append(.code(content))
            case "a":
                let attrsStr: String
                if let attrsRange = Range(match.range(at: 2), in: text) {
                    attrsStr = String(text[attrsRange])
                } else {
                    attrsStr = ""
                }
                let href = extractAttribute(attrsStr, name: "href") ?? ""
                segments.append(.link(text: content, url: href))
            default:
                segments.append(.plain(content))
            }

            lastEnd = fullRange.upperBound
        }

        let remaining = decodeEntities(stripHTML(String(text[lastEnd...])))
        if !remaining.isEmpty { segments.append(.plain(remaining)) }

        return segments
    }

    // MARK: - Utilities

    static func stripHTML(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) else {
            return html
        }
        let range = NSRange(html.startIndex..., in: html)
        return decodeEntities(regex.stringByReplacingMatches(in: html, range: range, withTemplate: ""))
    }

    static func decodeEntities(_ text: String) -> String {
        var s = text
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " "), ("&mdash;", "—"),
            ("&ndash;", "–"), ("&hellip;", "…"), ("&laquo;", "«"), ("&raquo;", "»"),
            ("&bull;", "•"), ("&middot;", "·"), ("&copy;", "©"), ("&reg;", "®"),
            ("&trade;", "™"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
        ]
        for (entity, ch) in named {
            s = s.replacingOccurrences(of: entity, with: ch, options: .caseInsensitive)
        }

        // Hex numeric: &#xHH;
        while let range = s.range(of: "&#x", options: .caseInsensitive) {
            guard let semi = s[range.upperBound...].firstIndex(of: ";") else { break }
            let hex = String(s[range.upperBound..<semi])
            if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                s.replaceSubrange(range.lowerBound...semi, with: String(scalar))
            } else { break }
        }

        // Decimal numeric: &#DDD;
        while let range = s.range(of: "&#") {
            // Skip if this is &#x (already handled)
            let afterHash = s.index(range.upperBound, offsetBy: 0)
            if afterHash < s.endIndex && s[afterHash] == "x" { break }
            guard let semi = s[range.upperBound...].firstIndex(of: ";") else { break }
            let num = String(s[range.upperBound..<semi])
            if let code = UInt32(num), let scalar = Unicode.Scalar(code) {
                s.replaceSubrange(range.lowerBound...semi, with: String(scalar))
            } else { break }
        }

        return s
    }

    private static func extractAttribute(_ html: String, name: String) -> String? {
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let valueRange = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[valueRange])
    }
}
