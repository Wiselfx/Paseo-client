import Foundation

/// The transcript header's auto-hide rule (H2 §3).
///
/// The user asked for the header to "appear only when scrolling up a lot": reading toward newer
/// content gets the bar out of the way, and a deliberate pull of a third of a screen toward older
/// content brings it back. Value-typed and free of observation, so the transcript accumulates
/// scroll distance in its non-observed box and writes its one `Bool` only when `isHidden` flips.
///
/// Programmatic scrolls never reach this type: the transcript calls `scroll(by:)` only while the
/// finger, a flick or its deceleration owns the scroll view.
public struct HeaderRevealState: Equatable, Sendable {
    /// Whether the header is hidden. A conversation opens with its chrome on screen.
    public private(set) var isHidden = false

    /// Travel accumulated in the current direction, in points. A reversal starts the other
    /// direction from zero, so a short nudge back never counts as a deliberate pull.
    private var travel: CGFloat = 0

    /// How close to an end still counts as that end: a bounce, not a scroll.
    private static let endSlack: CGFloat = 0.5

    public init() {}

    /// One scroll frame of user motion. Returns true when `isHidden` changed.
    ///
    /// - Parameters:
    ///   - delta: content-offset change; positive is toward newer content (down the page).
    ///   - revealDistance: deliberate travel toward older content that brings the bar back.
    ///   - hideDistance: travel toward newer content that gets it out of the way.
    ///   - roomAbove: distance from the top of the loaded content; zero or less means the top.
    ///   - roomBelow: distance from the end of the content; zero or less means the end.
    ///   - canScroll: false for a conversation that fits the viewport: it never hides its chrome.
    @discardableResult
    public mutating func scroll(
        by delta: CGFloat, revealDistance: CGFloat, hideDistance: CGFloat,
        roomAbove: CGFloat, roomBelow: CGFloat, canScroll: Bool
    ) -> Bool {
        // Nothing to hide from, or the top of the loaded transcript: chrome belongs on screen.
        guard canScroll, roomAbove > Self.endSlack else { return reveal() }
        guard delta.isFinite, abs(delta) > 0.01 else { return false }
        if delta > 0 {
            // Toward newer content. A bounce against the end moves no pixels of content, and a
            // reversal (already hidden, now reading forward) starts the travel over.
            guard roomBelow > Self.endSlack else { return false }
            guard !isHidden else { return resetTravel() }
            travel += delta
            guard travel >= max(hideDistance, 0) else { return false }
            isHidden = true
            travel = 0
            return true
        }
        // Toward older content: the bar only comes back after a deliberate distance.
        guard isHidden else { return resetTravel() }
        travel -= delta
        guard travel >= max(revealDistance, 1) else { return false }
        isHidden = false
        travel = 0
        return true
    }

    /// Shows the header now: a send, a jump to an older turn, or a conversation that can no
    /// longer scroll. Returns true when that changed the state.
    @discardableResult
    public mutating func reveal() -> Bool {
        travel = 0
        guard isHidden else { return false }
        isHidden = false
        return true
    }

    @discardableResult
    private mutating func resetTravel() -> Bool {
        travel = 0
        return false
    }
}

/// The send runway's arithmetic (D1 §2, H2 §1): the room under the turn you just sent that makes
/// `.top` land under the header, and that the incoming answer eats as it grows.
///
/// H2 adds the invariant the old code lacked: after the first frame the runway only ever shrinks.
/// A runway larger than the anchor needs lets the reader scroll past the last line into nothing;
/// growing it back on a keyboard dismissal hands that room back after they left it.
public struct SendRunway: Equatable, Sendable {
    /// The turn the runway was opened for; nil before the first send of this conversation.
    public private(set) var turnId: String?
    /// The space drawn under that turn.
    public private(set) var height: CGFloat = 0
    /// That turn's last measured height.
    public private(set) var turnHeight: CGFloat = 0
    /// True once that turn has been measured, so its first height is not read as growth.
    public private(set) var measured = false
    /// The glide to `.top` is owed: the transcript owes one scroll to the new turn, granted in a
    /// layout pass inside the scroll view (where a proxy exists, not in this type).
    public private(set) var owesGlide = false

    public init() {}

    /// Opens for the turn that was just sent.
    ///
    /// `turnHeight` is what the transcript already measured for that turn: the height report can
    /// land before the turn is registered as the anchor, and the ordering must not decide whether
    /// the runway starts exact or a whole viewport too tall.
    public mutating func open(
        turnId: String, viewport: CGFloat, turnHeight: CGFloat?, slack: CGFloat
    ) {
        self.turnId = turnId
        self.turnHeight = turnHeight ?? 0
        measured = turnHeight != nil
        owesGlide = true
        // Before the turn is measured the only safe grant is a whole viewport: `.top` must be
        // reachable on the first frame, and the first measurement trims it back the same pass.
        height = measured ? need(viewport: viewport, slack: slack) : max(0, viewport)
    }

    /// The transcript has a viewport and a scroll proxy: the glide it owes is granted now (the
    /// scroll itself belongs to the view). An unmeasured turn gets the whole viewport, so `.top`
    /// is reachable; a measured one is already exact.
    public mutating func grant(viewport: CGFloat, slack: CGFloat) {
        guard owesGlide, viewport > 0 else { return }
        owesGlide = false
        height = measured ? need(viewport: viewport, slack: slack) : max(0, viewport)
    }

    /// The tail turn's height moved. Returns true when this measurement is the one that fills the
    /// screen, so the transcript can hand the anchor over to tail-follow.
    public mutating func measure(
        turnHeight: CGFloat, viewport: CGFloat, slack: CGFloat
    ) -> Bool {
        let capacity = max(0, viewport - slack)
        let fills = measured && self.turnHeight < capacity && turnHeight >= capacity
        self.turnHeight = turnHeight
        measured = true
        height = min(height, need(viewport: viewport, slack: slack))
        return fills
    }

    /// The viewport changed (the keyboard, mostly, or rotation): the runway may only trim.
    public mutating func viewportChanged(viewport: CGFloat, slack: CGFloat) -> Bool {
        guard measured else { return false }
        return cap(need(viewport: viewport, slack: slack))
    }

    /// Removes the part of the runway that sits below the visible bottom. Changing off-screen
    /// room moves nothing the reader is looking at.
    public mutating func trim(toDistanceFromBottom distance: CGFloat) -> Bool {
        let removed = min(height, max(0, distance))
        guard removed > 0 else { return false }
        height -= removed
        return true
    }

    /// The conversation without the runway fits the screen: the remaining room is not reachable
    /// by any scroll and no longer makes `.top` reachable, so the transcript may drop it and let
    /// the short conversation rest on the composer (H2 §1). Only the caller can know the content
    /// fits, and only a settle may ask: collapsing while the reader is mid-conversation would
    /// move what they are reading.
    public mutating func collapse() -> Bool {
        guard height > 0 else { return false }
        height = 0
        return true
    }

    private mutating func cap(_ limit: CGFloat) -> Bool {
        let next = max(0, min(height, limit))
        guard next != height else { return false }
        height = next
        return true
    }

    /// The room under the tail turn, from its top under the header to the composer.
    private func need(viewport: CGFloat, slack: CGFloat) -> CGFloat {
        max(0, viewport - turnHeight - slack)
    }
}
