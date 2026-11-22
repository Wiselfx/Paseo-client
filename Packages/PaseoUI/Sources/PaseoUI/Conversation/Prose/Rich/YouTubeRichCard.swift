#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

// MARK: - YouTube (§1.2)

/// Thumbnail card at 16:9, full width; tapping swaps it in place for an inline player. The web
/// view is created by the tap, never for every card, and is destroyed when the card scrolls away.
/// "Open in YouTube" in the context menu keeps the old external path.
struct YouTubeRichCard: View {
    let reference: YouTubeReference
    let full: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.displayScale) private var displayScale
    @Environment(\.richActions) private var richActions

    /// The 16:9 card's still. Decoded once through the shared loader and cached by URL, so
    /// scrolling past and back does not re-download or re-flash it (H5 round 2: this used to be
    /// an uncached system image view, the same defect the image cards had).
    @State private var still: UIImage?
    @State private var stillFailed = false
    /// The card's real width, measured once per layout so the still is decoded at the size it
    /// is drawn at (never a guessed 320/430 pt).
    /// The card's measured width. Until its first layout the card reads the prose column's width
    /// (it spans the column), so a reused cell sizes it right in its first pass instead of
    /// settling a frame later, which moved the text below while the transcript scrolled.
    @State private var measuredWidth: CGFloat = 0
    @Environment(\.richProseWidth) private var proseWidth
    private var width: CGFloat { measuredWidth > 1 ? measuredWidth : proseWidth }
    /// The oEmbed title strip (C5): title + channel, cached by video id. Until it
    /// arrives (or when it fails) the strip shows the domain fallback, as before.
    @State private var videoTitle: String?
    @State private var videoChannel: String?

    private let playback = MediaPlaybackCoordinator.shared
    private var isPlaying: Bool { playback.activeID == reference.id }

    /// One decode per (URL, pixel bucket). Nil while playing — the player covers the still —
    /// and until the width is known.
    private var stillKey: String? {
        guard !isPlaying, width > 1 else { return nil }
        let pixels = MediaSizing.pixelWidth(points: width, scale: displayScale)
        return "\(RichContentDetector.youTubeThumbnailURL(id: reference.id))|\(pixels)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ZStack {
                if isPlaying {
                    InlineYouTubePlayer(referenceID: reference.id)
                        .accessibilityLabel(resolvedTitle ?? "YouTube video")
                        .transition(.opacity)
                } else {
                    YouTubeThumbnail(
                        still: still,
                        failed: stillFailed,
                        accessibilityText: resolvedTitle.map { "Play \($0)" } ?? "Play YouTube video",
                        onPlay: play)
                        .contextMenu {
                            Button("Open in YouTube", systemImage: "play.rectangle") { openInYouTube() }
                        }
                        // The box is already reserved by the card's 16:9 frame, so the still can
                        // land whenever.
                        .task(id: stillKey) { await loadStill() }
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: full ? .infinity : 320, alignment: .leading)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background { widthReader }
            .background(Color.black)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
            }
            .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: isPlaying)
            .onScrollVisibilityChange(threshold: 0.05) { visible in
                // Far enough off screen: destroy the player rather than let audio keep running.
                if !visible, isPlaying { playback.stop(reference.id) }
            }
            if full {
                YouTubeTitleStrip(
                    title: resolvedTitle,
                    channel: resolvedChannel,
                    id: reference.id,
                    isPlaying: isPlaying,
                    onClose: stopPlayback
                )
                .animation(
                    Motion.disclosure.resolved(reduceMotion: reduceMotion),
                    value: resolvedTitle != nil)
                .task(id: reference.id) { await loadTitle() }
            }
        }
        .frame(maxWidth: full ? .infinity : 320, alignment: .leading)
    }

    private func play() {
        playback.play(reference.id)
    }

    private func stopPlayback() {
        playback.stop(reference.id)
    }

    /// The card's inner width, measured on the frame it is actually drawn in. Published only
    /// when it changes; nothing here runs per scroll frame.
    private var widthReader: some View {
        // `onGeometryChange` on the clear background instead of a `GeometryReader` per card (W1): same
        // size, delivered at once and on change, written only when it differs.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if measuredWidth != newWidth { measuredWidth = newWidth }
            }
    }

    /// The title strip reads the cache on the first pass (remounts never flash the
    /// domain fallback); the fetch fills it in once, animated, on cheap links only.
    private var resolvedTitle: String? {
        videoTitle ?? YouTubeTitleCache.entry(for: reference.id)?.title
    }

    private var resolvedChannel: String? {
        videoChannel ?? YouTubeTitleCache.entry(for: reference.id)?.channel
    }

    /// YouTube's public oEmbed endpoint, fetched once per id and cached: the same
    /// third-party class as the thumbnail fetch, never the relay or the daemon.
    /// Gated like any other third-party metadata (§12): cheap links only.
    @MainActor
    private func loadTitle() async {
        if YouTubeTitleCache.entry(for: reference.id) != nil { return }
        guard
            mediaFetchPolicy(
                kind: .youTube, knownBytes: nil,
                condition: richActions?.linkCondition ?? .assumed) == .automatic
        else { return }
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(
                name: "url", value: RichContentDetector.youTubeWatchURL(id: reference.id)),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let endpoint = components?.url,
            let (data, _) = try? await MediaPipeline.fetchMetadataData(from: endpoint),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let title = json["title"] as? String, !title.isEmpty
        else { return }
        let channel = json["author_name"] as? String
        YouTubeTitleCache.store(title: title, channel: channel, for: reference.id)
        guard !Task.isCancelled else { return }
        videoTitle = title
        videoChannel = channel
    }

    /// One decode per URL, through the same loader (and cache) as every other remote image.
    /// A failed thumbnail is a decorative miss, not an error worth a card.
    @MainActor
    private func loadStill() async {
        guard width > 1, still == nil else { return }
        let url = RichContentDetector.youTubeThumbnailURL(id: reference.id)
        let outcome = await MediaPipeline.shared.load(
            urlString: url,
            pixelWidth: MediaSizing.pixelWidth(points: width, scale: displayScale))
        guard !Task.isCancelled else { return }
        switch outcome {
        case .image(let payload): still = payload.image
        case .failure: stillFailed = true
        case .svg: stillFailed = true
        }
    }

    private func openInYouTube() {
        if let target = URL(string: RichContentDetector.youTubeWatchURL(id: reference.id)) {
            openURL(target)
        }
    }
}
#endif
