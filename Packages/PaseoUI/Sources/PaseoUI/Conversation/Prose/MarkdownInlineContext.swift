import Foundation
import Markdown
import PaseoStore

/// How authored destinations are rewritten and whether bare URLs become links (J2).
/// A value with no home and no autolinking is the historical parse.
struct MarkdownInlineContext: Sendable {
    var home: String?
    var linkingBareURLs = true

    /// A link to a local file becomes the app's `paseo-file:` URL — exactly what a
    /// linkified bare path is turned into, and what `ChatController.fileLinkAction`
    /// opens in the file viewer, so a tap on `[clip.mp4](/media/clip.mp4)` now opens the
    /// file instead of nothing. A scheme-less web destination gains `https://`. Anchors
    /// and `mailto:` are untouched.
    func destination(_ raw: String) -> String {
        guard home != nil else { return raw }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("mailto:"),
            RichLocalSource.filePath(trimmed, home: home) != nil
        else { return raw }
        return FilePathLinks.url(forPath: trimmed)?.absoluteString ?? raw
    }

    /// An image keeps its bare form when it is already something the image pipeline
    /// loads — a local path (absolute, `~/`, `./`; the pipeline resolves those itself —
    /// see `ProseMarkdownImage`) or a remote image URL. Only a local path written
    /// relative to the agent's working directory gets expanded, because nothing else
    /// would resolve it.
    func imageSource(_ raw: String) -> String {
        guard let home else { return raw }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") || trimmed.hasPrefix("./") {
            return raw
        }
        if RichContentDetector.isRemoteImageURL(trimmed) { return raw }
        guard case .file(let path)? = RichLocalSource.image(trimmed, home: home) else { return raw }
        return path
    }
}
