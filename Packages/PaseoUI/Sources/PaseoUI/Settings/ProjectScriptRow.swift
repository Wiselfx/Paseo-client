#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One script of the project: its name and command, and an actions menu.
struct ProjectScriptRow: View {
    let script: ProjectScriptDraft
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(script.name.isEmpty ? "Unnamed script" : script.name)
                    .font(.paseo(.code, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(script.command.isEmpty ? "No command" : script.command)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Actions for \(script.name.isEmpty ? "unnamed script" : script.name)")
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: 51)
    }
}
#endif
