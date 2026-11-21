#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// A compaction in the timeline: a hairline on each side, a spinner while it runs (a scissors
/// glyph once it is done), and the label. Upstream `message.tsx:1426-1470`; the words are
/// `message-compaction-label.ts:10-27` (`en.ts:411-417`).
struct ClaudeCompactionMarker: View {
    let status: String
    /// `auto` / `manual`; absent on old daemons and on the loading row.
    let trigger: String?
    let preTokens: Int?


    var body: some View {
        HStack(spacing: 8) {
            ClaudeDivider()
            HStack(spacing: 8) {
                if status == "loading" {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "scissors").font(.glyph(.small, weight: .regular))
                        .accessibilityHidden(true)
                }
                Text(Self.label(status: status, trigger: trigger, preTokens: preTokens))
                    .font(.paseo(.footnote))
                    .multilineTextAlignment(.center)
                    .layoutPriority(1)
            }
            .foregroundStyle(Palette.tertiaryInk)
            ClaudeDivider()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    /// Upstream's order, exactly: loading wins, then the trigger, then the token count, then the
    /// bare "completed" line. The count is `Math.round(preTokens / 1000)` followed by "K"
    /// (`message-compaction-label.ts:21-25`); UX-SPEC §0.2 groups the digits.
    static func label(status: String, trigger: String?, preTokens: Int?) -> String {
        if status == "loading" { return "Compacting..." }
        if trigger == "auto" { return "Context automatically compacted" }
        if trigger == "manual" { return "Context manually compacted" }
        if let preTokens, preTokens != 0 {
            let thousands = Int((Double(preTokens) / 1000).rounded())
            return "Context compacted (\(PaseoFormat.integer(thousands))K tokens)"
        }
        return "Context compacted"
    }
}
#endif
