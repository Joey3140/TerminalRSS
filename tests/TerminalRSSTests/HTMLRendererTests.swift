import XCTest
@testable import TerminalRSS

final class HTMLRendererTests: XCTestCase {
    private func describe(_ blocks: [ContentBlock]) -> [String] {
        blocks.map { b in
            switch b {
            case .heading(let level, let text): return "h\(level):\(text)"
            case .paragraph(let segs): return "p:" + segs.map(describe).joined(separator: "|")
            case .codeBlock(let code): return "pre:\(code)"
            case .blockquote(let text): return "quote:\(text)"
            case .listItem(let text, _): return "li:\(text)"
            case .horizontalRule: return "hr"
            case .image(let alt): return "img:\(alt)"
            }
        }
    }

    private func describe(_ s: TextSegment) -> String {
        switch s {
        case .plain(let t): return t
        case .bold(let t): return "**\(t)**"
        case .italic(let t): return "_\(t)_"
        case .code(let t): return "`\(t)`"
        case .link(let t, let url): return "[\(t)](\(url))"
        }
    }

    func testBlocks() {
        let html = """
        <h2>Title</h2><p>Hello <b>bold</b>, <em>it</em> and <a href="https://x.example/">a link</a>.</p>
        <pre>let x = 1
        print(x)</pre><blockquote>Quoted</blockquote><ul><li>One</li><li>Two</li></ul><hr/><img alt="Chart" src="c.png">
        """
        XCTAssertEqual(describe(HTMLRenderer.parse(html: html)), [
            "h2:Title",
            "p:Hello |**bold**|, |_it_| and |[a link](https://x.example/)|.",
            "pre:let x = 1\nprint(x)",
            "quote:Quoted",
            "li:One",
            "li:Two",
            "hr",
            "img:Chart",
        ])
    }

    func testTextAfterARuleIsKept() {
        // Regression: the whole "<hr>…" chunk used to become the rule, dropping the text.
        XCTAssertEqual(describe(HTMLRenderer.parse(html: "<p>Before</p><hr>After the rule<HR class=\"x\">End")),
                       ["p:Before", "hr", "p:After the rule", "hr", "p:End"])
    }

    func testFirstItemOfEveryListIsAListItem() {
        // Regression: the first <li> shared a chunk with <ul>/<ol> and rendered as a paragraph.
        XCTAssertEqual(describe(HTMLRenderer.parse(html: "<ol start=\"3\"><li>A</li><li>B</li></ol><ul><li>C</li></ul>")),
                       ["li:A", "li:B", "li:C"])
    }

    func testPlainTextBecomesOneParagraph() {
        XCTAssertEqual(describe(HTMLRenderer.parse(html: "just text")), ["p:just text"])
        XCTAssertEqual(HTMLRenderer.parse(html: "").count, 0)
    }

    func testBreaksSplitParagraphs() {
        XCTAssertEqual(describe(HTMLRenderer.parse(html: "line one<br>line two<BR />line three")),
                       ["p:line one", "p:line two", "p:line three"])
    }

    func testStripAndDecode() {
        XCTAssertEqual(HTMLRenderer.stripHTML("<p>Fish &amp; <i>chips</i></p>"), "Fish & chips")
        XCTAssertEqual(HTMLRenderer.decodeEntities("&lt;tag&gt; &quot;q&quot; &rsquo;s &mdash; &nbsp;x"), "<tag> \"q\" \u{2019}s — \u{20}x")
        XCTAssertEqual(HTMLRenderer.decodeEntities("caf&#233; &#x1F600; &#8217;"), "café 😀 \u{2019}")
        XCTAssertEqual(HTMLRenderer.decodeEntities("no entities here"), "no entities here")
        XCTAssertEqual(HTMLRenderer.decodeEntities("broken &#xZZ; stays"), "broken &#xZZ; stays")
    }
}
