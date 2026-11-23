#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit
import WebKit

// MARK: - ArtifactDocument (G4 C9, G5 C8)

// NOTE: RemoteImagePipeline/G4: G4 ships the mermaid kind; G5 adds svg/html
// and grows this page (title extraction, Reload, Share as .html, Preview entries).
// NOTE: RemoteImagePipeline/G5: no viz bridges (`sendPrompt`/`saveState`/`loadState`)
// on this page — they do not exist in the inline card either (verified by grep:
// `SandboxedHTMLView` carries only the height reporter, and the reference's bridge
// protocol was never ported). The page hosts the identical document, so bridges land
// in both places at once when they are built (with the composer steer path).

/// One full-screen artifact: values only (R-2). The card builds it; the controller
/// presents it; the viewer never refetches. Identity equality only: the bitmap is
/// payload, not identity (like `MediaViewerItem`).
struct ArtifactDocument: Identifiable, Equatable, @unchecked Sendable {
    static func == (lhs: ArtifactDocument, rhs: ArtifactDocument) -> Bool {
        lhs.id == rhs.id
    }

    enum Kind: Equatable, Sendable {
        /// A rendered diagram: the live vector SVG plus the snapshot for Share.
        case mermaid(source: String, svg: String?, snapshot: UIImage?)
        /// A raw `<svg>` block.
        case svg(source: String)
        /// An html fence, or a `.html` file: a full document when the source carries
        /// `<html>`, otherwise a fragment wrapped in the offline shell on load.
        case html(source: String, fileName: String?)
    }

    var kind: Kind
    /// The image the card already drew, for Share when the kind has one.
    var shareImage: UIImage?

    var id: String {
        switch kind {
        case .mermaid(let source, _, _): "mermaid:\(source.hashValue)"
        case .svg(let source): "svg:\(source.hashValue)"
        case .html(let source, let fileName):
            "html:\(fileName ?? ""):\(source.hashValue)"
        }
    }

    /// The page title: the document's own `<title>`/`<h1>` for HTML, upstream's
    /// wording where it exists (`en.ts:325`), the existing card copy otherwise.
    var title: String {
        switch kind {
        case .mermaid: "Diagram"
        case .svg: "SVG"
        case .html(let source, let fileName):
            ArtifactTitle.extract(html: source) ?? fileName ?? "HTML"
        }
    }

    /// The live document the page hosts, in the app's scheme.
    func liveHTML(dark: Bool) -> String? {
        switch kind {
        case .mermaid(_, let svg, _):
            // Static SVG: scripts never run (the CSP has no `script-src`).
            guard let svg else { return nil }
            return RichHTMLDocument.artifactSVG(source: svg, dark: dark)
        case .svg(let source):
            return RichHTMLDocument.rawSVG(source: source, dark: dark)
        case .html(let source, _):
            return RichHTMLDocument.artifactHTML(source: source, dark: dark)
        }
    }

    /// The source the toggle shows.
    var sourceText: String {
        switch kind {
        case .mermaid(let source, _, _): source
        case .svg(let source): source
        case .html(let source, _): source
        }
    }

    /// Whether the document re-runs on Reload (scripted stages do; static SVG doesn't).
    var canReload: Bool {
        switch kind {
        case .mermaid, .svg: false
        case .html: true
        }
    }

    /// The exported file name: the title slugged, always `.html` (the export must open
    /// correctly in Safari in both schemes, so the scheme is baked in at export time).
    var shareFileName: String {
        let slug = title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined().split(separator: "-").joined(separator: "-")
        return (slug.isEmpty ? "artifact" : String(slug.prefix(48))) + ".html"
    }
}
#endif
