#if canImport(UIKit)
import SwiftUI

/// The drawer affordance: three rules, the last one short.
struct UnequalMenu: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            for (y, width) in [(0.1, 1.0), (0.5, 1.0), (0.9, 0.5)] {
                p.move(to: CGPoint(x: 0, y: rect.height * y))
                p.addLine(to: CGPoint(x: rect.width * width, y: rect.height * y))
            }
        }
    }
}
/// The host caps an open process card at `min(400pt, 50% of height)`; the chat root publishes the
/// screen-derived value so the card doesn't have to guess at its own container.
extension EnvironmentValues {
    @Entry var claudeProcessCap: CGFloat = 400
}
#endif
