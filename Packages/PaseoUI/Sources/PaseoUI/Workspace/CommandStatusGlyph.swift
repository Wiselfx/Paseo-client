#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

struct CommandStatusGlyph: View {
    let status: WorkspaceSetupCommandStatus
    let exitCode: Int?

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
    }
}
#endif
