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
    @State private var width: CGFloat = 0
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
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if isPlaying {
                    InlineYouTubePlayer(referenceID: reference.id)
                        .accessibilityLabel("YouTube video \(reference.id)")
                        .transition(.opacity)
                } else {
                    thumbnail
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
                VStack(alignment: .leading, spacing: 2) {
                    if let title = resolvedTitle {
                        Text(title)
                            .font(.paseo(.callout))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "play")
                            .font(.glyph(.small, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                        Text(resolvedChannel ?? "youtube.com · \(reference.id)")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if isPlaying {
                            Button("Close") { playback.stop(reference.id) }
                                .font(.paseo(.caption, weight: .medium))
                                .foregroundStyle(Palette.secondaryInk)
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .animation(
                    Motion.disclosure.resolved(reduceMotion: reduceMotion),
                    value: resolvedTitle != nil)
                .task(id: reference.id) { await loadTitle() }
            }
        }
        .frame(maxWidth: full ? .infinity : 320, alignment: .leading)
    }

    private var thumbnail: some View {
        ZStack {
            if let still {
                Image(uiImage: still)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Palette.codeSurface)
                    .overlay {
                        if stillFailed {
                            Image(systemName: "photo")
                                .font(.glyph(.xlarge, weight: .light))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
            }

            Circle()
                .fill(Palette.mediaBadge)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.glyph(.regular, weight: .semibold))
                        .foregroundStyle(Palette.onMediaBadge)
                        .offset(x: 1)
                }
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .onTapGesture { playback.play(reference.id) }
        .contextMenu {
            Button("Open in YouTube", systemImage: "play.rectangle") { openInYouTube() }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Play YouTube video \(reference.id)")
        // The box is already reserved by the card's 16:9 frame, so the still can land whenever.
        .task(id: stillKey) { await loadStill() }
    }

    /// The card's inner width, measured on the frame it is actually drawn in. Published only
    /// when it changes; nothing here runs per scroll frame.
    private var widthReader: some View {
        // `onGeometryChange` on the clear background instead of a `GeometryReader` per card (W1): same
        // size, delivered at once and on change, written only when it differs.
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if width != newWidth { width = newWidth }
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
