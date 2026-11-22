#if canImport(UIKit)
import SwiftUI

/// Keeps a cell's content at the top of the cell while its frame catches up with a size change.
///
/// A hosting view centres its root in its bounds. When streamed text wraps onto a new line, the
/// SwiftUI content is a line taller for a frame or two before the collection view resizes the cell,
/// so the centred content rose by half a line and dropped back: the whole turn bounced on every
/// wrapped line. Here the content always starts at the cell's top and grows downward into the space
/// the pin is about to scroll into view.
///
/// Measurement is unchanged: with no height offered (the self-sizing ideal size) or none to speak of
/// (the compressed fitting size), the layout reports the content's own height. Only the drawing pass,
/// which offers the cell's real height, gets that height back, with the content placed at its top.
struct TranscriptTopPinnedLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let width = proposal.width ?? size.width
        guard let height = proposal.height, height >= 1, height.isFinite else {
            return CGSize(width: width, height: size.height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
#endif
