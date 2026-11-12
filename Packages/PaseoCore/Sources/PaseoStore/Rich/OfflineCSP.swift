import Foundation

// MARK: - OfflineCSP (G5 artifact hardening)

// NOTE: RemoteImagePipeline/G5: chat artifacts stay offline. Documents the client builds
// (`visualize`, `rawSVG`, `artifactSVG`, `artifactHTML` shell) carry a no-network CSP by
// construction; this type covers the one case they cannot: an agent-written *full*
// document, which arrives with its own `<head>`. Injecting the meta is the second layer
// (the first is the `WKContentRuleList` on the rendering web view); the export shares
// the source as-is, which is correct — a file the user takes elsewhere is theirs.

/// A `connect-src 'none'` content security policy for chat documents, plus the
/// injection that applies it to full documents the client did not build.
public enum OfflineCSP {
    /// Chat artifacts may not reach the network: no fetch/XHR, beacons, external
    /// scripts, styles, images, fonts, media, frames or form posts.
    public static let meta = """
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        """

    /// Returns the HTML with the offline CSP applied. Documents that already carry a
    /// `Content-Security-Policy` meta are returned unchanged (idempotent: the builder
    /// docs keep their own copy). Otherwise the meta is injected right after `<head>`
    /// (or a `<head>` is prepended when there is none).
    public static func inject(into html: String) -> String {
        if html.range(of: "Content-Security-Policy", options: .caseInsensitive) != nil {
            return html
        }
        if let headRange = html.range(of: "<head", options: .caseInsensitive),
            let headEnd = html[headRange.upperBound...].firstIndex(of: ">")
        {
            let insertAt = html.index(after: headEnd)
            return String(html[..<insertAt]) + "\n" + meta + String(html[insertAt...])
        }
        return "<head>\n" + meta + "\n</head>\n" + html
    }
}
