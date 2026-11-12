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

    /// Returns the HTML with the offline CSP applied, right after `<head>` (or in a
    /// prepended `<head>` when there is none). Always injected, even when the document
    /// carries its own policy: an author's permissive `connect-src *` must not opt out,
    /// and multiple CSPs are all enforced (the effective policy is their intersection),
    /// so ours only ever narrows. Idempotent on our own meta.
    public static func inject(into html: String) -> String {
        if html.contains(meta) { return html }
        if let headRange = html.range(of: "<head", options: .caseInsensitive),
            let headEnd = html[headRange.upperBound...].firstIndex(of: ">")
        {
            let insertAt = html.index(after: headEnd)
            return String(html[..<insertAt]) + "\n" + meta + String(html[insertAt...])
        }
        return "<head>\n" + meta + "\n</head>\n" + html
    }
}
