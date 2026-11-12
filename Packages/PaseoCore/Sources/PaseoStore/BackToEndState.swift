import Foundation

/// "Back to the end" visibility (D1 §3, J3 §3).
///
/// The button is offered only when the reader is more than one stable screen above the **end of
/// the content**, and it is decided on the edges the transcript already publishes: while the
/// finger, a flick or its deceleration owns the scroll, and at rest. Never per frame.
///
/// J3 §3: the distance it is handed must be the reader's own — the gap between the end of the
/// content and the bottom of the **content** viewport, with no keyboard or composer inset in it.
/// `ChatTranscript` used to add `contentInsets.bottom` (the composer plus the keyboard), so the
/// report said "a screen further up" the moment the composer took focus, and the last decision
/// (taken before the inset changed) stuck.
///
/// The state is sticky on purpose: the button stays up while a streaming answer grows the content
/// under the reader's place, and it goes away when they come back into the last screen. It also
/// survives crossing a runway (if one is left) without latching.
public struct BackToEndState: Equatable, Sendable {
    /// Whether the button is offered.
    public private(set) var isShowing = false

    public init() {}

    /// One decision, from the distance between the end of the content and the bottom of the
    /// visible content area. Returns true when `isShowing` changed.
    ///
    /// - Parameters:
    ///   - distanceFromContentBottom: points of content below the bottom of the visible content
    ///     area. Zero at the end, positive when the reader is above it. Inset-independent.
    ///   - screen: one stable screen: the keyboard-independent viewport height.
    ///   - isFollowing: the reader is at the live end; nothing to offer.
    @discardableResult
    public mutating func update(
        distanceFromContentBottom: CGFloat, screen: CGFloat, isFollowing: Bool
    ) -> Bool {
        isShowing = Self.decide(
            distance: distanceFromContentBottom, screen: screen, following: isFollowing)
        return isShowing
    }

    /// The rule, without state: strictly more than one screen. A value that is not a number (a
    /// scroll view that has not reported yet) reads as the end, so the button cannot appear on a
    /// pre-layout frame.
    public static func decide(distance: CGFloat, screen: CGFloat, following: Bool) -> Bool {
        guard !following else { return false }
        guard distance.isFinite else { return false }
        return distance > max(screen, 1)
    }

    /// The button was tapped: it leaves the screen at once, on touch-down, instead of fading out
    /// under the finger while the glide runs.
    public mutating func returnedToEnd() {
        isShowing = false
    }

    /// Find opened: the transcript is showing a search result, not the reader's own position, so
    /// the button is hidden until the next decision.
    public mutating func reset() {
        isShowing = false
    }
}
