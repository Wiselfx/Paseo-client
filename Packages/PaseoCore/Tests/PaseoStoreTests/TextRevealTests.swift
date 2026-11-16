import Testing

@testable import PaseoStore

/// The paced-reveal policy: arrival sets the target, the reveal rate follows the backlog.
/// Ported alongside `TextReveal` from upstream `text-reveal.ts`; cases mirror
/// `text-reveal.test.ts` plus Swift grapheme specifics.
@Suite struct TextRevealTests {
    // MARK: - computeRevealStep

    @Test func stepIsZeroWithoutBacklog() {
        #expect(TextReveal.computeRevealStep(backlog: 0, elapsedMs: 16) == 0)
        #expect(TextReveal.computeRevealStep(backlog: -5, elapsedMs: 16) == 0)
    }

    @Test func stepDrainsBacklogOverHorizon() {
        #expect(
            TextReveal.computeRevealStep(
                backlog: 300, elapsedMs: TextReveal.horizonMs / 2) == 150)
    }

    @Test func stepReleasesAllOnceAFrameCoversHorizon() {
        #expect(
            TextReveal.computeRevealStep(backlog: 42, elapsedMs: TextReveal.horizonMs) == 42)
        #expect(
            TextReveal.computeRevealStep(backlog: 42, elapsedMs: TextReveal.horizonMs * 10)
                == 42)
    }

    @Test func stepScalesWithBacklog() {
        let slow = TextReveal.computeRevealStep(backlog: 20, elapsedMs: 16)
        let fast = TextReveal.computeRevealStep(backlog: 200, elapsedMs: 16)
        #expect(fast > slow)
    }

    @Test func stepAlwaysAdvancesAtLeastOneUnit() {
        #expect(TextReveal.computeRevealStep(backlog: 1, elapsedMs: 1) == 1)
        #expect(TextReveal.computeRevealStep(backlog: 2, elapsedMs: 0.01) == 1)
    }

    @Test func stepNeverOvershoots() {
        for backlog in [1, 3, 7, 50] {
            #expect(TextReveal.computeRevealStep(backlog: backlog, elapsedMs: 120) <= backlog)
        }
    }

    @Test func stepIsZeroWithoutElapsedTime() {
        #expect(TextReveal.computeRevealStep(backlog: 100, elapsedMs: 0) == 0)
        #expect(TextReveal.computeRevealStep(backlog: 100, elapsedMs: -16) == 0)
    }

    @Test func stepConvergesWithinBoundedFrames() {
        var remaining = 500
        var frames = 0
        while remaining > 0 {
            remaining -= TextReveal.computeRevealStep(backlog: remaining, elapsedMs: 16)
            frames += 1
            #expect(frames < 120)
        }
        #expect(remaining == 0)
    }

    @Test func burstyArrivalsStaySmooth() {
        // A lumpy arrival sequence: the daemon's coalescing window carries wildly
        // different character counts depending on model throughput.
        let arrivals = [4, 180, 6, 240, 2, 90, 300, 8]
        var backlog = 0
        var maxStep = 0
        for arrival in arrivals {
            backlog += arrival
            // ~60 ms of frames between coalesced flushes.
            for _ in 0..<4 {
                let step = TextReveal.computeRevealStep(backlog: backlog, elapsedMs: 16)
                backlog -= step
                maxStep = max(maxStep, step)
            }
        }
        // The 150 ms horizon outlasts the 60 ms arrival gap: drain afterwards.
        var frames = 0
        while backlog > 0 {
            backlog -= TextReveal.computeRevealStep(backlog: backlog, elapsedMs: 16)
            frames += 1
            #expect(frames < 120)
        }
        #expect(backlog == 0)
        // No single frame paints a whole lump: the largest lump (300) spreads out.
        #expect(maxStep < 100)
    }

    // MARK: - clampToSafeRevealBoundary

    @Test func clampKeepsAsciiCut() {
        #expect(TextReveal.clampToSafeRevealBoundary("hello", 3) == 3)
    }

    @Test func clampPinsOutOfRangeCuts() {
        #expect(TextReveal.clampToSafeRevealBoundary("hello", 0) == 0)
        #expect(TextReveal.clampToSafeRevealBoundary("hello", 99) == 5)
        #expect(TextReveal.clampToSafeRevealBoundary("", 4) == 0)
    }

    @Test func clampNeverSplitsARegionalIndicatorPair() {
        // One flag: four UTF-16 units, one grapheme.
        let flag = "\u{1F1EB}\u{1F1F7}"
        #expect(flag.utf16.count == 4)
        #expect(TextReveal.clampToSafeRevealBoundary(flag, 2) == 0)
        #expect(TextReveal.clampToSafeRevealBoundary(flag, 4) == 4)
    }

    @Test func clampNeverSplitsAZWJSequence() {
        let family = "a\u{200D}b"
        let cut = TextReveal.clampToSafeRevealBoundary(family, family.utf16.count - 1)
        let visible = String(family.prefix(upTo: family.utf16.index(
            family.utf16.startIndex, offsetBy: cut)))
        // The cut lands on a boundary: re-encoding it holds whole characters.
        #expect(visible.unicodeScalars.count <= family.unicodeScalars.count)
        #expect(family.hasPrefix(visible))
    }

    @Test func clampKeepsCombiningMarksWithTheirBase() {
        let eAcute = "e\u{301}"
        #expect(eAcute.utf16.count == 2)
        #expect(TextReveal.clampToSafeRevealBoundary(eAcute, 1) == 0)
        #expect(TextReveal.clampToSafeRevealBoundary(eAcute, 2) == 2)
    }

    // MARK: - nextFrame

    @Test func firstFrameSpendsOneInterval() {
        let frame = TextReveal.nextFrame(previousFrameAtMs: nil, timestampMs: 1000)
        #expect(frame?.elapsedMs == TextReveal.frameIntervalMs)
    }

    @Test func tooSoonFrameReleasesNothing() {
        #expect(
            TextReveal.nextFrame(previousFrameAtMs: 1000, timestampMs: 1000 + 1) == nil)
    }

    @Test func frameCarriesRemainderForward() {
        // 25 ms after the last frame at 60 Hz: one interval spent, ~8 ms carried.
        let frame = TextReveal.nextFrame(previousFrameAtMs: 1000, timestampMs: 1025)
        let elapsed = frame?.elapsedMs ?? -1
        #expect(abs(elapsed - 25) < 0.001)
        let remainder = 1025 - (frame?.frameAtMs ?? 0)
        #expect(abs(remainder - 25.truncatingRemainder(dividingBy: TextReveal.frameIntervalMs)) < 0.01)
    }

    // MARK: - State

    @Test func beginRevealsFirstSightWhole() {
        let state = TextReveal.begin("hello")
        #expect(state.revealed == 5)
        #expect(TextReveal.isSettled(state))
        #expect(TextReveal.visibleText(state, streaming: true) == "hello")
    }

    @Test func retargetKeepsShownCount() {
        var state = TextReveal.begin("hello")
        state = TextReveal.retarget(state, "hello world")
        #expect(state.revealed == 5)
        #expect(!TextReveal.isSettled(state))
    }

    @Test func retargetClampsToShorterText() {
        var state = TextReveal.begin("hello world")
        state = TextReveal.retarget(state, "hi")
        #expect(state.revealed == 2)
        #expect(TextReveal.isSettled(state))
    }

    @Test func retargetIsIdentityForSameText() {
        let state = TextReveal.begin("hello")
        #expect(TextReveal.retarget(state, "hello") == state)
    }

    @Test func advanceIsMonotonicAndSettles() {
        var state = TextRevealState(target: "hello world", revealed: 0)
        var last = -1
        while !TextReveal.isSettled(state) {
            state = TextReveal.advance(state, elapsedMs: 16)
            #expect(state.revealed > last)
            last = state.revealed
        }
        #expect(state.revealed == 11)
    }

    @Test func completeReleasesEverything() {
        let state = TextReveal.complete(TextRevealState(target: "hello", revealed: 2))
        #expect(TextReveal.isSettled(state))
        #expect(TextReveal.visibleText(state, streaming: true) == "hello")
    }

    @Test func completeIsIdentityWhenSettled() {
        let state = TextReveal.begin("hello")
        #expect(TextReveal.complete(state) == state)
    }

    @Test func visibleTextPacesGrowth() {
        let state = TextRevealState(target: "hello world", revealed: 5)
        #expect(TextReveal.visibleText(state, streaming: true) == "hello")
        #expect(TextReveal.visibleText(state, streaming: false) == "hello")
    }

    // MARK: - Trailing fragments

    @Test func asciiPassesThroughUntouched() {
        #expect(TextReveal.trimmedForStreaming("hello") == "hello")
        #expect(TextReveal.trimmedForStreaming("") == "")
    }

    @Test func trailingJoinerWaitsForItsSequence() {
        // A joiner that stands alone is withheld; one merged with its base paints
        // through (the joiner itself is invisible, and it cannot be split off).
        #expect(TextReveal.trimmedForStreaming("a\n\u{200D}") == "a\n")
        #expect(TextReveal.trimmedForStreaming("a\u{200D}") == "a\u{200D}")
        #expect(TextReveal.trimmedForStreaming("a \u{200D}") == "a \u{200D}")
    }

    @Test func oddRegionalIndicatorWaitsForItsPair() {
        // One regional indicator: half a flag.
        #expect(TextReveal.trimmedForStreaming("a\u{1F1EB}") == "a")
    }

    @Test func completedFlagPaints() {
        let flag = "a\u{1F1EB}\u{1F1F7}"
        #expect(TextReveal.trimmedForStreaming(flag) == flag)
    }

    @Test func settledTextAlwaysPaintsWhole() {
        // Once the turn ends everything received is painted: nothing more is coming.
        let partial = "a\u{1F1EB}"
        let state = TextReveal.begin(partial)
        #expect(TextReveal.visibleText(state, streaming: false) == partial)
        #expect(TextReveal.visibleText(state, streaming: true) == "a")
    }
}
