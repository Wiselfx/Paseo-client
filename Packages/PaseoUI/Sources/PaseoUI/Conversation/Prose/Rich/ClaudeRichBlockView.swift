#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// Routes one detector block to its renderer, in document order (the caller iterates).
/// Actions and the workspace image loader arrive from `RichActions` in the environment (G1
/// §1.2, R-2): this router and every card below it take values only.
struct ClaudeRichBlockView: View {
    let block: RichContentBlock

    var body: some View {
        switch block {
        case .linkCard(let url, _):
            // GitHub links get their own card (G9 C7/C13); everything else keeps the
            // metadata card.
            if let parsed = GitHubURL.parse(url) {
                RichGitHubCard(url: url, parsed: parsed)
            } else {
                RichLinkCard(url: url)
            }
        case .youTubePlayer(let reference, _):
            YouTubeRichCard(reference: reference, full: true)
        case .youTubeInline(let reference, _):
            YouTubeRichCard(reference: reference, full: false)
        case .bareImageURL(let url, _):
            RichRemoteImage(urlString: url, alt: "")
        case .localImage(let path, let alt, _):
            RichLocalImage(path: path, alt: alt)
        case .imageGroup(let images, _):
            RichGalleryCard(images: images)
        case .localMedia(let path, let kind, _):
            switch kind {
            case .video: VideoCard(input: .local(path: path))
            case .audio: AudioRow(input: .local(path: path))
            }
        case .remoteMedia(let url, let kind, _):
            switch kind {
            case .video: VideoCard(input: .remote(url: url))
            case .audio: AudioRow(input: .remote(url: url))
            }
        case .localFileLink(let path, _):
            RichPathChip(path: path, glyph: "doc.text")
        case .rawSVG(let source, _):
            RichSVGCard(code: source)
        case .mermaid(let source, _):
            MermaidCard(code: source)
        case .htmlArtifact(let code, _):
            RichWebCard(code: code, kind: .html)
        case .mapCard(let reference, _):
            RichMapCard(reference: reference)
        }
    }
}
#endif
