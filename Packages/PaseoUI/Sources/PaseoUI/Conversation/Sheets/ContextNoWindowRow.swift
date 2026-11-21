#if canImport(UIKit)
import SwiftUI

/// The same header slot as `ContextMeterRow`, with no window to draw: the composer's empty
/// track, and upstream's wording (`contextWindow.noData`) where the percentage goes — its
/// details sheet draws that line and keeps the session figures below it
/// (`context-window-details.tsx:52-55`).
struct ContextNoWindowRow: View {
    var body: some View {
        HStack(spacing: 18) {
            ClaudeMeterRing(
                percent: 0, size: 64, lineWidth: 6, tint: Palette.secondaryInk, drawsArc: false)
            Text("No context data")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.xl)
    }
}
#endif
