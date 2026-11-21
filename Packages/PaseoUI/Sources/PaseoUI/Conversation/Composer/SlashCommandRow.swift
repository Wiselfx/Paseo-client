#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One row of the slash-command menu: `/name`, its argument hint, the skill mark, and the
/// description under it.
struct SlashCommandRow: View {
    let command: AgentSlashCommand
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("/\(command.name)")
                        .font(.paseo(.code, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if !command.argumentHint.isEmpty {
                        Text(command.argumentHint)
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.tertiaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if command.kind == .skill {
                        Image(systemName: "sparkles")
                            .font(.glyph(.small, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityLabel("Skill")
                    }
                }
                if !command.description.isEmpty {
                    Text(command.description)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            ["/\(command.name)", command.description]
                .filter { !$0.isEmpty }
                .joined(separator: ", "))
    }
}
#endif
