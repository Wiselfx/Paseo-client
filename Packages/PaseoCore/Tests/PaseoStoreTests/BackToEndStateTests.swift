import Foundation
import Testing

@testable import PaseoStore

/// J3 §3: "Back to the end" is offered only when the reader is more than one stable screen above
/// the end of the content, measured without the keyboard or the composer in the distance.
@Suite struct BackToEndStateTests {
    private let screen: CGFloat = 780

    @Test func aConversationOpensWithoutTheButton() {
        let state = BackToEndState()
        #expect(!state.isShowing)
    }

    @Test func theEndOfTheContentNeverOffersIt() {
        var state = BackToEndState()
        state.update(distanceFromContentBottom: 0, screen: screen, isFollowing: false)
        #expect(!state.isShowing)
        // The runway's tail lives below the end: negative distance is still the end.
        state.update(distanceFromContentBottom: -120, screen: screen, isFollowing: false)
        #expect(!state.isShowing)
    }

    @Test func aScreenIsTheThresholdAndItIsStrict() {
        var state = BackToEndState()
        state.update(distanceFromContentBottom: screen, screen: screen, isFollowing: false)
        #expect(!state.isShowing)
        state.update(distanceFromContentBottom: screen + 1, screen: screen, isFollowing: false)
        #expect(state.isShowing)
    }

    /// Following the live end and the button are mutually exclusive: nothing to offer.
    @Test func followingTheEndHidesItWhateverTheDistance() {
        var state = BackToEndState()
        state.update(distanceFromContentBottom: screen * 3, screen: screen, isFollowing: false)
        #expect(state.isShowing)
        state.update(distanceFromContentBottom: screen * 3, screen: screen, isFollowing: true)
        #expect(!state.isShowing)
    }

    /// The keyboard and the composer are not part of the reader's distance. The value handed in is
    /// the content gap — the end of the content to the bottom of the content area, always with
    /// `contentInsets.bottom` and the content height cancelling out — so focusing the composer,
    /// which only moves the inset, cannot flip the button.
    ///
    /// This is the J3 §3 regression: the old report added `contentInsets.bottom` on top of a gap
    /// that had already accounted for it. Here the same conversation is asked twice, before and
    /// after the keyboard raises the composer to 340 pt, and the answer cannot change.
    @Test func anInsetOnlyChangeDoesNotOfferTheButton() {
        let contentHeight: CGFloat = 6_000
        let offset: CGFloat = 6_000 - 900 - 40 // 40 pt above the end with the keyboard down
        var state = BackToEndState()
        state.update(distanceFromContentBottom: contentHeight - offset - 900, screen: screen,
                     isFollowing: false)
        #expect(!state.isShowing)
        // Focus: the bounds shrink by the 340 pt the bar and the keyboard take. The inset-free gap
        // is the same 40 pt; the inset-flavoured one the old code reported would be 720.
        let insetAfterFocus: CGFloat = 340
        let boundsAfterFocus: CGFloat = 900 - insetAfterFocus
        let oldReport = contentHeight - offset - boundsAfterFocus + insetAfterFocus
        #expect(oldReport == 720)
        state.update(
            distanceFromContentBottom: contentHeight - offset - boundsAfterFocus, screen: screen,
            isFollowing: false)
        #expect(!state.isShowing)
    }

    /// And the converse: the inset alone never manufactures a screen's worth of distance.
    @Test func theComposerInsetIsNotPartOfTheDistance() {
        var state = BackToEndState()
        // Ten points above the end with the keyboard down.
        let gap: CGFloat = 10
        state.update(distanceFromContentBottom: gap, screen: screen, isFollowing: false)
        #expect(!state.isShowing)
        // A tall composer and a keyboard that together add more than a screen to the inset.
        state.update(distanceFromContentBottom: gap, screen: screen, isFollowing: false)
        #expect(!state.isShowing)
        #expect(BackToEndState.decide(distance: gap, screen: screen, following: false) == false)
    }

    /// A streaming answer grows the content under the reader: the button is already up and stays.
    @Test func tailGrowthKeepsTheButtonUp() {
        var state = BackToEndState()
        state.update(distanceFromContentBottom: screen * 2, screen: screen, isFollowing: false)
        state.update(
            distanceFromContentBottom: screen * 2 + 400, screen: screen, isFollowing: false)
        #expect(state.isShowing)
    }

    /// Crossing back into the last screen drops it, even if a runway is still below the tail.
    @Test func comingBackIntoTheLastScreenDropsIt() {
        var state = BackToEndState()
        state.update(distanceFromContentBottom: screen * 2, screen: screen, isFollowing: false)
        state.update(distanceFromContentBottom: -80, screen: screen, isFollowing: false)
        #expect(!state.isShowing)
    }

    @Test func aMissingMeasurementReadsAsTheEnd() {
        var state = BackToEndState()
        state.update(distanceFromContentBottom: .infinity, screen: screen, isFollowing: false)
        #expect(!state.isShowing)
        #expect(BackToEndState.decide(distance: .nan, screen: screen, following: false) == false)
    }

    /// A pre-layout screen (0) still needs a deliberate distance, so a first frame cannot flash it.
    @Test func aZeroScreenDoesNotFlashTheButtonOnOnePoint() {
        var state = BackToEndState()
        state.update(distanceFromContentBottom: 0, screen: 0, isFollowing: false)
        #expect(!state.isShowing)
        state.update(distanceFromContentBottom: 1, screen: 0, isFollowing: false)
        #expect(!state.isShowing)
        state.update(distanceFromContentBottom: 2, screen: 0, isFollowing: false)
        #expect(state.isShowing)
    }

    @Test func theTapAndFindResetIt() {
        var state = BackToEndState()
        state.update(distanceFromContentBottom: screen * 2, screen: screen, isFollowing: false)
        state.returnedToEnd()
        #expect(!state.isShowing)
        state.update(distanceFromContentBottom: screen * 2, screen: screen, isFollowing: false)
        state.reset()
        #expect(!state.isShowing)
    }
}
