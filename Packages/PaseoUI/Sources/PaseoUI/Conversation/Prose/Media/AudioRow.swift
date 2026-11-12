#if canImport(UIKit)
import AVFoundation
import MediaPlayer
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
    @State private var player: AVAudioPlayer?
    @State private var scrubbing = false

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
                    guard let player, player.isPlaying else { break }
                    elapsed = player.currentTime
                    setNowPlaying()
                }
            }
    }

    // MARK: Waveform

    /// 48 RMS buckets across the whole file, computed off main once per card.
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
            .gesture(scrubGesture(width: proxy.size.width))
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

    /// Drag to scrub: the playhead follows the finger; haptics bracket the gesture.
    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !scrubbing {
                    scrubbing = true
                    Haptics.selection()
                }
                guard duration > 0, width > 0 else { return }
                seek(to: Double(min(max(value.location.x / width, 0), 1)) * duration)
            }
            .onEnded { _ in
                scrubbing = false
                Haptics.selection()
            }
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
                guard player != nil else { return }
                MediaPlaybackCoordinator.shared.play(cardID)
                await MediaAudioSession.activateForPlayback()
                player?.volume = 1
                player?.play()
                playing = true
                setNowPlaying()
            }
        }
    }

    @MainActor
    private func pause() {
        guard let player, player.isPlaying else {
            playing = false
            return
        }
        MediaPlaybackCoordinator.shared.remember(position: player.currentTime, for: cardID)
        player.pause()
        playing = false
        if MediaPlaybackCoordinator.shared.activeID == cardID {
            MediaPlaybackCoordinator.shared.stop(cardID)
        }
        Task { @MainActor in
            await MediaAudioSession.deactivateAfterPlayback()
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func seek(to seconds: Double) {
        guard let player, duration > 0 else { return }
        player.currentTime = min(max(seconds, 0), duration)
        elapsed = player.currentTime
        setNowPlaying()
    }

    /// Downloads (whole file; audio files rarely approach the cap), decodes the
    /// waveform off main, and builds the player. Nothing starts until the tap.
    @MainActor
    private func ensurePlayer() async {
        if player != nil { return }
        let bytes: Data?
        switch input {
        case .remote(let urlString):
            guard let url = URL(string: urlString) else { return }
            bytes = try? await URLSession.shared.data(from: url).0
        case .local(let path):
            guard let workspaceID = richActions?.daemonWorkspaceID else { return }
            let ref = DaemonFileRef(workspaceID: workspaceID, path: path, revision: nil)
            switch await MediaPipeline.shared.fetchDaemonFile(
                ref: ref, maxBytes: Int(MediaPipeline.maxDaemonBytes))
            {
            case .bytes(let fetched): bytes = fetched.data
            case .tooLarge, .unavailable: return
            }
        }
        guard let bytes, !Task.isCancelled else { return }
        let decoded = await Task.detached(priority: .userInitiated) { () -> (waveform: [CGFloat], duration: Double, player: AVAudioPlayer?)? in
            let fileURL = FileManager.default.temporaryDirectory
                .appending(path: "paseo-audio-\(UUID().uuidString)", directoryHint: .notDirectory)
            do {
                try bytes.write(to: fileURL, options: .atomic)
                defer { try? FileManager.default.removeItem(at: fileURL) }
                guard let player = try? AVAudioPlayer(data: bytes) else { return nil }
                player.prepareToPlay()
                let bars = Self.waveformBuckets(fileURL: fileURL)
                return (bars, player.duration, player)
            } catch {
                return nil
            }
        }.value
        guard let decoded, let decodedPlayer = decoded.player, !Task.isCancelled else { return }
        bars = decoded.waveform
        duration = decoded.duration
        player = decodedPlayer
        elapsed = 0
    }

    /// 48 RMS buckets over the whole file, read in chunks off main. A missing or
    /// unreadable file gets a flat line instead of an error state.
    private nonisolated static func waveformBuckets(fileURL: URL) -> [CGFloat] {
        let bucketCount = 48
        let flat = Array(repeating: CGFloat(0.05), count: bucketCount)
        guard let file = try? AVAudioFile(forReading: fileURL) else { return flat }
        let totalFrames = file.length
        guard totalFrames > 0 else { return flat }
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate,
                channels: min(file.fileFormat.channelCount, 2), interleaved: false)
        else { return flat }
        let chunkFrames = max(AVAudioFrameCount(4096), totalFrames / AVAudioFrameCount(bucketCount * 4))
        var buckets: [Float] = []
        buckets.reserveCapacity(bucketCount * 4)
        var remaining = totalFrames
        while remaining > 0 {
            let frames = min(chunkFrames, AVAudioFrameCount(remaining))
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
            remaining -= AVAudioFrameCount(buffer.frameLength)
        }
        guard !buckets.isEmpty else { return flat }
        let perBar = max(1, buckets.count / bucketCount)
        return (0..<bucketCount).map { index in
            let upper = min((index + 1) * perBar, buckets.count)
            let peak = buckets[(index * perBar)..<upper].max() ?? 0
            return CGFloat(min(max(peak * 1.6, 0.05), 1.0))
        }
    }

    private func setNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: fileName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
        ]
        if isPlaying {
            info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
