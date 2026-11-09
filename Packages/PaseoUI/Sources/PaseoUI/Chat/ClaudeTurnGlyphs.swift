#if canImport(UIKit)
import SwiftUI

/// The activity/tool glyphs the turn surfaces wear, drawn from a 16-unit viewBox with the stroke
/// in the ink in force (doc 08 §1.4). SF Symbols approximate these nowhere near exactly; the
/// paths below are the ones the live page measures, with two called out in the final message:
/// the think glyph is a bow-tie/atom approximation (the source path is elided in doc 08), and
/// the browse glyph is a page with two lines (shape from the doc's words, not a measured path).
/// Coordinates are scaled by `size / 16` when the path is built.
struct ClaudeGlyph: View {
    enum Kind {
        /// `dsw-icon-api-outline-regular`: the `>-` terminal prompt.
        case api
        /// `dsw-icon-browse-outline-regular`: a page outline with two lines.
        case browse
        /// `dsw-icon-think-outline-regular`: a bow-tie/atom outline with a filled centre dot.
        case think
        /// `dsw-icon-chevron-down-outline-regular`: `M4 6L7.29 9.29a1 1 0 0 0 1.41 0L12 6`.
        case chevronDown
        /// The same glyph rotated a half turn, for the open summary seat.
        case chevronUp
    }

    var kind: Kind
    var size: CGFloat = 14
    var color: Color = .primary
    /// The stroke width in viewBox units (1 for the host glyphs, 1.5 for the 12 pt trailing chevron mask).
    var lineWidth: CGFloat = 1

    private var scale: CGFloat { size / 16 }

    var body: some View {
        ZStack {
            if kind == .think {
                // Bow-tie/atom: two stroked ellipses crossing at the centre, plus the filled dot.
                ForEach([60.0, -60.0], id: \.self) { degrees in
                    Ellipse()
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth * scale))
                        .frame(width: 11 * scale, height: 4.6 * scale)
                        .rotationEffect(.degrees(degrees))
                }
                Circle().fill(color).frame(width: 1.7 * scale, height: 1.7 * scale)
            } else {
                Path { path in draw(kind, into: &path) }
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * scale, y: y * scale)
    }

    private func draw(_ kind: Kind, into path: inout Path) {
        switch kind {
        case .api:
            path.move(to: point(3, 4))
            path.addLine(to: point(7, 8))
            path.addLine(to: point(3, 12))
            path.move(to: point(9, 12))
            path.addLine(to: point(13, 12))
        case .browse:
            // A page outline with two writing lines; the outline's corner radius is a guess at 1.5.
            path.addRoundedRect(
                in: CGRect(x: 4 * scale, y: 2 * scale, width: 8 * scale, height: 12 * scale),
                cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale), style: .circular)
            path.move(to: point(6.2, 6))
            path.addLine(to: point(9.8, 6))
            path.move(to: point(6.2, 9))
            path.addLine(to: point(9.8, 9))
        case .think:
            break // drawn with the ellipses in the ZStack
        case .chevronDown:
            // The 1 × 1 arc at the tip is folded into a round-joined line join; identical at 14 pt.
            path.move(to: point(4, 6))
            path.addLine(to: point(7.29, 9.29))
            path.addLine(to: point(8.7, 9.29))
            path.addLine(to: point(12, 6))
        case .chevronUp:
            path.move(to: point(4, 10))
            path.addLine(to: point(7.29, 6.71))
            path.addLine(to: point(8.7, 6.71))
            path.addLine(to: point(12, 10))
        }
    }
}
#endif
