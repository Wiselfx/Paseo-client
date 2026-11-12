#if canImport(UIKit)
import AVFoundation
import AVKit
import PaseoStore
import SwiftUI
import UIKit

// MARK: - VideoCard (G11 C3)

// NOTE: RemoteImagePipeline/G11: the poster shows first and the player is created on
// tap — never autoplay, never a player per card. One player at a time across the
// transcript (`MediaPlaybackCoordinator`); scrolling a player more than a screen away
// pauses it. Remote posters stream their first frame; local files download whole
// (≤ 64 MB, tap-gated past 20 MB) before the poster and the player exist.

/// A simulator recording, browser test or generated clip: poster card → inline AVKit
/// player on tap, in the same frame.
struct VideoCard: View {
    enum Input: Equatable {
        case local(path: String)
        case remote(url: String)
    }

    let input: Input

    @Environment(\.richActions) private var richActions
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.richViewportHeight) private var viewportHeight

    /// Stable identity across re-renders: the content key, not the card instance.
    private var cardID: String {
        switch input {
        case .remote(let url): "video:\(url)"
        case .local(let path): "video:local:\(path)"
        }
    }

    private var source: MediaSource? {
        switch input {
        case .remote(let urlString):
            return MediaPipeline.target(for: urlString).map(MediaSource.remote)
        case .local(let path):
            guard let workspaceID = richActions?.daemonWorkspaceID else { return nil }
            return .daemon(DaemonFileRef(workspaceID: workspaceID, path: path, revision: nil))
        }
    }

    private var fileName: String {
        switch input {
        case .remote(let urlString):
            return URL(string: urlString)?.lastPathComponent.nilIfEmpty ?? "video"
        case .local(let path):
            return (path as NSString).lastPathComponent.nilIfEmpty ?? "video"
        }
    }

    @State private var poster: UIImage?
    @State private var aspectRatio: CGFloat = 16.0 / 9.0
    @State private var duration: Double?
    @State private var knownBytes: Int64?
    @State private var tappedLoad = false
    @State private var localFileURL: URL?
    @State private var player: AVPlayer?
    @State private var showShare = false
    @State private var overLimit = false
    @State private var width: CGFloat = 0

    private var heightCap: CGFloat { viewportHeight * 0.6 }

    /// Reserved 16:9 until the track ratio arrives; one settle, at most.
    private var reservedAspect: CGFloat { aspectRatio }

    private var isPlaying: Bool { player != nil }

    private var policy: MediaFetchPolicy {
        mediaFetchPolicy(
            kind: .video, knownBytes: nil,
            condition: richActions?.linkCondition ?? .assumed)
    }

    /// The size reads the directory cache on the first pass: a remount shows it
    /// on frame one instead of flashing the bare title until the listing lands.
    private var resolvedBytes: Int64? {
        if let knownBytes { return knownBytes }
        guard case .daemon(let ref) = source,
            let cached = DaemonDirectoryCache.shared.cached(
                workspaceID: ref.workspaceID, dir: parentDirectory(of: ref.path)),
            let entry = cached.first(where: { entry in
                (entry.path as NSString).lastPathComponent
                    == (ref.path as NSString).lastPathComponent
            })
        else { return nil }
        return Int64(entry.size)
    }

    private var metaText: String? {
        var parts: [String] = []
        if let resolvedBytes { parts.append(Self.byteCount(resolvedBytes)) }
        if let duration { parts.append(Self.timestamp(duration)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static func byteCount(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    private static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        Group {
            if overLimit {
                PaseoCard(content: capBox)
            } else {
                PaseoMediaCard(
                    media: stage,
                    header: PaseoCardHeader(title: fileName, meta: metaText))
            }
        }
            .task(id: cardID) { await prepare() }
            .onDisappear { tearDown() }
            .onScrollVisibilityChange(threshold: 0.05) { visible in
                // Far enough off screen: pause rather than let audio keep running.
                if !visible { pause() }
            }
            .onChange(of: MediaPlaybackCoordinator.shared.activeID) { _, activeID in
                if activeID != cardID { pause() }
            }
            .paseoCardMenu(
                onShare: shareTarget != nil ? { showShare = true } : nil,
                copyTitle: "Copy link",
                copyText: copyLinkText,
                externalTitle: "Open in Files",
                externalURL: nil,
                filePath: filePath)
            .paseoCardAccessibility(kind: "Video", title: fileName, meta: metaText, isButton: true)
            .accessibilityHint("Plays the video")
            .sheet(isPresented: $showShare) {
                if let shareTarget {
                    ActivityView(items: [shareTarget])
                }
            }
    }

    private var shareTarget: URL? { localFileURL }

    private var copyLinkText: String? {
        if case .remote(let url) = input { url } else { nil }
    }

    private var filePath: String? {
        if case .local(let path) = input { path } else { nil }
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        if let player {
            InlineAVPlayer(player: player)
                .frame(maxWidth: .infinity)
                .aspectRatio(reservedAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: heightCap)
                .transition(.opacity)
        } else if let poster {
            ZStack {
                Image(uiImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: heightCap)
                    .clipped()
                Circle()
                    .fill(Palette.mediaBadge)
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.paseo(.body, weight: .semibold))
                            .foregroundStyle(Palette.onMediaBadge)
                            .offset(x: 1)
                            .accessibilityHidden(true)
                    }
                if let duration {
                    Text(Self.timestamp(duration))
                        .font(.paseo(.caption, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.onMediaBadge)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Metrics.overlayVPadding)
                        .background(Palette.mediaBadge, in: .capsule)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(Space.sm)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(reservedAspect, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: heightCap)
            .clipped()
            .contentShape(.rect)
            .onTapGesture { startTappedPlayback() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Play video")
        } else if showsTapBox {
            tapBox
        } else if loadFailed {
            failureBox
        } else {
            Rectangle()
                .fill(Palette.codeSurface)
                .aspectRatio(reservedAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: heightCap)
                .overlay {
                    ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                }
                .accessibilityLabel("Loading video")
        }
    }

    /// The 64 MB cap row (G10 C10 pattern): no download, Share and Show in Files only.
    private var capBox: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Image(systemName: "film")
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Too large to preview")
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(fileName)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
            if let filePath {
                Button("Files") {
                    richActions?.openFile(filePath)
                }
                .buttonStyle(.plain)
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(minWidth: Metrics.hitSize, minHeight: Metrics.hitSize)
                .accessibilityLabel("Show in Files")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, minHeight: Metrics.rowCardMinHeight - Space.md * 2, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video too large to preview, \(fileName)")
    }

    private var downloadLabel: String {
        if let knownBytes { return "Tap to download · \(Self.byteCount(knownBytes))" }
        return "Tap to download"
    }

    /// The §12 tap state: the reserved box, the size when known, one tap to fetch.
    private var tapBox: some View {
        Button {
            Haptics.light()
            tappedLoad = true
            Task { @MainActor in
                await prepare()
                // An explicit tap plays as soon as the poster is ready: never
                // autoplay on appear, always play on the reader's tap.
                if poster != nil, !isPlaying {
                    await play()
                }
            }
        } label: {
            Rectangle()
                .fill(Palette.codeSurface)
                .aspectRatio(reservedAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: heightCap)
                .overlay {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "arrow.down.circle")
                            .font(.glyph(.large, weight: .light))
                            .foregroundStyle(Palette.secondaryInk)
                        Text(downloadLabel)
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(fileName)
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, Space.md)
                }
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Download video \(fileName)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Downloads the video")
    }

    /// The poster stays local-only knowledge: after a failure the box owns the
    /// error with Retry instead of spinning forever.
    @State private var loadFailed = false

    private var showsTapBox: Bool {
        guard !tappedLoad, !isPlaying, poster == nil, !overLimit, !loadFailed else { return false }
        return policy == .tapToDownload || posterPolicy == .tap
    }

    /// The poster rule (§12): remote posters stream (no download), so they ride
    /// along wherever metadata does — but `AVAssetImageGenerator` on a remote URL
    /// can pull megabytes (moov at the end of the file), so auto-fetch runs on
    /// cheap links only (Wi-Fi/wired, direct); cellular, relay and constrained
    /// links wait for the tap. Local posters need the whole file, so they follow
    /// the `.daemonImage` cap, not a private threshold. `.full` = inline player
    /// now; `.tap` = wait for the tap.
    private enum PosterPolicy { case full, tap }

    private var posterPolicy: PosterPolicy {
        if tappedLoad { return .full }
        let condition = richActions?.linkCondition ?? .assumed
        if condition.offline || condition.constrained { return .tap }
        guard let source else { return .tap }
        switch source {
        case .remote:
            switch condition.interface {
            case .wifi, .wired where !condition.isRelay:
                return .full
            case .wifi, .wired, .cellular, .other:
                return .tap
            }
        case .daemon:
            guard
                let cap = mediaDownloadCap(
                    kind: .daemonImage, condition: condition)
            else { return .tap }
            guard let knownBytes else { return .tap }
            return knownBytes <= cap ? .full : .tap
        case .data:
            // This card's source never yields inline bytes (inputs are remote or
            // daemon only): nothing to poster from, wait for the tap.
            return .tap
        }
    }

    /// The honest failure: the reserved box, one line, and Retry in place.
    private var failureBox: some View {
        Button {
            loadFailed = false
            startTappedPlayback()
        } label: {
            Rectangle()
                .fill(Palette.codeSurface)
                .aspectRatio(reservedAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: heightCap)
                .overlay {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "film")
                            .font(.glyph(.large, weight: .light))
                            .foregroundStyle(Palette.secondaryInk)
                        Text("Couldn't load video")
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text("Retry")
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.accentInk)
                    }
                    .padding(.horizontal, Space.md)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Couldn't load video \(fileName)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Retries loading the video")
    }

    // MARK: Loading

    /// The poster streams for remote URLs; local files download whole first (the
    /// daemon has no range reads). Nothing starts until a tap on metered links.
    @MainActor
    private func prepare() async {
        // Local size first: the listing is cheap, the bytes are not. The poster gate
        // then decides from the size table above.
        if let source, case .daemon(let ref) = source, knownBytes == nil {
            knownBytes = await daemonFileSize(ref: ref)
            guard !Task.isCancelled else { return }
        }
        guard posterPolicy == .full else { return }
        await loadPosterIfNeeded()
    }

    private func startTappedPlayback() {
        tappedLoad = true
        Haptics.light()
        Task { @MainActor in
            if poster == nil {
                await loadPosterIfNeeded()
            }
            await play()
        }
    }

    @MainActor
    private func loadPosterIfNeeded() async {
        guard poster == nil, let source else { return }
        switch source {
        case .remote(let url):
            await loadRemotePoster(url: url)
        case .daemon(let ref):
            await loadLocalPoster(ref: ref)
        case .data:
            // Unreachable (see `posterPolicy`): leave the reserved box alone.
            return
        }
    }

    @MainActor
    private func loadRemotePoster(url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let (image, duration) = await posterFrame(for: asset) else {
            loadFailed = true
            return
        }
        guard !Task.isCancelled else { return }
        poster = image
        if duration > 0 { self.duration = duration }
        if image.size.height > 0 {
            withAnimation(Motion.fade.resolved(reduceMotion: reduceMotion)) {
                aspectRatio = image.size.width / image.size.height
            }
        }
    }

    @MainActor
    private func loadLocalPoster(ref: DaemonFileRef) async {
        if let knownBytes, knownBytes > MediaPipeline.maxDaemonBytes {
            // Past the socket cap: the 64 MB cap row, Share and Show in Files only.
            overLimit = true
            return
        }
        let result = await MediaPipeline.shared.fetchDaemonFile(
            ref: ref, maxBytes: Int(MediaPipeline.maxDaemonBytes))
        switch result {
        case .bytes(let fetched):
            // The file lands in the cache off main; the card only holds the URL.
            guard
                let fileURL = await MediaPipeline.cacheDaemonFile(
                    data: fetched.data, ref: ref)
            else {
                loadFailed = true
                return
            }
            localFileURL = fileURL
        case .tooLarge:
            overLimit = true
            return
        case .unavailable:
            loadFailed = true
            return
        }
        guard let fileURL = localFileURL else { return }
        let asset = AVURLAsset(url: fileURL)
        guard let (image, duration) = await posterFrame(for: asset) else { return }
        guard !Task.isCancelled else { return }
        poster = image
        if duration > 0 { self.duration = duration }
        if image.size.height > 0 {
            withAnimation(Motion.fade.resolved(reduceMotion: reduceMotion)) {
                aspectRatio = image.size.width / image.size.height
            }
        }
    }

    /// The size reads the directory cache on the first pass (body's `resolvedBytes`)
    /// and fills it in here, coalesced with every other card in the directory.
    private func daemonFileSize(ref: DaemonFileRef) async -> Int64? {
        guard let list = richActions?.listDaemonDirectory else { return nil }
        guard
            let fetched = await DaemonDirectoryCache.shared.entries(
                workspaceID: ref.workspaceID, dir: parentDirectory(of: ref.path), fetch: list)
        else { return nil }
        let base = (ref.path as NSString).lastPathComponent
        return fetched.first(where: { ($0.path as NSString).lastPathComponent == base })
            .map { Int64($0.size) }
    }

    private func parentDirectory(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    /// The first non-black frame at 1 s, off main, at display width. Nil when the
    /// track has no readable frame (the card keeps its 16:9 box).
    private func posterFrame(for asset: AVURLAsset) async -> (UIImage, Double)? {
        await Task.detached(priority: .userInitiated) { () -> (UIImage, Double)? in
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 960)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            do {
                let duration = try? await asset.load(.duration).seconds
                let time = CMTime(seconds: min(1, (duration ?? 2) / 2), preferredTimescale: 600)
                let (cgImage, _) = try await generator.image(at: time)
                return (UIImage(cgImage: cgImage), duration ?? 0)
            } catch {
                return nil
            }
        }.value
    }

    // MARK: Playback

    @MainActor
    private func play() async {
        let url: URL?
        switch source {
        case .remote(let remoteURL): url = remoteURL
        case .daemon: url = localFileURL
        case .data:
            // Unreachable (see `posterPolicy`): nothing staged to play.
            url = nil
        case nil: url = nil
        }
        guard let url else { return }
        await MediaAudioSession.activateForPlayback()
        let player = AVPlayer(url: url)
        if let resumeAt = MediaPlaybackCoordinator.shared.position(for: cardID), resumeAt > 1 {
            await player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
        }
        self.player = player
        MediaPlaybackCoordinator.shared.play(cardID)
        player.play()
    }

    @MainActor
    private func pause() {
        guard let player else { return }
        MediaPlaybackCoordinator.shared.remember(
            position: player.currentTime().seconds, for: cardID)
        player.pause()
        // The session goes back to ambient with playback, so later UI sounds
        // respect the silent switch again (H1 restores the same after voice).
        Task { @MainActor in
            await MediaAudioSession.deactivateAfterPlayback()
        }
    }

    @MainActor
    private func tearDown() {
        if player != nil {
            pause()
            player = nil
            MediaPlaybackCoordinator.shared.stop(cardID)
        }
    }
}

/// Inline AVKit: native transport controls, PiP and full screen come only from AVKit.
private struct InlineAVPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
