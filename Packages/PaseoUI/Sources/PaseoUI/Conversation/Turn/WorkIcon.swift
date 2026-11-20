#if canImport(UIKit)
import SwiftUI

/// The one icon language of an agent's work: a light SF Symbol inside a hairline ring, the same
/// size, weight and ink for every kind of step, so a thought, a command and an edit read as one
/// family. A running step swaps its symbol for a spinner in the same ring; a failed one takes the
/// failure ink. Replaces the hand-drawn glyphs and the filled discs the timeline wore before.
struct WorkIcon: View {
    enum Kind: Equatable, Sendable {
        case thought
        case tools
        case shell
        case read
        case edit
        case write
        case search
        case webSearch
        case fetch
        case more
        /// Any other tool: its presentation's symbol.
        case symbol(String)

        var systemName: String {
            switch self {
            case .thought: "sparkle"
            case .tools: "wrench.adjustable"
            case .shell: "terminal"
            case .read: "doc.text"
            case .edit: "pencil.line"
            case .write: "doc.badge.plus"
            case .search: "magnifyingglass"
            case .webSearch: "globe"
            case .fetch: "link"
            case .more: "ellipsis"
            case .symbol(let name): name
            }
        }
    }

    let kind: Kind
    var running = false
    var failed = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(failed ? Palette.failureInk.opacity(0.45) : Palette.cardBorder, lineWidth: 1)
            if running {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: kind.systemName)
                    .font(.glyph(.small, weight: .regular))
                    .imageScale(.small)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(failed ? Palette.failureInk : Palette.secondaryInk)
            }
        }
        .frame(width: WorkTimelineMetrics.nodeSize, height: WorkTimelineMetrics.nodeSize)
        .accessibilityHidden(true)
    }
}
#endif
