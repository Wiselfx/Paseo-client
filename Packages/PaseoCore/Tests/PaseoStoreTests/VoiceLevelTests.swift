import Foundation
import PaseoStore
import Testing

/// H1: the level chain the waveform draws, tested where it lives instead of on a device.
@Suite("Voice level")
struct VoiceLevelTests {

    // MARK: Bands

    @Test("Silence and the floor map to zero, the ceiling and beyond map to one")
    func bandEnds() {
        for band in [AudioLevel.Band.dictation, AudioLevel.Band.voiceChat] {
            #expect(AudioLevel.normalized(rms: 0, band: band) == 0)
            let floorRms = Float(pow(10, Double(band.floor) / 20))
            #expect(abs(AudioLevel.normalized(rms: floorRms, band: band)) < 0.001)
            let ceilingRms = Float(pow(10, Double(band.ceiling) / 20))
            #expect(abs(AudioLevel.normalized(rms: ceilingRms, band: band) - 1) < 0.001)
            #expect(AudioLevel.normalized(rms: 1, band: band) == 1)
        }
    }

    @Test("The mapping is monotonic across the band")
    func monotonic() {
        let band = AudioLevel.Band.voiceChat
        var previous: Float = -1
        for step in stride(from: 0.0, through: 1.0, by: 0.01) {
            let rms = Float(step)
            let value = AudioLevel.normalized(rms: rms, band: band)
            #expect(value >= previous)
            previous = value
        }
    }

    @Test("Ordinary speech lands in the visible middle of the bars")
    func speechFillsTheMiddle() {
        // −40 dBFS and −35 dBFS: what a handset mic reports for normal speech in `.voiceChat`
        // (AGC on) and `.measurement` (AGC off), once normalised by the band ends.
        let voice = AudioLevel.normalized(
            rms: Float(pow(10, -40.0 / 20)), band: .voiceChat)
        #expect(voice > 0.4 && voice < 0.85)
        let dictation = AudioLevel.normalized(
            rms: Float(pow(10, -35.0 / 20)), band: .dictation)
        #expect(dictation > 0.4 && dictation < 0.85)
        // A shout reaches the top.
        #expect(AudioLevel.normalized(rms: Float(pow(10, -18.0 / 20)), band: .voiceChat) > 0.9)
        // A whisper is still visible, not a dead row.
        #expect(AudioLevel.normalized(rms: Float(pow(10, -50.0 / 20)), band: .voiceChat) > 0.2)
    }

    @Test("Easing attacks fast and releases slowly")
    func smoothing() {
        let attack = AudioLevel.smoothed(0, towards: 1)
        #expect(abs(attack - 0.6) < 0.0001)
        let release = AudioLevel.smoothed(1, towards: 0)
        #expect(abs(release - 0.85) < 0.0001)
        // Never overshoots.
        #expect(AudioLevel.smoothed(0.9, towards: 1) <= 1)
        #expect(AudioLevel.smoothed(0.1, towards: 0) >= 0)
    }

    // MARK: The ring the bars read

    @Test("A snapshot returns the newest levels, oldest first")
    func ringOrder() {
        let buffer = LiveWaveformBuffer(capacity: 8)
        for index in 0..<5 {
            buffer.push(Float(index + 1) / 10, at: Double(index))
        }
        let snapshot = buffer.snapshot(count: 5, at: 4)
        #expect(snapshot.levels == [0.1, 0.2, 0.3, 0.4, 0.5])
        #expect(buffer.latest == 0.5)
    }

    @Test("A snapshot never asks for more bars than the ring holds")
    func ringClamps() {
        let buffer = LiveWaveformBuffer(capacity: 4)
        buffer.push(0.5, at: 0)
        #expect(buffer.snapshot(count: 40, at: 0).levels.count == 4)
        #expect(buffer.snapshot(count: 0, at: 0).levels.isEmpty)
    }

    @Test("The ring advances at most thirty times a second")
    func pushRate() {
        let buffer = LiveWaveformBuffer(capacity: 8)
        #expect(buffer.push(0.2, at: 1.000))
        #expect(!buffer.push(0.9, at: 1.010))
        #expect(buffer.latest == 0.2)
        #expect(buffer.push(0.9, at: 1.034))
        #expect(buffer.latest == 0.9)
    }

    @Test("Each bar's slide is its own age in slots, so the row never jumps on a push")
    func slots() {
        let buffer = LiveWaveformBuffer(capacity: 8)
        buffer.push(0.25, at: 10)
        let one = buffer.snapshot(count: 1, at: 10 + 1.0 / 60.0).slots
        #expect(abs(one[0] - 0.5) < 0.01)

        // Two samples 0.1 s apart: the newer one sits at the right edge, the older one three
        // slots in (0.1 s × 30 pushes/s). A push never moves a bar that is already drawn.
        buffer.push(0.75, at: 10.1)
        let both = buffer.snapshot(count: 2, at: 10.1).slots
        #expect(abs(both[1]) < 0.001)
        #expect(abs(both[0] - 3) < 0.001)

        // Idle: the whole row keeps sliding left with time; it never slides out the right edge.
        let idle = buffer.snapshot(count: 2, at: 12).slots
        #expect(abs(idle[1] - 57) < 0.001)
        #expect(idle[0] > idle[1])
    }

    @Test("Reset clears the history so a new recording starts from dots")
    func reset() {
        let buffer = LiveWaveformBuffer(capacity: 8)
        buffer.push(0.8, at: 1)
        buffer.reset()
        #expect(buffer.latest == 0)
        #expect(buffer.snapshot(count: 4, at: 2).levels == [0, 0, 0, 0])
    }

    @Test("Levels outside zero to one are clamped")
    func clampsLevels() {
        let buffer = LiveWaveformBuffer(capacity: 4)
        buffer.push(4, at: 1)
        buffer.push(-2, at: 2)
        let levels = buffer.snapshot(count: 2, at: 2).levels
        #expect(levels == [1, 0])
    }

    // MARK: The meter

    @Test("The meter maps, eases and writes the ring in one step")
    func meterPushes() {
        let buffer = LiveWaveformBuffer(capacity: 4)
        let meter = AudioLevelMeter(band: .voiceChat, buffer: buffer)
        let first = meter.push(rms: 0.01, at: 0)
        #expect(first > 0)
        #expect(buffer.latest == first)
        let louder = meter.push(rms: 0.1, at: 1)
        #expect(louder > first)
        meter.reset()
        #expect(meter.level == 0)
        #expect(buffer.latest == 0)
    }

    // MARK: Upload framing

    @Test("Buffers are coalesced into at most thirty uploads a second")
    func coalescerRate() {
        let coalescer = VoiceUploadCoalescer()
        var deliveries: [Data] = []
        // 48 buffers in one second: ~21 ms apart, like a 1024-frame tap at 48 kHz.
        for index in 0..<48 {
            let now = Double(index) / 48.0
            if let chunk = coalescer.append(Data([UInt8(index)]), at: now) {
                deliveries.append(chunk)
            }
        }
        // Flush the frame still accumulating at the end of the second.
        if let last = coalescer.append(Data(), at: 2), !last.isEmpty { deliveries.append(last) }
        #expect(deliveries.count <= 31)
        // At most 30/s; the 21 ms buffer cadence quantises the gate, so ~24 is expected.
        #expect(deliveries.count >= 20)
        // Nothing is lost: every byte appended came out, in order.
        #expect(deliveries.flatMap { $0 } == (0..<48).map { UInt8($0) })
        // The first buffer leaves immediately: a live conversation must not wait for a frame.
        let fresh = VoiceUploadCoalescer()
        #expect(fresh.append(Data([7]), at: 0) == Data([7]))
    }

    @Test("A stalled consumer cannot grow the backlog past 1.5 seconds")
    func coalescerBacklog() {
        let coalescer = VoiceUploadCoalescer(sampleRate: 16_000, bytesPerFrame: 2)
        let buffer = Data(repeating: 1, count: 64_000)  // 2 s of audio
        // The first delivery is immediate, already trimmed to the 1.5 s backlog cap.
        let first = coalescer.append(buffer, at: 0)
        #expect(first?.count == 48_000)
        #expect(coalescer.backlogBytes == 0)
        _ = coalescer.append(buffer, at: 0.001)
        #expect(coalescer.backlogBytes == 48_000)
        let delivered = coalescer.append(Data(), at: 1)
        #expect(delivered?.count == 48_000)
        coalescer.reset()
        #expect(coalescer.backlogBytes == 0)
    }

    @Test("A frame with no audio still reports due, so the level travels with it")
    func coalescerEmptyFrame() {
        let coalescer = VoiceUploadCoalescer()
        #expect(coalescer.append(Data(), at: 0) == Data())
        #expect(coalescer.append(Data(), at: 0.001) == nil)
    }
}
