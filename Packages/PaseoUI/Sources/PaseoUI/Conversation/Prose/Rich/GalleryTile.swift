#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One tile of `RichGalleryCard`'s grid: a cropped thumbnail inside a plain button that opens the
/// viewer at this index, or retries a failed fetch. On the last visible tile of a longer set,
/// `moreCount` draws the "+N" scrim inside the same button's label, so the tile stays one
/// VoiceOver element and its tap (including the failed-tile retry) is never swallowed.
struct GalleryTile: View {
    let image: RichImage
    let index: Int
    let count: Int
    let aspect: CGFloat
    /// What the tile draws: the stored thumbnail, or the decoded cache's on the first pass.
    let displayed: UIImage?
    /// The stored thumbnail, the one Share and Save to Photos act on.
    let saved: UIImage?
    let failed: Bool
    let moreCount: Int?
    let sourceID: String
    let namespace: Namespace.ID
    let onOpen: () -> Void
    /// A failed tile retries on tap: the reader's explicit fetch.
    let onRetry: () -> Void
    let onShare: (UIImage) -> Void

    var body: some View {
        Button(action: tap) {
            // The box decides the size; the picture is drawn over it and can never push the row
            // wider (a `.fill` image proposes its pixel size to its parent).
            Rectangle().fill(Palette.codeSurface)
                .overlay {
                    if let displayed {
                        Image(uiImage: displayed)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    } else if failed {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.glyph(.regular, weight: .light))
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityLabel("Couldn't load image")
                    }
                }
                .overlay {
                    if let moreCount {
                        Color.black.opacity(0.55)
                        Text("+\(moreCount)")
                            .font(.paseo(.headline))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                .aspectRatio(aspect, contentMode: .fit)
                .clipped()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: sourceID, in: namespace)
        .paseoCardMenu(
            onShare: shareAction,
            copyTitle: "Copy link",
            copyText: copyText,
            saveImage: saved,
            externalTitle: externalTitle,
            externalURL: externalURL,
            filePath: filePath)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(accessibilityHint)
    }

    private var shareAction: (() -> Void)? {
        guard let saved else { return nil }
        return { onShare(saved) }
    }

    private var accessibilityHint: String {
        moreCount == nil ? "Opens the image full screen" : "Opens the images full screen"
    }

    private func tap() {
        if failed { onRetry() } else { onOpen() }
    }

    /// "Image 2 of 5, name", with the hidden-count scrim folded in on the last tile.
    private var accessibilityText: String {
        let name = image.alt.isEmpty ? Self.fileName(for: image) : image.alt
        let text = "Image \(index + 1) of \(count), \(name)"
        guard let moreCount else { return text }
        return "\(text), \(moreCount) more images"
    }

    private var copyText: String? {
        if case .remote(let url) = image.source { url } else { nil }
    }

    private var externalTitle: String? {
        if case .remote = image.source { "Open link" } else { nil }
    }

    private var externalURL: URL? {
        if case .remote(let urlString) = image.source {
            return MediaPipeline.target(for: urlString).flatMap { url in
                guard url.scheme == "http" || url.scheme == "https" else { return nil }
                return url
            }
        }
        return nil
    }

    private var filePath: String? {
        if case .local(let path) = image.source { path } else { nil }
    }

    /// The name the viewer and VoiceOver use: the last path component, else "image".
    static func fileName(for image: RichImage) -> String {
        let name: String
        switch image.source {
        case .remote(let url):
            name = MediaPipeline.target(for: url)?.lastPathComponent ?? ""
        case .local(let path):
            name = (path as NSString).lastPathComponent
        }
        return name.isEmpty ? "image" : name
    }
}
#endif
