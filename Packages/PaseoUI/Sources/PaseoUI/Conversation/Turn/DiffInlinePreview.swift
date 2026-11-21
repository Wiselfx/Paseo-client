#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The first lines of a diff, sideways-scrollable (or wrapped), never a scroller inside the
/// transcript, plus "Show all" when the diff is longer.
struct DiffInlinePreview: View {
    let lines: [ClaudeDiffLine]
    let wrap: Bool
    /// What "Show all" opens in the sheet.
    let document: ClaudeDiffDocument

    @Environment(\.chatActions) private var actions

    var body: some View {
        let shown = lines.prefix(ClaudeDiffView.inlineLines)
        Group {
            if wrap {
                DiffLineStack(lines: shown, wrap: true)
            } else {
                ScrollView(.horizontal) { DiffLineStack(lines: shown, wrap: false) }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        if lines.count > ClaudeDiffView.inlineLines, let actions {
            Button("Show all \(PaseoFormat.integer(lines.count)) lines") {
                actions.showDiff(document)
            }
            .font(.paseo(.caption, weight: .medium))
            .foregroundStyle(Palette.secondaryInk)
            .frame(minHeight: Metrics.hitSize)
            .padding(.horizontal, Space.md)
        }
    }
}
#endif
