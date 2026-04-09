import SwiftUI

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
            // Reset to reader when switching articles
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

                if let article = store.selectedArticle, let url = article.link {
                    Button {
                        browserURL = url
                        showBrowser = true
                    } label: {
                        Text("VIEW IN BROWSER")
                            .font(TerminalTheme.smallFont)
                            .foregroundStyle(TerminalTheme.accentBlue)
                    }
                    .buttonStyle(.plain)

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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(TerminalTheme.panelBackground)

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            if let article = store.selectedArticle {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Title
                        Text(article.title.uppercased())
                            .font(TerminalTheme.largeTitleFont)
                            .foregroundStyle(TerminalTheme.brightText)

                        // Metadata
                        HStack(spacing: 12) {
                            if let date = article.pubDate {
                                Text(date.formatted(.dateTime.year().month().day().hour().minute()))
                                    .foregroundStyle(TerminalTheme.accentAmber)
                            }
                            if let author = article.author {
                                Text("BY \(author.uppercased())")
                                    .foregroundStyle(TerminalTheme.accentAmber)
                            }
                            if let url = article.link {
                                Text(url.host ?? "")
                                    .foregroundStyle(TerminalTheme.dimText)
                            }
                        }
                        .font(TerminalTheme.smallFont)

                        Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)
                            .padding(.vertical, 4)

                        // Article content
                        let blocks = HTMLRenderer.parse(html: article.content)
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            renderBlock(block)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    // MARK: - Block Rendering

    @ViewBuilder
    private func renderBlock(_ block: ContentBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            VStack(alignment: .leading, spacing: 2) {
                Text(level <= 2 ? text.uppercased() : text)
                    .font(level <= 2 ? TerminalTheme.titleFont : TerminalTheme.headerFont)
                    .foregroundStyle(level <= 2 ? TerminalTheme.accentOrange : TerminalTheme.brightText)
                if level <= 2 {
                    Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)
                }
            }
            .padding(.top, level <= 2 ? 8 : 4)

        case .paragraph(let segments):
            renderSegments(segments)
                .padding(.vertical, 2)

        case .codeBlock(let code):
            Text(code)
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.accentGreen)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TerminalTheme.codeBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(TerminalTheme.panelBorder, lineWidth: 1)
                )
                .padding(.vertical, 4)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(TerminalTheme.accentGreen)
                    .frame(width: 3)
                Text(text)
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.primaryText)
                    .italic()
            }
            .padding(.vertical, 4)

        case .listItem(let text, let index):
            HStack(alignment: .top, spacing: 8) {
                Text(index != nil ? "\(index!)." : "•")
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.accentGreen)
                    .frame(width: 20, alignment: .trailing)
                Text(text)
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.primaryText)
            }

        case .horizontalRule:
            Rectangle()
                .fill(TerminalTheme.panelBorder)
                .frame(height: 1)
                .padding(.vertical, 8)

        case .image(let alt):
            Text("[IMG: \(alt)]")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.accentAmber)
                .padding(.vertical, 2)
        }
    }

    private func renderSegments(_ segments: [TextSegment]) -> Text {
        var attributed = AttributedString()
        for segment in segments {
            var part: AttributedString
            switch segment {
            case .plain(let s):
                part = AttributedString(s)
                part.font = TerminalTheme.bodyFont
                part.foregroundColor = TerminalTheme.primaryText
            case .bold(let s):
                part = AttributedString(s)
                part.font = TerminalTheme.headerFont
                part.foregroundColor = TerminalTheme.brightText
            case .italic(let s):
                part = AttributedString(s)
                part.font = TerminalTheme.bodyFont.italic()
                part.foregroundColor = TerminalTheme.primaryText
            case .code(let s):
                part = AttributedString(s)
                part.font = TerminalTheme.bodyFont
                part.foregroundColor = TerminalTheme.accentGreen
            case .link(let text, let urlString):
                part = AttributedString(text)
                part.font = TerminalTheme.bodyFont
                part.foregroundColor = TerminalTheme.accentBlue
                part.underlineStyle = .single
                if let url = URL(string: urlString) {
                    part.link = url
                }
            }
            attributed.append(part)
        }
        return Text(attributed)
    }
}
