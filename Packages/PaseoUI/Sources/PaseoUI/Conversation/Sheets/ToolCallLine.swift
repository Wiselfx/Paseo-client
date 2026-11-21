#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A one-line `verb · argument` for a tool call, e.g. `Read · src/server.ts`.
struct ToolCallLine: View {
    let call: ToolCall

    private var presentation: ToolCallPresentation { ToolCallPresentation(call) }

    var body: some View {
        HStack(spacing: Space.sm) {
            Text(presentation.title)
                .font(.paseo(.codeSmall))
                .foregroundStyle(Palette.tertiaryInk)
            if let subtitle = presentation.subtitle {
                Text(subtitle)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
