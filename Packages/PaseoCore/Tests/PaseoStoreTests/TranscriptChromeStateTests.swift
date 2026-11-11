import Foundation
import Testing

@testable import PaseoStore

/// H2: the pure halves of the transcript chrome — the send runway's arithmetic and the header's
/// reveal state machine. Both are replayed here with the numbers the transcript feeds them.
@Suite struct SendRunwayTests {
    private let slack: CGFloat = 48

    @Test func openingWithoutAMeasurementGrantsOneViewport() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: nil, slack: slack)
        #expect(runway.turnId == "t1")
        #expect(!runway.measured)
        #expect(runway.owesGlide)
        #expect(runway.height == 700)
        runway.grant(viewport: 700, slack: slack)
        #expect(!runway.owesGlide)
        #expect(runway.height == 700)
    }

    /// The glide is the view's job: `grant` only hands the go-ahead, and the height it leaves is
    /// the one `open` already chose.
    @Test func aGrantDoesNotTouchAMeasuredRunway() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: 60, slack: slack)
        #expect(runway.height == 592)
        runway.grant(viewport: 700, slack: slack)
        #expect(runway.height == 592)
        #expect(!runway.owesGlide)
    }

    /// Nothing to grant without a viewport, and the glide stays owed.
    @Test func aGrantWithoutAViewportWaits() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 0, turnHeight: 60, slack: slack)
        runway.grant(viewport: 0, slack: slack)
        #expect(runway.owesGlide)
        #expect(runway.height == 0)
        runway.grant(viewport: 700, slack: slack)
        #expect(!runway.owesGlide)
        #expect(runway.height == 592)
    }

    /// The height report can land before the turn is registered as the anchor; the ordering must
    /// not decide whether the runway is exact or a whole viewport too tall (H2 §1).
    @Test func openingAfterTheHeightWasReportedIsExact() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: 60, slack: slack)
        #expect(runway.measured)
        #expect(runway.turnHeight == 60)
        #expect(runway.height == CGFloat(592))
    }

    @Test func withoutAViewportTheGlideIsOwedAndGrantedOnce() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 0, turnHeight: nil, slack: slack)
        #expect(runway.owesGlide)
        runway.grant(viewport: 700, slack: slack)
        #expect(!runway.owesGlide)
        #expect(runway.height == 700)
        _ = runway.measure(turnHeight: 60, viewport: 700, slack: slack)
        // A late grant must never overwrite the measurement with a fresh viewport.
        runway.grant(viewport: 700, slack: slack)
        #expect(runway.height == CGFloat(592))
    }

    @Test func aMeasurementOnlyShrinks() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: nil, slack: slack)
        _ = runway.measure(turnHeight: 60, viewport: 700, slack: slack)
        #expect(runway.height == 592)
        _ = runway.measure(turnHeight: 240, viewport: 700, slack: slack)
        #expect(runway.height == 412)
        // The work group collapsed: the answer is shorter, but the reader already left the room.
        _ = runway.measure(turnHeight: 40, viewport: 700, slack: slack)
        #expect(runway.height == 412)
    }

    @Test func aViewportChangeMayOnlyTrim() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: 60, slack: slack)
        #expect(runway.height == 592)
        // Dismissing the keyboard must not hand back the room the reader left (H2 §1).
        #expect(runway.viewportChanged(viewport: 900, slack: slack) == false)
        #expect(runway.height == 592)
        // The keyboard appearing leaves room for the tail turn and no more.
        #expect(runway.viewportChanged(viewport: 500, slack: slack) == true)
        #expect(runway.height == 392)
        #expect(runway.viewportChanged(viewport: 480, slack: slack) == true)
        #expect(runway.height == 372)
    }

    @Test func trimmingRemovesOnlyWhatIsBelowTheViewport() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: 60, slack: slack)
        #expect(runway.trim(toDistanceFromBottom: 30) == true)
        #expect(runway.height == 562)
        #expect(runway.trim(toDistanceFromBottom: 10_000) == true)
        #expect(runway.height == 0)
        #expect(runway.trim(toDistanceFromBottom: 10_000) == false)
    }

    /// A short answer's room is visible but unreachable: once the conversation without it fits
    /// the screen, the transcript collapses it and the content rests on the composer (H2 §1).
    @Test func collapseDropsTheRemainingRoomOnce() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: 60, slack: slack)
        #expect(runway.collapse() == true)
        #expect(runway.height == 0)
        #expect(runway.collapse() == false)
        // Still measured: the next measurement must not reopen a closed runway.
        _ = runway.measure(turnHeight: 60, viewport: 700, slack: slack)
        #expect(runway.height == 0)
    }

    @Test func aTrimmedRunwayNeverGrowsBack() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: 60, slack: slack)
        _ = runway.trim(toDistanceFromBottom: 200)
        #expect(runway.height == 392)
        _ = runway.measure(turnHeight: 60, viewport: 700, slack: slack)
        #expect(runway.height == 392)
        #expect(runway.viewportChanged(viewport: 900, slack: slack) == false)
        #expect(runway.height == 392)
    }

    @Test func theFillHandoverNeedsARealCrossing() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: nil, slack: slack)
        #expect(runway.measure(turnHeight: 60, viewport: 700, slack: slack) == false)
        #expect(runway.height == 592)
        #expect(runway.measure(turnHeight: 400, viewport: 700, slack: slack) == false)
        #expect(runway.height == 252)
        #expect(runway.measure(turnHeight: 700, viewport: 700, slack: slack) == true)
        #expect(runway.height == 0)
    }

    @Test func anAnswerTallerThanTheViewportTakesNoRunway() {
        var runway = SendRunway()
        runway.open(turnId: "t1", viewport: 700, turnHeight: 800, slack: slack)
        #expect(runway.height == 0)
    }
}

@Suite struct HeaderRevealStateTests {
    private let revealDistance: CGFloat = 290
    private let hideDistance: CGFloat = 24

    private func scrollFrame(
        _ state: inout HeaderRevealState, delta: CGFloat, roomAbove: CGFloat = 600,
        roomBelow: CGFloat = 600, canScroll: Bool = true
    ) -> Bool {
        state.scroll(
            by: delta, revealDistance: revealDistance, hideDistance: hideDistance,
            roomAbove: roomAbove, roomBelow: roomBelow, canScroll: canScroll)
    }

    @Test func conversationOpensWithTheHeaderVisible() {
        let state = HeaderRevealState()
        #expect(!state.isHidden)
    }

    @Test func readingForwardHidesTheBarAfterAShortTravel() {
        var state = HeaderRevealState()
        #expect(scrollFrame(&state, delta: 10) == false)
        #expect(!state.isHidden)
        #expect(scrollFrame(&state, delta: 10) == false)
        #expect(scrollFrame(&state, delta: 6) == true)
        #expect(state.isHidden)
    }

    @Test func aReversalStartsTheTravelOver() {
        var state = HeaderRevealState()
        _ = scrollFrame(&state, delta: 20)
        // A nudge back does not accumulate toward the reveal distance.
        _ = scrollFrame(&state, delta: -200)
        #expect(!state.isHidden)
        _ = scrollFrame(&state, delta: 4) // reversing again: the hide travel restarted at 0
        #expect(!state.isHidden)
        _ = scrollFrame(&state, delta: 24)
        #expect(state.isHidden)
    }

    @Test func theBarComesBackOnlyAfterADeliberatePull() {
        var state = HeaderRevealState()
        _ = scrollFrame(&state, delta: 100)
        #expect(state.isHidden)
        _ = scrollFrame(&state, delta: -289)
        #expect(state.isHidden)
        _ = scrollFrame(&state, delta: -1)
        #expect(!state.isHidden)
    }

    @Test func theTopOfTheLoadedTranscriptAlwaysShowsTheBar() {
        var state = HeaderRevealState()
        _ = scrollFrame(&state, delta: 100)
        #expect(state.isHidden)
        _ = scrollFrame(&state, delta: 10, roomAbove: 0)
        #expect(!state.isHidden)
        // A bounce at the top (negative room) reveals too.
        _ = scrollFrame(&state, delta: 100, roomAbove: -12)
        #expect(!state.isHidden)
    }

    @Test func aBounceAgainstTheEndNeverHides() {
        var state = HeaderRevealState()
        #expect(scrollFrame(&state, delta: 400, roomBelow: 0) == false)
        #expect(!state.isHidden)
        #expect(scrollFrame(&state, delta: 400, roomBelow: -3) == false)
        #expect(!state.isHidden)
    }

    @Test func aTranscriptThatFitsTheViewportNeverHides() {
        var state = HeaderRevealState()
        _ = scrollFrame(&state, delta: 400, canScroll: false)
        #expect(!state.isHidden)
        _ = scrollFrame(&state, delta: -400, canScroll: false)
        #expect(!state.isHidden)
    }

    @Test func revealReportsOnlyRealChanges() {
        var state = HeaderRevealState()
        #expect(state.reveal() == false)
        _ = scrollFrame(&state, delta: 100)
        #expect(state.isHidden)
        #expect(state.reveal() == true)
        #expect(!state.isHidden)
        #expect(state.reveal() == false)
    }
}
