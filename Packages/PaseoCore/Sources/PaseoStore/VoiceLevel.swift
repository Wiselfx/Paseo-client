import Foundation

// The microphone level chain, from a tap buffer to the bars: one dB mapping, one easing curve,
// one ring of levels, and the upload coalescer that turns the engine's buffer cadence into the
// daemon's frame cadence.
//
// Lives in Core (Foundation only) so it can be tested on Linux: the UI layer only owns the
// drawing. Nothing here touches SwiftUI, and nothing here may block: `AudioLevelMeter.push` runs
// on the audio thread and writes straight into `LiveWaveformBuffer`, which the renderer reads
// from its own display link. That is the whole point (H1 §3): the level never crosses the actor
// boundary, so no SwiftUI view is invalidated by an audio buffer.

/// The one mic-level mapping for both voice features.
///
/// `.dictation` runs `.measurement` with AGC off: raw RMS sits low, so the band reaches down to
/// −60 dBFS. `.voiceChat` runs the voice-processing IO unit with AGC on, which lifts and flattens
/// the signal, so its floor is higher. Both ceilings are −12 dBFS: speech rarely exceeds that,
/// and clamping there keeps a shout at the top of the meter instead of leaving it mid-height.
public enum AudioLevel {
    /// A recording mode's real signal range, in dBFS.
    public struct Band: Sendable, Equatable {
        public var floor: Float
        public var ceiling: Float

        public init(floor: Float, ceiling: Float) {
            self.floor = floor
            self.ceiling = ceiling
        }

        /// `.measurement`, AGC off.
        public static let dictation = Band(floor: -62, ceiling: -22)
        /// `.voiceChat`, AGC on (voice processing lifts the signal a few dB).
        public static let voiceChat = Band(floor: -57, ceiling: -17)
    }

    /// `20·log10(max(rms, 1e-5))` in dBFS.
    public static func decibels(rms: Float) -> Float {
        20 * log10(max(rms, 1e-5))
    }

    /// dBFS clamped to the band, mapped to 0…1, then `pow(_, 0.7)`.
    ///
    /// The power curve is what puts ordinary speech at 40–80 % of the height: a linear dB scale
    /// leaves it hugging the floor, and the eye reads the floor as "the mic is dead".
    public static func normalized(rms: Float, band: Band) -> Float {
        let db = decibels(rms: rms)
        let span = max(band.ceiling - band.floor, 1)
        let clamped = min(max(db, band.floor), band.ceiling)
        let linear = (clamped - band.floor) / span
        return Float(pow(Double(linear), 0.7))
    }

    /// Attack 0.6, release 0.15: bars jump to a syllable and fall away calmly.
    public static func smoothed(_ previous: Float, towards target: Float) -> Float {
        let factor: Float = target >= previous ? 0.6 : 0.15
        return previous + (target - previous) * factor
    }
}

/// The ring of levels the bars draw, **newest last**. Pushed from the audio thread (at most
/// `maxPushRate` times a second), read by the renderer at its own cadence.
///
/// A reference type on purpose: `@State` arrays or `@Observable` levels would re-render the
/// composer for every audio buffer. Nothing here invalidates SwiftUI; the renderer asks for a
/// snapshot when it draws.
///
/// Thread-safe: the capture tap writes while the main thread reads.
public final class LiveWaveformBuffer: @unchecked Sendable {
    /// Bars the ring can hold. Must exceed the widest row any screen can show (a full-width
    /// composer row is ≈ 420 pt, which is 84 slots at 3 pt bar + 2 pt gap).
    public static let capacity = 96

    /// One frame's worth of data, oldest first: `levels`, and `slots` — how many bar slots each
    /// sample has already slid left since it was recorded (0 = at the right edge). Slots come
    /// from each sample's own capture time, so the row slides left continuously between pushes
    /// and a new sample enters at the right edge without moving the bars already drawn.
    public struct Snapshot: Sendable, Equatable {
        public var levels: [Float]
        public var slots: [Float]

        public init(levels: [Float], slots: [Float]) {
            self.levels = levels
            self.slots = slots
        }
    }

    private let lock = NSLock()
    private let maxPushRate: Double
    private var levels: [Float]
    private var times: [TimeInterval]
    private var next = 0
    private var lastPush: TimeInterval = 0
    private var hasPushed = false

    public init(capacity: Int = LiveWaveformBuffer.capacity, maxPushRate: Double = 30) {
        let count = max(capacity, 1)
        levels = [Float](repeating: 0, count: count)
        times = [TimeInterval](repeating: 0, count: count)
        self.maxPushRate = max(maxPushRate, 1)
    }

    public var capacity: Int {
        lock.lock()
        defer { lock.unlock() }
        return levels.count
    }

    /// Records one 0…1 level, at most `maxPushRate` times a second. Callable from any thread.
    @discardableResult
    public func push(_ level: Float, at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // The first push always lands, even at the clock's zero: a new recording must show its
        // first syllable, not wait a frame.
        guard !hasPushed || now - lastPush >= 1.0 / maxPushRate else { return false }
        hasPushed = true
        lastPush = now
        levels[next] = min(max(level, 0), 1)
        times[next] = now
        next = (next + 1) % levels.count
        return true
    }

    /// The newest `count` levels, oldest first, with each sample's age in bar slots.
    public func snapshot(
        count: Int, at now: TimeInterval = Date().timeIntervalSince1970
    ) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let wanted = min(max(count, 0), levels.count)
        var window = [Float]()
        var slots = [Float]()
        window.reserveCapacity(wanted)
        slots.reserveCapacity(wanted)
        for offset in stride(from: wanted, to: 0, by: -1) {
            let index = (next + levels.count - offset) % levels.count
            window.append(levels[index])
            // A ring slot that has never been pushed has no timestamp; it is off-screen to the
            // left, which is what an empty bar should be.
            let age = hasPushed ? now - times[index] : 0
            slots.append(Float(min(max(age * maxPushRate, 0), Self.maxSlots)))
        }
        return Snapshot(levels: window, slots: slots)
    }

    /// Nothing is drawn half a million slots away, and keeping the number finite keeps the path
    /// arithmetic sane if a caller passes a clock far in the future.
    private static let maxSlots = 10_000.0

    /// The level the mic heard last; zero when nothing has arrived yet.
    public var latest: Float {
        lock.lock()
        defer { lock.unlock() }
        return levels[(next + levels.count - 1) % levels.count]
    }

    /// A new recording starts from silence, so old speech isn't drawn as if it just happened.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        levels = [Float](repeating: 0, count: levels.count)
        times = [TimeInterval](repeating: 0, count: levels.count)
        next = 0
        lastPush = 0
        hasPushed = false
    }
}

/// Turns raw RMS into the eased 0…1 level and writes it into a `LiveWaveformBuffer`, directly on
/// whatever thread the audio engine delivers buffers on. One instance per recording mode.
///
/// This is the only place a level is mapped or eased. It is `@unchecked Sendable` because it
/// guards its two mutable values with a lock; the audio thread must never wait on an actor.
public final class AudioLevelMeter: @unchecked Sendable {
    public let band: AudioLevel.Band
    public let buffer: LiveWaveformBuffer

    private let lock = NSLock()
    private var smoothed: Float = 0

    public init(band: AudioLevel.Band, buffer: LiveWaveformBuffer) {
        self.band = band
        self.buffer = buffer
    }

    /// Maps one buffer's RMS, eases it, and pushes it to the ring. Returns the eased level for
    /// callers that publish telemetry (voice mode's store).
    @discardableResult
    public func push(rms: Float, at now: TimeInterval = Date().timeIntervalSince1970) -> Float {
        let target = AudioLevel.normalized(rms: rms, band: band)
        lock.lock()
        smoothed = AudioLevel.smoothed(smoothed, towards: target)
        let value = smoothed
        lock.unlock()
        buffer.push(value, at: now)
        return value
    }

    /// The current eased level (0…1).
    public var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return smoothed
    }

    /// Silence, for the start of a recording or a mute.
    public func reset() {
        lock.lock()
        smoothed = 0
        lock.unlock()
        buffer.reset()
    }
}

/// Turns the capture engine's buffer cadence into the wire's frame cadence: one upload at most
/// `deliveriesPerSecond` times a second, with the PCM of the buffers in between concatenated in
/// order, and a hard cap (`maxBacklogSeconds`) so a stalled consumer cannot grow the buffer
/// without bound.
///
/// Pure arithmetic, no audio types: the framing is what the daemon receives, so it is tested.
public final class VoiceUploadCoalescer: @unchecked Sendable {
    /// The most the main actor hears from the mic per second (H1 §3).
    public static let deliveriesPerSecond = 30.0
    /// How much audio may pile up before the oldest is dropped (~1.5 s at 16 kHz mono PCM16).
    public static let maxBacklogSeconds = 1.5

    private let lock = NSLock()
    private let maxBacklogBytes: Int
    private let interval: TimeInterval
    private var pending = Data()
    private var lastDelivery: TimeInterval = 0
    private var hasDelivered = false

    public init(sampleRate: Double = 16_000, bytesPerFrame: Int = 2) {
        let bytesPerSecond = max(Int(sampleRate * Double(bytesPerFrame)), 1)
        self.maxBacklogBytes = Int(Double(bytesPerSecond) * VoiceUploadCoalescer.maxBacklogSeconds)
        self.interval = 1 / VoiceUploadCoalescer.deliveriesPerSecond
    }

    /// Appends one converted buffer and returns the bytes to send now, or nil to keep buffering.
    /// A returned empty `Data` means "a frame is due but no audio was produced" (the level still
    /// travels on the same tick).
    public func append(_ pcm: Data, at now: TimeInterval) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if !pcm.isEmpty {
            pending.append(pcm)
            if pending.count > maxBacklogBytes {
                pending.removeFirst(pending.count - maxBacklogBytes)
            }
        }
        guard !hasDelivered || now - lastDelivery >= interval else { return nil }
        hasDelivered = true
        lastDelivery = now
        let chunk = pending
        pending = Data()
        return chunk
    }

    /// Bytes waiting for the next delivery.
    public var backlogBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    /// Drops anything buffered and restarts the delivery clock (a new capture session).
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        pending = Data()
        lastDelivery = 0
        hasDelivered = false
    }
}
