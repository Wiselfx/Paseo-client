#if canImport(UIKit)
import SwiftUI

/// The merge-conflict callout, with "Ask the agent" mentioning the conflicted files in chat.
struct ChangesConflictBanner: View {
    let title: String
    let conflictFiles: [String]

    @Environment(\.mentionInChat) private var mentionInChat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.glyph(.regular, weight: .medium))
                .foregroundStyle(Palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text("Ask the agent to resolve it.")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !conflictFiles.isEmpty, let mentionInChat {
                Button {
                    Haptics.light()
                    for path in conflictFiles.prefix(10) {
                        mentionInChat(path)
                    }
                } label: {
                    Text("Ask the agent")
                        .font(.paseo(.caption, weight: .medium))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, Space.md)
                        .frame(minHeight: 30)
                        .background(Palette.ink, in: .capsule)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mention the conflicted files in chat")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.sm)
        .background(Palette.warning.opacity(0.08))
    }
}
#endif
