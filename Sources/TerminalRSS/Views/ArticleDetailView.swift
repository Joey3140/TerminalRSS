import SwiftUI
import AppKit

// MARK: - Selectable NSTextView wrapper

struct SelectableArticleText: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(TerminalTheme.accentBlue),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        // Allow the text view to use the full width
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        // Match the terminal scroller style
        scrollView.scrollerStyle = .overlay

        textView.textStorage?.setAttributedString(attributedString)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(attributedString)
        // Scroll to top on content change
        textView.scrollToBeginningOfDocument(nil)
    }
}

// MARK: - Build NSAttributedString from ContentBlocks

private enum ArticleAttributedBuilder {
    static let monoBody = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let monoBold = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    static let monoSmall = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let monoTitle = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)
    static let monoLargeTitle = NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)

    static func build(article: FeedItem) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Title
        let title = NSAttributedString(string: article.title.uppercased() + "\n", attributes: [
            .font: monoLargeTitle,
            .foregroundColor: NSColor.white,
        ])
        result.append(title)

        // Metadata line
        var metaParts: [String] = []
        if let date = article.pubDate {
            metaParts.append(date.formatted(.dateTime.year().month().day().hour().minute()))
        }
        if let author = article.author {
            metaParts.append("BY \(author.uppercased())")
        }
        if let url = article.link {
            metaParts.append(url.host ?? "")
        }
        if !metaParts.isEmpty {
            let metaLine = NSMutableAttributedString()
            for (i, part) in metaParts.enumerated() {
                let color: NSColor = (i < metaParts.count - 1) ? NSColor(TerminalTheme.accentAmber) : NSColor(TerminalTheme.dimText)
                metaLine.append(NSAttributedString(string: part, attributes: [
                    .font: monoSmall,
                    .foregroundColor: color,
                ]))
                if i < metaParts.count - 1 {
                    metaLine.append(NSAttributedString(string: "  ", attributes: [.font: monoSmall]))
                }
            }
            metaLine.append(NSAttributedString(string: "\n", attributes: [.font: monoSmall]))
            result.append(metaLine)
        }

        // Divider
        result.append(NSAttributedString(string: "─────────────────────────────────────────\n\n", attributes: [
            .font: monoBody,
            .foregroundColor: NSColor(TerminalTheme.panelBorder),
        ]))

        // Content blocks
        let blocks = HTMLRenderer.parse(html: article.content)
        for block in blocks {
            result.append(renderBlock(block))
        }

        return result
    }

    static func renderBlock(_ block: ContentBlock) -> NSAttributedString {
        let result = NSMutableAttributedString()

        switch block {
        case .heading(let level, let text):
            let displayText = level <= 2 ? text.uppercased() : text
            let font = level <= 2 ? monoTitle : monoBold
            let color = level <= 2 ? NSColor(TerminalTheme.accentOrange) : NSColor.white
            result.append(NSAttributedString(string: "\n" + displayText + "\n", attributes: [
                .font: font,
                .foregroundColor: color,
            ]))
            if level <= 2 {
                result.append(NSAttributedString(string: "─────────────────────────────────────────\n", attributes: [
                    .font: monoBody,
                    .foregroundColor: NSColor(TerminalTheme.panelBorder),
                ]))
            }

        case .paragraph(let segments):
            result.append(renderSegments(segments))
            result.append(NSAttributedString(string: "\n\n", attributes: [.font: monoBody]))

        case .codeBlock(let code):
            let para = NSMutableParagraphStyle()
            para.headIndent = 12
            para.firstLineHeadIndent = 12
            para.tailIndent = -12
            result.append(NSAttributedString(string: code + "\n\n", attributes: [
                .font: monoBody,
                .foregroundColor: NSColor(TerminalTheme.accentGreen),
                .backgroundColor: NSColor(TerminalTheme.codeBackground),
                .paragraphStyle: para,
            ]))

        case .blockquote(let text):
            let para = NSMutableParagraphStyle()
            para.headIndent = 16
            para.firstLineHeadIndent = 16
            let font = NSFontManager.shared.convert(monoBody, toHaveTrait: .italicFontMask)
            result.append(NSAttributedString(string: "▎ " + text + "\n\n", attributes: [
                .font: font,
                .foregroundColor: NSColor(TerminalTheme.primaryText),
                .paragraphStyle: para,
            ]))

        case .listItem(let text, let index):
            let bullet = index != nil ? "\(index!)." : "•"
            let para = NSMutableParagraphStyle()
            para.headIndent = 28
            para.firstLineHeadIndent = 4
            let tabStop = NSTextTab(textAlignment: .right, location: 24)
            para.tabStops = [tabStop, NSTextTab(textAlignment: .left, location: 28)]
            result.append(NSAttributedString(string: "\t\(bullet)\t\(text)\n", attributes: [
                .font: monoBody,
                .foregroundColor: NSColor(TerminalTheme.primaryText),
                .paragraphStyle: para,
            ]))

        case .horizontalRule:
            result.append(NSAttributedString(string: "\n─────────────────────────────────────────\n\n", attributes: [
                .font: monoBody,
                .foregroundColor: NSColor(TerminalTheme.panelBorder),
            ]))

        case .image(let alt):
            result.append(NSAttributedString(string: "[IMG: \(alt)]\n", attributes: [
                .font: monoSmall,
                .foregroundColor: NSColor(TerminalTheme.accentAmber),
            ]))
        }

        return result
    }

    static func renderSegments(_ segments: [TextSegment]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for segment in segments {
            switch segment {
            case .plain(let s):
                result.append(NSAttributedString(string: s, attributes: [
                    .font: monoBody,
                    .foregroundColor: NSColor(TerminalTheme.primaryText),
                ]))
            case .bold(let s):
                result.append(NSAttributedString(string: s, attributes: [
                    .font: monoBold,
                    .foregroundColor: NSColor.white,
                ]))
            case .italic(let s):
                let font = NSFontManager.shared.convert(monoBody, toHaveTrait: .italicFontMask)
                result.append(NSAttributedString(string: s, attributes: [
                    .font: font,
                    .foregroundColor: NSColor(TerminalTheme.primaryText),
                ]))
            case .code(let s):
                result.append(NSAttributedString(string: s, attributes: [
                    .font: monoBody,
                    .foregroundColor: NSColor(TerminalTheme.accentGreen),
                ]))
            case .link(let text, let urlString):
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: monoBody,
                    .foregroundColor: NSColor(TerminalTheme.accentBlue),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]
                if let url = URL(string: urlString) {
                    attrs[.link] = url
                }
                result.append(NSAttributedString(string: text, attributes: attrs))
            }
        }
        return result
    }
}

// MARK: - Article Detail View

struct ArticleDetailView: View {
    @EnvironmentObject var store: FeedStore
    @State private var showBrowser = false
    @State private var browserURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            if showBrowser, let url = browserURL {
                BrowserPanel(
                    url: url,
                    onClose: { showBrowser = false },
                    onOpenExternal: {
                        NSWorkspace.shared.open(url)
                    }
                )
            } else {
                readerView
            }
        }
        .background(TerminalTheme.background)
        .onChange(of: store.selectedArticleID) { _, _ in
            showBrowser = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .openInBrowser)) { _ in
            if let article = store.selectedArticle, let url = article.link {
                browserURL = url
                showBrowser = true
            }
        }
    }

    // MARK: - Reader View

    private var readerView: some View {
        VStack(spacing: 0) {
            // Panel header
            HStack {
                Text("READER")
                    .font(TerminalTheme.headerFont)
                    .foregroundStyle(TerminalTheme.accentOrange)

                Spacer()

                if let article = store.selectedArticle {
                    // Flag buttons
                    ForEach(ArticleFlag.allCases, id: \.rawValue) { flag in
                        Button {
                            store.toggleFlag(article.id, flag: flag)
                        } label: {
                            Text(flag.icon)
                                .font(TerminalTheme.bodyFont)
                                .foregroundStyle(store.flag(for: article.id) == flag
                                    ? TerminalTheme.accentOrange
                                    : TerminalTheme.dimText)
                        }
                        .buttonStyle(.plain)
                        .help(flag.rawValue)
                    }

                    if let url = article.link {
                        Button {
                            browserURL = url
                            showBrowser = true
                        } label: {
                            Text("VIEW IN BROWSER")
                                .font(TerminalTheme.smallFont)
                                .foregroundStyle(TerminalTheme.accentBlue)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)

                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Text("SAFARI ↗")
                                .font(TerminalTheme.smallFont)
                                .foregroundStyle(TerminalTheme.dimText)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(TerminalTheme.panelBackground)

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            if let article = store.selectedArticle {
                SelectableArticleText(
                    attributedString: ArticleAttributedBuilder.build(article: article)
                )
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Text("NO ARTICLE SELECTED")
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(TerminalTheme.dimText)
                    Text("Select an article from the list above")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.dimText.opacity(0.6))
                }
                Spacer()
            }
        }
    }
}
