#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// Error, notification, compaction, and the daemon's newer item types, as light chips.
struct ClaudeNoticeRow: View {
    let item: TimelineItem


    var body: some View {
        switch item {
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.failureInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .notification(let level, let message):
            Label(message, systemImage: level == "warning" ? "exclamationmark.circle" : "info.circle")
                .font(.paseo(.callout))
                .foregroundStyle(level == "error" ? Palette.failureInk : Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .compaction(let status, let trigger, let preTokens):
            ClaudeCompactionMarker(status: status, trigger: trigger, preTokens: preTokens)
        case .unknown(let type, _):
            // A debugging aid: a host may send item types this build doesn't know yet (§20).
            #if DEBUG
            Text("Unsupported item: \(type)")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        default:
            EmptyView()
        }
    }
}
#endif
