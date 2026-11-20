#if canImport(UIKit)
import SwiftUI

/// The trailing chevron the process card's thought/file rows wear (doc 08 §1.3): a 12 × 12 mask
/// of `M6 4l4 4-4 4`, stroke 1.5 with round caps, rotated a quarter turn while the row is open.
struct ClaudeTurnChevron: View {
    var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 6, y: 4))
            path.addLine(to: CGPoint(x: 10, y: 8))
            path.addLine(to: CGPoint(x: 6, y: 12))
        }
        .stroke(
            Palette.tertiaryInk,
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 12, height: 12)
        .rotationEffect(.degrees(expanded ? 90 : 0))
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: expanded)
        .accessibilityHidden(true)
    }
}
#endif
