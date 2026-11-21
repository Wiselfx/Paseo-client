#if canImport(UIKit)
import SwiftUI

/// The context sheet's header: the usage ring, the percentage and, when known, the window size.
struct ContextMeterRow: View {
    let percent: Double
    let maxTokens: Int?

    var body: some View {
        HStack(spacing: 18) {
            ClaudeMeterRing(percent: percent, size: 64, lineWidth: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(PaseoFormat.percent(percent)) used")
                    .monospacedDigit()
                    .font(.paseo(.largeTitle))
                    .foregroundStyle(Palette.ink)
                if let maxTokens {
                    Text("of \(ClaudeContextSheet.tokenCount(maxTokens)) tokens")
                        .monospacedDigit()
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.xl)
    }
}
#endif
