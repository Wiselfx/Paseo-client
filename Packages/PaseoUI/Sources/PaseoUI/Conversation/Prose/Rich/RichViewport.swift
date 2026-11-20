#if canImport(UIKit)
import SwiftUI

/// The height of the container rich cards are laid out in, for the 60 %/70 % media caps (§3).
///
/// Set once per screen — the transcript root, the file viewer — never per card. A card that
/// measured its own window had to render one frame uncapped and then shrink, which reads as a
/// jump, and every image mounted its own `UIViewRepresentable`. An environment value is known
/// before the card's first layout, so the cap is part of the first frame.
///
/// 800 is a phone-height fallback: a host that sets nothing still caps, so no screenshot is
/// ever drawn at full height.
extension EnvironmentValues {
    @Entry var richViewportHeight: CGFloat = 800
}

/// The prose column's width, set once per screen (plan §1.3): the transcript root and the file
/// viewer measure their content column and publish it here, never per card.
///
/// A media slot must know its width *before* a pixel arrives. `frame(maxWidth: .infinity)` alone
/// leaves that to the proposal, and a proposal that is not finite makes a resizable image fall
/// back to the image's own pixel size: a 640 pt photo escaped a 408 pt column, widened the
/// transcript's lazy stack under it, and every row that re-wrapped to the wider width kept its
/// old height (V1.2/V1.3). With the column here the slot is exactly the column, so its height
/// follows from the aspect ratio alone.
///
/// 0 means no column was measured (previews, tests): a card then keeps its former flexible
/// slot rather than pinning itself to a made-up number.
extension EnvironmentValues {
    @Entry var richProseWidth: CGFloat = 0
}

/// A media slot at exactly `width` points, its height capped at `heightCap` (`CGFloat.infinity`
/// for a slot that grows with its content). Fixed width, not `maxWidth`: the slot's height then
/// follows from the aspect ratio, and the card can never report a width wider than the column.
struct MediaSlotFrame: ViewModifier {
    var width: CGFloat
    var heightCap: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if width > 1 {
            // `minWidth` and `maxWidth` together pin the width, so the frame proposes exactly
            // `width` (and the cap) to the child — the letterboxing fit a tall image needs.
            content.frame(minWidth: width, maxWidth: width, maxHeight: heightCap)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: heightCap)
        }
    }
}

extension View {
    /// Sizes a media slot to the prose column. See `MediaSlotFrame`.
    func mediaSlot(width: CGFloat, heightCap: CGFloat) -> some View {
        modifier(MediaSlotFrame(width: width, heightCap: heightCap))
    }
}
#endif
