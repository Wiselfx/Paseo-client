#if canImport(UIKit)
import SwiftUI
import UIKit
import VisionKit

// MARK: - MediaViewerItem (G3 §4.6)

// NOTE: RemoteImagePipeline/G3: `fullSource == nil` means the thumbnail *is* the full image
// (an SVG snapshot, a Files-panel bitmap). Nothing refetches in that case.

/// One page of the shared full-screen viewer: values only (R-2). The thumbnail is the
/// display-size pixels the card already holds, so the viewer opens instantly; the full
/// image streams in behind it (full-resolution off main, neighbours ±1 preloaded).
struct MediaViewerItem: Equatable, @unchecked Sendable {
    /// Stable per content: the URL string or daemon path. Drives pager identity.
    let id: String
    /// What the card already drew. Always present in practice; nil falls back to the fetch.
    let thumbnail: UIImage?
    /// Where the full image comes from. Nil renders the thumbnail at full size.
    let fullSource: MediaSource?
    let fileName: String
    let alt: String
    /// The daemon path, when there is one: enables Show in Files. Nil for remote content.
    let filePath: String?

    static func == (lhs: MediaViewerItem, rhs: MediaViewerItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Animated frames (G3: GIF/APNG animate here only)

// NOTE: RemoteImagePipeline/G3: stills stay stills everywhere; only this decoder animates,
// and only from bytes the pipeline already carried (`MediaPayload.fullData`, ≤ 8 MB).

/// Decodes the frames of a small animated image at display width, off main. Bounded
/// (48 frames) so a pathological GIF cannot eat the viewer; the caller runs it detached.
enum AnimatedImageDecoder {
    static let maxFrames = 48
    static let minFrameDuration = 0.02

    static func animatedImage(data: Data, pixelWidth: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = min(CGImageSourceGetCount(source), maxFrames)
        guard count > 1 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, 1),
        ]
        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        var duration = 0.0
        for index in 0..<count {
            guard
                let cgImage = CGImageSourceCreateThumbnailAtIndex(
                    source, index, options as CFDictionary)
            else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDelay(source: source, index: index)
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: max(duration, Double(frames.count) * minFrameDuration))
    }

    /// The GIF delay, else the floor. Unequal frame lengths collapse to the mean — the
    /// inaccuracy is invisible at these sizes; the alternative (a custom display-link player)
    /// is a second video stack for a sticker format. Non-GIF animation runs at the floor
    /// rather than freezing: there is no gate-verifiable per-frame delay API for APNG/WebP.
    private static func frameDelay(source: CGImageSource, index: Int) -> Double {
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any],
            let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0
        else { return minFrameDuration }
        return delay
    }
}

/// The cover transition: zoom from the exact thumbnail, or the system default under
/// Reduce Motion. A modifier (not a ternary): the two transition types do not mix.
/// Shared with the artifact page, which enters the same way.
struct MediaViewerTransition: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
    }
}

// MARK: - MediaViewerView (G3 §4.6)

/// The one full-screen viewer for every visual in the app (G3): chat images, galleries,
/// Mermaid snapshots, Files-panel images, inline prose images. A UIKit pager (R-3) does the
/// finger-tracked work — swipe between pages, pinch and double-tap zoom, drag-down dismiss —
/// and SwiftUI hosts the content plus this chrome, learning only open/closed, the page and
/// the few values the chrome draws (R-1).
///
/// Entrance is the system zoom from the exact thumbnail (`matchedTransitionSource` on the
/// card, `.navigationTransition(.zoom)` here); Reduce Motion gets the fade. VoiceOver hears
/// one announcement per page ("Image 2 of 5, alt") and Escape closes.
struct MediaViewerView: View {
    let items: [MediaViewerItem]
    /// The matched-transition source id, shared with the card's `matchedTransitionSource`.
    let sourceID: String
    let namespace: Namespace.ID
    let onClose: () -> Void

    @Binding var selection: Int

    @Environment(\.richActions) private var richActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var chromeVisible = true
    /// The current page's full image, reported by the pager. Drives Copy and Add to chat.
    @State private var currentImage: UIImage?
    /// Set by the pager's Live Text analysis (off main): the button appears only when found.
    @State private var liveTextAvailable = false
    @State private var liveTextMode = false
    @State private var shareImage: UIImage?

    private var clampedSelection: Int {
        min(max(selection, 0), max(items.count - 1, 0))
    }

    private var currentItem: MediaViewerItem? {
        guard items.indices.contains(clampedSelection) else { return nil }
        return items[clampedSelection]
    }

    var body: some View {
        ZStack {
            MediaViewerPager(
                items: items,
                selection: $selection,
                chromeVisible: $chromeVisible,
                currentImage: $currentImage,
                liveTextAvailable: $liveTextAvailable,
                liveTextMode: liveTextMode,
                onClose: onClose,
                reduceMotion: reduceMotion)
                .ignoresSafeArea()
            chrome
        }
        .background(.clear)
        .environment(\.colorScheme, .dark)
        // Clear so the drag can fade the UIKit backdrop onto the transcript behind.
        .presentationBackground(.clear)
        // Reduce Motion gets the system default cover transition (a cross-dissolve),
        // never the zoom: the two transition types cannot mix in one ternary.
        .modifier(MediaViewerTransition(sourceID: sourceID, namespace: namespace, reduceMotion: reduceMotion))
        .accessibilityAction(.escape) { onClose() }
        .onChange(of: selection) { _, _ in
            // One announcement per page; the label carries kind + position + alt (G3 §1.5).
            liveTextMode = false
            UIAccessibility.post(
                notification: .announcement, argument: pageAnnouncement)
        }
        .sheet(isPresented: Binding(
            get: { shareImage != nil },
            set: { if !$0 { shareImage = nil } }
        )) {
            if let shareImage {
                ActivityView(items: [shareImage])
            }
        }
        .accessibilityIdentifier("media.viewer")
    }

    private var pageAnnouncement: String {
        let position = items.count > 1 ? "Image \(clampedSelection + 1) of \(items.count)" : "Image"
        let alt = currentItem?.alt ?? ""
        return alt.isEmpty ? position : "\(position), \(alt)"
    }

    // MARK: Chrome

    @ViewBuilder
    private var chrome: some View {
        if chromeVisible {
            VStack {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
            .transition(.opacity)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.paseo(.body))
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .contentShape(.circle)
            }
            .glassEffect(in: .circle)
            .accessibilityLabel("Close viewer")
            .accessibilityIdentifier("media.viewer.close")
            Spacer(minLength: 8)
            if items.count > 1, let currentItem {
                Text("\(clampedSelection + 1) of \(items.count)")
                    .font(.paseo(.footnote))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityLabel(pageAnnouncement)
                    .accessibilityAddTraits(.isHeader)
            } else if let currentItem {
                Text(currentItem.fileName)
                    .font(.paseo(.footnote))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Balance: the close circle's width, so a lone title stays centred.
            Color.clear.frame(width: Metrics.hitSize, height: Metrics.hitSize)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.md)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            viewerButton(systemImage: "square.and.arrow.up", label: "Share image") {
                if let currentImage { shareImage = currentImage }
            }
            .disabled(currentImage == nil)
            viewerButton(systemImage: "doc.on.doc", label: "Copy image") {
                copyCurrentImage()
            }
            .disabled(currentImage == nil && currentItem?.fullSource == nil)
            viewerButton(systemImage: "photo", label: "Save to Photos") {
                if let currentImage {
                    if let richActions {
                        richActions.saveImage(currentImage)
                    } else {
                        UIImageWriteToSavedPhotosAlbum(currentImage, nil, nil, nil)
                    }
                }
            }
            .disabled(currentImage == nil)
            if currentItem?.filePath != nil {
                viewerButton(systemImage: "folder", label: "Show in Files") {
                    if let path = currentItem?.filePath {
                        richActions?.openFile(path)
                    }
                }
            }
            if liveTextAvailable {
                viewerButton(
                    systemImage: "text.viewfinder",
                    label: liveTextMode ? "Hide text" : "Show text"
                ) {
                    liveTextMode.toggle()
                }
            }
            viewerButton(systemImage: "plus.bubble", label: "Add to chat") {
                addCurrentToChat()
            }
            .disabled(currentImage == nil)
        }
        .glassEffect(in: .capsule)
        .padding(.horizontal, Space.md)
        .padding(.bottom, Space.md)
    }

    private func viewerButton(
        systemImage: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.paseo(.body))
                .frame(width: Metrics.viewerChromeButtonWidth, height: Metrics.hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }

    private func copyCurrentImage() {
        if let currentImage {
            if let richActions {
                richActions.copyImage(currentImage)
            } else {
                UIPasteboard.general.image = currentImage
                Haptics.light()
            }
        } else if case .remote(let url) = currentItem?.fullSource {
            // Nothing decoded yet: the link is all we honestly have.
            if let richActions {
                richActions.copyText(url.absoluteString)
            } else {
                UIPasteboard.general.string = url.absoluteString
                Haptics.light()
            }
        }
    }

    /// The composer attachment path (M6a): JPEG-encode off main, then hand the bytes to the
    /// tray, which decodes and uploads like a picked photo. The `UIImage` crossing uses
    /// the same `@unchecked Sendable` box the pipeline uses (immutable once decoded).
    private func addCurrentToChat() {
        guard let currentImage, let item = currentItem else { return }
        let fileName = item.fileName
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) {
                ImageBox(image: currentImage).image.jpegData(compressionQuality: 0.85)
            }.value
            guard let data else { return }
            if let richActions {
                richActions.addImageToChat(fileName, data)
            }
        }
    }

    private struct ImageBox: @unchecked Sendable {
        let image: UIImage
    }
}
#endif
