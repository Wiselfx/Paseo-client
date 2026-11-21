#if canImport(UIKit)
import SwiftUI

/// One check-status counter on the live PR card: a colored dot and its count. A zero count is
/// hidden from VoiceOver, which reads the card's own checks summary instead.
struct CheckDot: View {
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("\(count)")
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .monospacedDigit()
        }
        .accessibilityHidden(count == 0)
    }
}
#endif
