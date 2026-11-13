import Foundation

extension URL {
    /// True only for http/https URLs with a host. Feed text is untrusted: a
    /// link like `file:///…`, `smb://…`, `javascript:…` or an app's custom
    /// scheme must never reach NSWorkspace.open, the article NSTextView or the
    /// in-app WKWebView. Check this before opening or loading any feed URL.
    var isWebURL: Bool {
        guard let scheme = scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return !(host ?? "").isEmpty
    }
}
