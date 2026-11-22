#if canImport(UIKit)
import SwiftUI

/// The "Hidden workspaces (N)" disclosure at the end of the directory.
struct SidebarHiddenWorkspacesRow: View {
    let count: Int
    let showHidden: Bool
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion), onToggle)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showHidden ? "eye" : "eye.slash")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 24, height: 24)
                    .background(Palette.chip, in: .circle)
                Text("Hidden workspaces (\(PaseoFormat.integer(count)))")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                ClaudeChevron(expanded: showHidden)
            }
            .padding(.top, 12)
            .frame(minHeight: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showHidden ? "Hide hidden workspaces" : "Show hidden workspaces")
        .paseoFeedback(.selection, trigger: showHidden)
    }
}
#endif
