#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

struct CommandStatusGlyph: View {
    let status: WorkspaceSetupCommandStatus
    let exitCode: Int?

    /// What VoiceOver says for the symbol: the glyph is the only indicator of the outcome.
    private var accessibilityText: LocalizedStringKey {
        switch status {
        case .running: "Running"
        case .completed: (exitCode ?? 0) == 0 ? "Succeeded" : "Failed"
        case .failed: "Failed"
        case .unknown: "Status unknown"
        }
    }

    var body: some View {
        Group {
            switch status {
            case .running:
                ProgressView().controlSize(.mini).tint(Palette.secondaryInk)
            case .completed:
                if (exitCode ?? 0) == 0 {
                    Image(systemName: "checkmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.successInk)
                } else {
                    Image(systemName: "xmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.failureInk)
                }
            case .failed:
                Image(systemName: "xmark")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.failureInk)
            case .unknown:
                Image(systemName: "questionmark")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
#endif
