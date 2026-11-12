#if canImport(UIKit)
import AVFoundation
import PaseoStore
import SwiftUI
import UIKit

// MARK: - AudioRow (G4 C4)

// NOTE: RemoteImagePipeline/G11: an audio file as a 56 pt row card — play/pause, a
// 48-bar waveform computed off main, elapsed/total in mono digits, the file name
// above. One player at a time (`MediaPlaybackCoordinator`); scrolling far away pauses.
// The waveform scrubs with a drag (a bounded control gesture with start/end haptics,
// not a finger-tracked surface). No background-audio mode: playback stops with the app.

/// One audio file: a row card that plays in place.
struct AudioRow: View {
    enum Input: Equatable {
        case local(path: String)
        case remote(url: String)
    }

    let input: Input

    @Environment(\.richActions) private var richActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bars: [CGFloat] = []
    @State private var duration: Double = 0
    @State private var elapsed: Double = 0
    @State private var playing = false
    /// Local files play their cached bytes (`AVAudioPlayer(contentsOf:)` on main,
    /// fast once the file exists); remote audio streams (`AVPlayer`) and never
    /// downloads the whole file. One row, one player: the coordinator stops the other.
    @State private var localPlayer: AVAudioPlayer?
    @State private var streamPlayer: AVPlayer?

    private var isPlaying: Bool { playing }

    private var cardID: String {
        switch input {
        case .remote(let url): "audio:\(url)"
        case .local(let path): "audio:local:\(path)"
        }
    }

    private var fileName: String {
        switch input {
        case .remote(let url):
            return URL(string: url)?.lastPathComponent.nilIfEmpty ?? "audio"
        case .local(let path):
            return (path as NSString).lastPathComponent.nilIfEmpty ?? "audio"
        }
    }

    private var policy: MediaFetchPolicy {
        mediaFetchPolicy(
            kind: .audio, knownBytes: nil,
            condition: richActions?.linkCondition ?? .assumed)
    }

    private var timeText: String {
        "\(Self.timestamp(elapsed)) / \(Self.timestamp(duration))"
    }

    private static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        PaseoCard(content:
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(fileName)
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Space.sm) {
                    Button {
                        togglePlay()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.paseo(.body, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .disabled(policy == .cacheOnly)
                    .accessibilityLabel(isPlaying ? "Pause audio" : "Play audio")
                    .accessibilityHint(fileName)
                    waveform
                    Text(timeText)
                        .font(.paseo(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                        .accessibilityLabel(
                            "Elapsed \(Self.timestamp(elapsed)) of \(Self.timestamp(duration))")
                }
            }
            .frame(minHeight: Metrics.rowCardMinHeight - Space.md * 2, alignment: .leading)
            .contentShape(.rect))
            .paseoCardAccessibility(kind: "Audio", title: fileName, meta: timeText, isButton: true)
            .onDisappear { pause() }
            .onScrollVisibilityChange(threshold: 0.05) { visible in
                // Far enough off screen: pause rather than keep playing unseen.
                if !visible { pause() }
            }
            .onChange(of: MediaPlaybackCoordinator.shared.activeID) { _, activeID in
                if activeID != cardID { pause() }
            }
            .task(id: isPlaying) {
                // The elapsed clock: one small body pass per second while playing,
                // never per frame.
                guard isPlaying else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if let localPlayer, localPlayer.isPlaying {
                        elapsed = localPlayer.currentTime
                    } else if let streamPlayer, streamPlayer.rate > 0 {
                        elapsed = streamPlayer.currentTime().seconds
                        // The stream's duration arrives after playback starts.
                        if duration <= 0,
                            let total = streamPlayer.currentItem?.duration.seconds,
                            total.isFinite, total > 0
                        {
                            duration = total
                        }
                    } else {
                        break
                    }
                }
            }
    }

    // MARK: Waveform

    /// 48 RMS buckets across the whole file, computed off main once per card.
    /// Tap seeks (a tap never steals the transcript's vertical scroll; a drag would —
    /// R-3), and VoiceOver adjusts in 10 s steps.
    private var waveform: some View {
        GeometryReader { proxy in
            let count = max(bars.count, 1)
            let step = max(proxy.size.width / CGFloat(count), 1)
            let played = duration > 0 ? elapsed / duration : 0
            Canvas { context, size in
                for (index, level) in bars.enumerated() {
                    let x = CGFloat(index) * step + 1
                    let height = max(2, level * size.height)
                    let y = (size.height - height) / 2
                    let playedBar = Double(index) / Double(count) <= played
                    context.fill(
                        Path(CGRect(x: x, y: y, width: max(step - 2, 1), height: height)),
                        with: .color(playedBar ? Palette.ink : Palette.tertiaryInk))
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                guard duration > 0, proxy.size.width > 0 else { return }
                seek(to: Double(min(max(value.location.x / proxy.size.width, 0), 1))
                    * duration)
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio waveform")
            .accessibilityAdjustableAction { direction in
                scrubBy(seconds: direction == .increment ? 10 : -10)
            }
            .accessibilityValue(timeText)
        }
        .frame(height: Metrics.audioWaveformHeight)
        .frame(maxWidth: .infinity)
    }

    private func scrubBy(seconds: Double) {
        seek(to: max(0, elapsed + seconds))
    }

    // MARK: Playback

    private func togglePlay() {
        Haptics.light()
        if isPlaying {
            pause()
            MediaPlaybackCoordinator.shared.stop(cardID)
        } else {
            Task { @MainActor in
                await ensurePlayer()
                guard localPlayer != nil || streamPlayer != nil else { return }
                MediaPlaybackCoordinator.shared.play(cardID)
                await MediaAudioSession.activateForPlayback()
                localPlayer?.volume = 1
                localPlayer?.play()
                streamPlayer?.play()
                playing = true
            }
        }
    }

    /// No Now Playing entry: without `MPRemoteCommandCenter` handlers the Lock
    /// Screen controls would do nothing, and there is no background audio.
    @MainActor
    private func pause() {
        if let localPlayer {
            MediaPlaybackCoordinator.shared.remember(
                position: localPlayer.currentTime, for: cardID)
            localPlayer.pause()
        }
        if let streamPlayer {
            let position = streamPlayer.currentTime().seconds
            if position.isFinite {
                MediaPlaybackCoordinator.shared.remember(position: position, for: cardID)
            }
            streamPlayer.pause()
        }
        playing = false
        if MediaPlaybackCoordinator.shared.activeID == cardID {
            MediaPlaybackCoordinator.shared.stop(cardID)
        }
        Task { @MainActor in
            await MediaAudioSession.deactivateAfterPlayback()
        }
    }

    private func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        if let localPlayer {
            localPlayer.currentTime = clamped
            elapsed = localPlayer.currentTime
        } else if let streamPlayer {
            streamPlayer.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
            elapsed = clamped
        }
    }

    /// Nothing starts until the tap: local files decode their waveform off main and
    /// play their cached bytes; remote audio streams (never a whole-file download,
    /// which would skip the UA, the policy and the caps).
    @MainActor
    private func ensurePlayer() async {
        switch input {
        case .local: await ensureLocalPlayer()
        case .remote: ensureStreamPlayer()
        }
    }

    @MainActor
    private func ensureLocalPlayer() async {
        if localPlayer != nil { return }
        guard case .local(let path) = input,
            let workspaceID = richActions?.daemonWorkspaceID
        else { return }
        let ref = DaemonFileRef(workspaceID: workspaceID, path: path, revision: nil)
        guard
            case .bytes(let fetched) = await MediaPipeline.shared.fetchDaemonFile(
                ref: ref, maxBytes: Int(MediaPipeline.maxDaemonBytes))
        else { return }
        guard !Task.isCancelled else { return }
        // The bytes land in the cache file off main; the player opens it on main
        // (fast once the file exists), so no player ever crosses isolation.
        guard let fileURL = await MediaPipeline.cacheDaemonFile(data: fetched.data, ref: ref)
        else { return }
        guard !Task.isCancelled else { return }
        // Detached work returns values only: the bars. The file stays in the cache.
        bars = await Task.detached(priority: .userInitiated) {
            Self.waveformBuckets(fileURL: fileURL)
        }.value
        guard !Task.isCancelled else { return }
        guard let player = try? AVAudioPlayer(contentsOf: fileURL) else { return }
        player.prepareToPlay()
        duration = player.duration
        localPlayer = player
        elapsed = 0
    }

    @MainActor
    private func ensureStreamPlayer() {
        if streamPlayer != nil { return }
        guard case .remote(let urlString) = input,
            let url = URL(string: urlString)
        else { return }
        // The waveform would need the full bytes: a flat placeholder instead.
        bars = Array(repeating: 0.05, count: Metrics.audioBarCount)
        streamPlayer = AVPlayer(url: url)
        elapsed = 0
    }

    /// `audioBarCount` RMS buckets over the whole file, read in chunks off main.
    /// A missing or unreadable file gets a flat line instead of an error state.
    private nonisolated static func waveformBuckets(fileURL: URL) -> [CGFloat] {
        let barCount = Metrics.audioBarCount
        let flat = Array(repeating: CGFloat(0.05), count: barCount)
        guard let file = try? AVAudioFile(forReading: fileURL) else { return flat }
        let totalFrames = file.length
        guard totalFrames > 0 else { return flat }
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate,
                channels: min(file.fileFormat.channelCount, 2), interleaved: false)
        else { return flat }
        // `AVAudioFramePosition` is `Int64`, `AVAudioFrameCount` is `UInt32`:
        // convert explicitly, clamped, never trapping on the last partial chunk.
        let chunkFrames = AVAudioFrameCount(max(Int64(4096), totalFrames / max(Int64(barCount * 4), 1)))
        var buckets: [Float] = []
        buckets.reserveCapacity(barCount * 4)
        var remaining = totalFrames
        while remaining > 0 {
            let frames = AVAudioFrameCount(min(remaining, Int64(chunkFrames)))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
            do {
                try file.read(into: buffer, frameCount: frames)
            } catch {
                break
            }
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { continue }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) {
                let sample = channel[index]
                sum += sample * sample
            }
            buckets.append(sqrt(sum / Float(buffer.frameLength)))
            remaining -= AVAudioFramePosition(buffer.frameLength)
        }
        guard !buckets.isEmpty else { return flat }
        let perBar = max(1, buckets.count / barCount)
        return (0..<barCount).map { index in
            let upper = min((index + 1) * perBar, buckets.count)
            let peak = buckets[(index * perBar)..<upper].max() ?? 0
            return CGFloat(min(max(peak * 1.6, 0.05), 1.0))
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
