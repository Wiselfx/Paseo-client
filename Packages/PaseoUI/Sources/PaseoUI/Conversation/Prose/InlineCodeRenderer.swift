#if canImport(UIKit)
import SwiftUI

    struct InlineCodeRenderer: TextRenderer {
        var background: Color
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            for line in layout {
                for run in line {
                    if run[InlineCodeAttribute.self] != nil {
                        context.fill(
                            Path(roundedRect: run.typographicBounds.rect.insetBy(dx: -1, dy: -1), cornerRadius: Radius.xs),
                            with: .color(background))
                    }
                    context.draw(run)
                }
            }
        }
    }
#endif
