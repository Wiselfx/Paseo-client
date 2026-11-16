import Foundation

/// The URL scheme a workspace HTML preview uses for its own files.
///
/// A preview document is loaded with `baseURL: nil`, so `./style.css`, `/logo.png` and
/// `fetch("data.json")` had nothing to resolve against and the page drew half of itself.
/// E3b injects `<base href="paseo-file://<workspace>/<dir>/">` and serves the scheme from the
/// checkout's read-only file API. This type is the whole security boundary: it turns a request
/// URL into a workspace-relative path, and refuses anything that leaves the workspace.
///
/// Pure and Foundation-only on purpose: the rules (`..`, encoded dot segments, the workspace
/// host) are unit-tested without a web view or a daemon.
public enum PreviewFileScheme {
    /// The scheme string registered with `WKWebViewConfiguration`.
    public static let name = "paseo-file"

    /// The largest resource the preview may load. A page can reference anything in the
    /// workspace; 16 MB is enough for a screenshot and too small to stall the daemon.
    public static let maxResourceBytes = 16 * 1024 * 1024

    /// `paseo-file://<workspaceId>/<path>` → `(workspaceId, path)`, with `path` normalised and
    /// inside the workspace. Nil for another scheme, a missing/other host, or an escaping path.
    public static func resolve(_ url: URL) -> (workspaceId: String, path: String)? {
        guard url.scheme?.lowercased() == name, let workspaceId = url.host, !workspaceId.isEmpty
        else { return nil }
        guard let path = relativePath(url.path) else { return nil }
        return (workspaceId, path)
    }

    /// Normalises a URL path to a workspace-relative one.
    ///
    /// The input is a decoded path (`URL.path` decodes once; a second decode would corrupt a
    /// file literally named `100%.txt`). Leading slashes are workspace-root relative
    /// (`/assets/app.css`); empty and `.` components are dropped; `..` pops, and a `..` with
    /// nothing left to pop escapes the root and returns nil. `%2e%2e` cannot smuggle an escape
    /// past this because Foundation decodes it to `..` before the split.
    public static func relativePath(_ path: String) -> String? {
        guard !path.contains("\0") else { return nil }
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    /// The `baseHref` for a file at `path`: its directory, as an absolute scheme URL ending in
    /// `/`, with each component percent-encoded so a space or `#` in a folder name still works.
    public static func baseHref(workspaceId: String, filePath: String) -> String {
        let directory = (filePath as NSString).deletingLastPathComponent
        var href = "\(name)://\(escaped(workspaceId))/"
        if !directory.isEmpty {
            href += escaped(directory) + "/"
        }
        return href
    }

    /// Percent-encodes each path component, leaving the `/` separators.
    private static func escaped(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
    }
}
