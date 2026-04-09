import SwiftUI
import WebKit

/// NSViewRepresentable wrapper for WKWebView with terminal-themed chrome.
struct WebBrowserView: NSViewRepresentable {
    let url: URL
    @Binding var currentURL: String
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var webView: WKWebView?

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebBrowserView

        init(_ parent: WebBrowserView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.currentURL = webView.url?.absoluteString ?? ""
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true

        // Dark background while loading
        wv.setValue(false, forKey: "drawsBackground")

        wv.load(URLRequest(url: url))

        // Pass reference back so BrowserPanel can call goBack/goForward/reload directly
        DispatchQueue.main.async { webView = wv }

        return wv
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only navigate if URL actually changed
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

/// The full browser panel with terminal-themed toolbar
struct BrowserPanel: View {
    let url: URL
    let onClose: () -> Void
    let onOpenExternal: () -> Void

    @State private var currentURL: String = ""
    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webView: WKWebView?

    var body: some View {
        VStack(spacing: 0) {
            // Browser toolbar
            HStack(spacing: 8) {
                // Back / Forward
                Button { webView?.goBack() } label: {
                    Text("◀")
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(canGoBack ? TerminalTheme.brightText : TerminalTheme.dimText)
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)

                Button { webView?.goForward() } label: {
                    Text("▶")
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(canGoForward ? TerminalTheme.brightText : TerminalTheme.dimText)
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)

                Button { webView?.reload() } label: {
                    Text("↻")
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(TerminalTheme.brightText)
                }
                .buttonStyle(.plain)

                // URL bar
                Text(currentURL.isEmpty ? url.absoluteString : currentURL)
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.dimText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(TerminalTheme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(TerminalTheme.panelBorder, lineWidth: 1)
                    )

                if isLoading {
                    Text("LOADING...")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentGreen)
                }

                // Open in Safari
                Button { onOpenExternal() } label: {
                    Text("SAFARI ↗")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentBlue)
                }
                .buttonStyle(.plain)

                // Close browser
                Button { onClose() } label: {
                    Text("✕ READER")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentOrange)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(TerminalTheme.panelBackground)

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Web content
            WebBrowserView(
                url: url,
                currentURL: $currentURL,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                webView: $webView
            )
        }
    }
}
