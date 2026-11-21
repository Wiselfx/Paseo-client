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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.richViewportHeight) private var viewportHeight
    @Environment(\.richProseWidth) private var proseWidth

    /// Stable identity across re-renders: the content key, not the card instance. The
    /// workspace is part of it so the card's `prepare` task re-runs when the agent snapshot
    /// names the workspace a restored chat was missing (V1.1).
    private var cardID: String {
        switch input {
        case .remote(let url):
            return "video:\(url)"
        case .local(let path):
            return "video:local:\(richActions?.daemonWorkspaceID ?? "-"):\(path)"
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
    /// The tap's load-and-play. Held so a second tap while it runs is ignored (it would build
    /// a second player and orphan the first) and so the card can cancel it when it goes away.
    @State private var playbackTask: Task<Void, Never>?
    /// Bumped per load: a cancelled load can finish after a newer tap started its own, and
    /// must not clear that load's handle.
    @State private var playbackGeneration = 0
    /// Bumped per tap: the trigger for the touch feedback.
    @State private var tapCount = 0

    private var heightCap: CGFloat { viewportHeight * 0.6 }

    /// The stage's width: the prose column when the transcript published one, else 0 (the
    /// flexible slot). Fixed, so the poster's box is decided before the file arrives.
    private var slotWidth: CGFloat { proseWidth }

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

    private static func byteCount(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let pattern: Duration.TimeFormatStyle.Pattern =
            total >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(total).formatted(.time(pattern: pattern))
    }

    var body: some View {
        Group {
            if overLimit {
                PaseoCard(content: VideoCapRow(fileName: fileName, filePath: filePath))
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
            // Once AVKit's player is on screen its transport controls must stay separate
            // elements: combining the card would hide them behind one "Video" button.
            .accessibilityElement(children: isPlaying ? .contain : .combine)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityAddTraits(isPlaying ? [] : .isButton)
            .accessibilityHint(isPlaying ? "" : "Plays the video")
            .paseoFeedback(.light, trigger: tapCount)
            .sheet(isPresented: $showShare) {
                if let shareTarget {
                    ActivityView(items: [shareTarget])
                }
            }
    }

    private var accessibilityTitle: String {
        (["Video", fileName] + (metaText.map { [$0] } ?? [])).filter { !$0.isEmpty }
            .joined(separator: ", ")
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
                .aspectRatio(reservedAspect, contentMode: .fit)
                .mediaSlot(width: slotWidth, heightCap: heightCap)
                .transition(.opacity)
        } else if let poster {
            VideoPosterStage(
                poster: poster, duration: duration, aspect: reservedAspect,
                slotWidth: slotWidth, heightCap: heightCap, reduceMotion: reduceMotion,
                action: startTappedPlayback)
        } else if showsTapBox {
            VideoTapToDownloadBox(
                label: downloadLabel, fileName: fileName, aspect: reservedAspect,
                slotWidth: slotWidth, heightCap: heightCap, reduceMotion: reduceMotion,
                action: startTappedDownload)
        } else if loadFailed {
            VideoLoadFailureBox(
                fileName: fileName, aspect: reservedAspect,
                slotWidth: slotWidth, heightCap: heightCap, retry: retryLoad)
        } else {
            Rectangle()
                .fill(Palette.codeSurface)
                .aspectRatio(reservedAspect, contentMode: .fit)
                .mediaSlot(width: slotWidth, heightCap: heightCap)
                .overlay {
                    VStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                        // A whole local file arrives in one daemon read, so there is no byte
                        // progress to report: say what is happening instead of a bare ring
                        // (V1.4). Remote posters stream and show the ring only.
                        if tappedLoad {
                            Text("Downloading...")
                                .font(.paseo(.caption))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
                .accessibilityLabel(tappedLoad ? "Downloading video" : "Loading video")
        }
    }

    private var downloadLabel: String {
        if let knownBytes { return "Tap to download · \(Self.byteCount(knownBytes))" }
        return "Tap to download"
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
            // A `where` in a multi-pattern case binds to its last pattern only: the relay check
            // has to be explicit, or a Wi-Fi relay link auto-fetched.
            case .wifi, .wired:
                return condition.isRelay ? .tap : .full
            case .cellular, .other:
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

    // MARK: Loading

    /// The poster streams for remote URLs; local files download whole first (the
    /// daemon has no range reads). Nothing starts until a tap on metered links.
    @MainActor
    private func prepare() async {
        guard let source else {
            // No workspace id yet: a restored chat draws before the agent snapshot (V1.1).
            // `cardID` carries the id, so this task re-runs when it lands; after an explicit
            // tap with still no source, say so instead of leaving a spinner.
            if tappedLoad { loadFailed = true }
            return
        }
        // Local size first: the listing is cheap, the bytes are not. The poster gate
        // then decides from the size table above.
        if case .daemon(let ref) = source, knownBytes == nil {
            knownBytes = await daemonFileSize(ref: ref)
            guard !Task.isCancelled else { return }
        }
        guard posterPolicy == .full else { return }
        await loadPosterIfNeeded()
    }

    private func startTappedPlayback() {
        guard playbackTask == nil else { return }
        tappedLoad = true
        tapCount += 1
        playbackGeneration += 1
        let generation = playbackGeneration
        playbackTask = Task { @MainActor in
            // Clear only our own handle: a cancelled earlier load may still finish.
            defer { if generation == playbackGeneration { playbackTask = nil } }
            if poster == nil {
                await loadPosterIfNeeded()
            }
            guard !Task.isCancelled else { return }
            await play()
        }
    }

    private func startTappedDownload() {
        guard playbackTask == nil else { return }
        tappedLoad = true
        tapCount += 1
        playbackGeneration += 1
        let generation = playbackGeneration
        playbackTask = Task { @MainActor in
            // Clear only our own handle: a cancelled earlier load may still finish.
            defer { if generation == playbackGeneration { playbackTask = nil } }
            await prepare()
            guard !Task.isCancelled else { return }
            // An explicit tap plays as soon as the poster is ready: never
            // autoplay on appear, always play on the reader's tap.
            if poster != nil, !isPlaying {
                await play()
            }
        }
    }

    private func retryLoad() {
        loadFailed = false
        startTappedPlayback()
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
        // The card went away, or another tap won, while the session and the seek were awaited.
        guard !Task.isCancelled, self.player == nil else { return }
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
        playbackTask?.cancel()
        playbackTask = nil
        if player != nil {
            pause()
            player = nil
            MediaPlaybackCoordinator.shared.stop(cardID)
        }
    }
}
extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
