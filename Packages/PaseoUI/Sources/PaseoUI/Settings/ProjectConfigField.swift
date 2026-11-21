#if canImport(UIKit)
import SwiftUI

/// One multi-line command field of the worktree group: one command per line.
struct ProjectConfigField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            TextField(
                title, text: $text,
                prompt: Text(placeholder).foregroundStyle(Palette.tertiaryInk),
                axis: .vertical
            )
            .font(.paseo(.code))
            .foregroundStyle(Palette.ink)
            .lineLimit(3...8)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }
}
#endif
