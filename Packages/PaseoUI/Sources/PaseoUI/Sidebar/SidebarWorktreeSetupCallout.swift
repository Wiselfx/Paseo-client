#if canImport(UIKit)
import SwiftUI

/// The quiet "Set up worktree scripts" callout under a project (see `worktreeSetupCallout`):
/// the body opens the project page, the xmark dismisses it.
struct SidebarWorktreeSetupCallout: View {
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .frame(width: 26, height: 26)
                        .background(Palette.chip, in: .circle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Set up worktree scripts")
                            .font(.paseo(.footnote, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                        Text("Add setup commands so new worktrees can prepare themselves.")
                            .font(.paseo(.caption2))
                            .foregroundStyle(Palette.captionInk)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set up worktree scripts")
            .accessibilityHint("Opens the project page.")
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.glyph(.small, weight: .regular))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 30, height: 30)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Palette.chip.opacity(0.55), in: .rect(cornerRadius: Radius.sm))
        .padding(.top, 4)
    }
}
#endif
