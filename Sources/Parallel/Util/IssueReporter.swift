import Foundation
import AppKit

/// Builds prefilled GitHub "new issue" URLs and hands them to the default
/// browser via NSWorkspace. The app never POSTs to GitHub — the user
/// reviews and submits the issue in their already-logged-in browser.
enum IssueReporter {
    static let repository = "BottlePumpkin/Parallel"

    static func newIssueURL(title: String, body: String, labels: [String]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository)/issues/new"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "title", value: encode(title)),
            URLQueryItem(name: "body", value: encode(body)),
        ]
        if !labels.isEmpty {
            items.append(URLQueryItem(name: "labels", value: encode(labels.joined(separator: ","))))
        }
        components.percentEncodedQueryItems = items
        return components.url!
    }

    /// Percent-encodes a query-item value, including characters that
    /// `URLComponents.url` would leave unencoded (comma, `&`, `#`, `=`, `+`).
    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ",&=+#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Open the prefilled URL in the user's default browser. Returns true
    /// when NSWorkspace accepted the open; false when it rejected and we
    /// fell back to copying the URL to the clipboard.
    @discardableResult
    static func openNewIssue(title: String, body: String, labels: [String]) -> Bool {
        let url = newIssueURL(title: title, body: body, labels: labels)
        if NSWorkspace.shared.open(url) { return true }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        return false
    }
}
