#if canImport(UIKit)
import SwiftUI

/// The callout for a missing forge CLI step, with each command as a copy chip.
struct ForgeSetupBanner: View {
    let issue: ForgeSetupIssue
    let remoteHost: String?

    @State private var copiedCommand: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal")
                .font(.glyph(.regular, weight: .medium))
                .foregroundStyle(Palette.warning)
            VStack(alignment: .leading, spacing: 6) {
                Text(issue.title)
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text("Run this on the host, then refresh:")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                ForEach(issue.commands(remoteHost: remoteHost), id: \.self) { command in
                    copyChip(command)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.sm)
        .background(Palette.warning.opacity(0.08))
        .paseoFeedback(.light, trigger: copiedCommand) { _, new in new != nil }
    }

    private func copyChip(_ command: String) -> some View {
        Button {
            Clipboard.copy(command)
            copiedCommand = command
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copiedCommand == command { copiedCommand = nil }
            }
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: copiedCommand == command ? "checkmark" : "doc.on.doc")
                    .font(.glyph(.small, weight: .semibold))
                Text(command)
                    .font(.paseo(.codeSmall))
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Palette.chip, in: .capsule)
            .padding(.vertical, Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(command)")
    }
}
#endif
