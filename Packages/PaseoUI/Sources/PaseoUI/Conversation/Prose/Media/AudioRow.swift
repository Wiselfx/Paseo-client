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
    @State private var bars: [CGFloat] = []
    @State private var duration: Double = 0
    @State private var elapsed: Double = 0
    @State private var playing = false
    /// Local files play their cached bytes (`AVAudioPlayer(contentsOf:)` on main,
    /// fast once the file exists); remote audio streams (`AVPlayer`) and never
    /// downloads the whole file. One row, one player: the coordinator stops the other.
    @State private var localPlayer: AVAudioPlayer?
    @State private var streamPlayer: AVPlayer?
    /// A tap that could not load: the row says so instead of looking like a dead button,
    /// and the next tap retries (V1.4).
    @State private var loadFailure = false
    /// A tap while the bytes are on their way: the time slot says so once, not per frame.
    @State private var loading = false
    /// The tap's load-and-play. Held so a second tap while it runs is ignored (it would build
    /// a second player and orphan the first) and so the row can cancel it when it goes away.
    @State private var playTask: Task<Void, Never>?
    /// Bumped per load: a cancelled load can finish after a newer tap started its own, and
    /// must not clear that load's handle.
    @State private var playGeneration = 0
    /// Bumped per tap: the trigger for the touch feedback.
    @State private var playTaps = 0

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

    /// Offline with nothing loaded to play: the button is dimmed and the row says why. A player
    /// that is already loaded (or playing) keeps working, so Pause never goes dead.
    private var playUnavailable: Bool {
        policy == .cacheOnly && !isPlaying && localPlayer == nil && streamPlayer == nil
    }

    private var playHint: String {
        if loadFailure { return "Tries loading the audio again" }
        return isPlaying ? "Pauses the audio" : "Plays the audio"
    }

    private var playLabel: LocalizedStringKey {
        isPlaying ? "Pause audio" : "Play audio"
    }

    private var timeText: String {
        "\(Self.timestamp(elapsed)) / \(Self.timestamp(duration))"
    }

    private static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let pattern: Duration.TimeFormatStyle.Pattern =
            total >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(total).formatted(.time(pattern: pattern))
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
                    Button(action: togglePlay) {
                        Label(playLabel, systemImage: isPlaying ? "pause.fill" : "play.fill")
                            .labelStyle(.iconOnly)
                            .font(.paseo(.body, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .disabled(playUnavailable)
                    .accessibilityHint(playHint)
                    AudioWaveform(
                        bars: bars,
                        progress: duration > 0 ? elapsed / duration : 0,
                        valueText: timeText,
                        onSeek: { fraction in
                            guard duration > 0 else { return }
                            seek(to: fraction * duration)
                        },
                        onScrub: scrubBy(seconds:))
                    if loading {
                        Text("Loading…")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityLabel("Loading audio")
                    } else if loadFailure {
                        Text("Couldn't load audio")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.failureInk)
                            .lineLimit(1)
                            .accessibilityLabel("Couldn't load audio, \(fileName)")
                    } else if playUnavailable {
                        Text("No connection")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    } else {
                        Text(timeText)
                            .font(.paseo(.caption))
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityLabel(
                                "Elapsed \(Self.timestamp(elapsed)) of \(Self.timestamp(duration))")
                    }
                }
            }
            .frame(minHeight: Metrics.rowCardMinHeight - Space.md * 2, alignment: .leading)
            .contentShape(.rect))
            // The row keeps its play button and adjustable waveform as separate elements:
            // combining the card would swallow both, and its label would change every second.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Audio, \(fileName)")
            .paseoFeedback(.light, trigger: playTaps)
            .onDisappear {
                cancelPendingPlay()
                pause()
            }
            .onScrollVisibilityChange(threshold: 0.05) { visible in
                // Far enough off screen: pause rather than keep playing unseen.
                if !visible {
                    cancelPendingPlay()
                    pause()
                }
            }
            .onChange(of: MediaPlaybackCoordinator.shared.activeID) { _, activeID in
                if activeID != cardID {
                    // Another player took over: a load still in flight must not start over
                    // it. A cleared id (the other player just stopped) leaves a load alone.
                    if activeID != nil { cancelPendingPlay() }
                    pause()
                }
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

    /// 10 s steps for VoiceOver on the waveform, and the scrub callback's seek.
    private func scrubBy(seconds: Double) {
        seek(to: max(0, elapsed + seconds))
    }

    // MARK: Playback

    private func togglePlay() {
        playTaps += 1
        if isPlaying {
            pause()
            MediaPlaybackCoordinator.shared.stop(cardID)
        } else {
            guard playTask == nil else { return }
            playGeneration += 1
            let generation = playGeneration
            playTask = Task { @MainActor in
                // Clear only our own handle: a cancelled earlier load may still finish.
                defer { if generation == playGeneration { playTask = nil } }
                loading = true
                loadFailure = false
                await ensurePlayer()
                loading = false
                // The row went away (or paused) mid-load: stay silent and idle.
                guard !Task.isCancelled else {
                    loadFailure = false
                    return
                }
                // Nothing to play: the row says so and the next tap retries, instead of a
                // button that silently does nothing (V1.4).
                guard localPlayer != nil || streamPlayer != nil else {
                    loadFailure = true
                    return
                }
                MediaPlaybackCoordinator.shared.play(cardID)
                await MediaAudioSession.activateForPlayback()
                guard !Task.isCancelled else {
                    MediaPlaybackCoordinator.shared.stop(cardID)
                    return
                }
                localPlayer?.volume = 1
                localPlayer?.play()
                streamPlayer?.play()
                playing = true
            }
        }
    }

    /// A load still in flight must not start playback after the row went away or lost the floor.
    @MainActor
    private func cancelPendingPlay() {
        playTask?.cancel()
        playTask = nil
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
        guard case .local(let path) = input else { return }
        var workspaceID = richActions?.daemonWorkspaceID
        if workspaceID == nil {
            // A restored chat can be tapped before the agent snapshot names its workspace
            // (V1.1). Wait a moment for it; a row is not the place to wait forever, so the
            // tap ends in an honest failure when the id never arrives.
            var attempts = 0
            while workspaceID == nil, attempts < 20, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                workspaceID = richActions?.daemonWorkspaceID
                attempts += 1
            }
        }
        guard let workspaceID else {
            loadFailure = true
            return
        }
        let ref = DaemonFileRef(workspaceID: workspaceID, path: path, revision: nil)
        guard
            case .bytes(let fetched) = await MediaPipeline.shared.fetchDaemonFile(
                ref: ref, maxBytes: Int(MediaPipeline.maxDaemonBytes))
        else {
            loadFailure = true
            return
        }
        guard !Task.isCancelled else { return }
        // The bytes land in the cache file off main; the player opens it on main
        // (fast once the file exists), so no player ever crosses isolation.
        guard let fileURL = await MediaPipeline.cacheDaemonFile(data: fetched.data, ref: ref)
        else {
            loadFailure = true
            return
        }
        guard !Task.isCancelled else { return }
        // Detached work returns values only: the bars. The file stays in the cache.
        bars = await Task.detached(priority: .userInitiated) {
            Self.waveformBuckets(fileURL: fileURL)
        }.value
        guard !Task.isCancelled else { return }
        guard let player = try? AVAudioPlayer(contentsOf: fileURL) else {
            loadFailure = true
            return
        }
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
