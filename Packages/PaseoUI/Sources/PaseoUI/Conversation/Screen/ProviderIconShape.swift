#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Draws a provider's catalogue mark (`ProviderIcon`, parsed from the daemon's `iconSvg`) as one
/// filled path, ink only (§0.1). The view box is scaled to fit and centred, so marks with their
/// own aspect ratio (the catalogue has 24×24, 128×128 and 466×532 boxes) all land in the glyph
/// frame the same size.
struct ProviderIconShape: Shape {
    var icon: ProviderIcon

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let box = icon.viewBox
        guard box.width > 0, box.height > 0 else { return path }
        let scale = min(rect.width / CGFloat(box.width), rect.height / CGFloat(box.height))
        let insetX = rect.minX + (rect.width - CGFloat(box.width) * scale) / 2
        let insetY = rect.minY + (rect.height - CGFloat(box.height) * scale) / 2

        func point(_ source: ProviderIcon.Point) -> CGPoint {
            CGPoint(
                x: insetX + CGFloat(source.x - box.x) * scale,
                y: insetY + CGFloat(source.y - box.y) * scale)
        }

        for subpath in icon.paths {
            for segment in subpath.segments {
                switch segment {
                case .move(let end):
                    path.move(to: point(end))
                case .line(let end):
                    path.addLine(to: point(end))
                case .cubic(let control1, let control2, let end):
                    path.addCurve(
                        to: point(end), control1: point(control1), control2: point(control2))
                case .quad(let control, let end):
                    path.addQuadCurve(to: point(end), control: point(control))
                case .close:
                    path.closeSubpath()
                }
            }
        }
        return path
    }
}
#endif
