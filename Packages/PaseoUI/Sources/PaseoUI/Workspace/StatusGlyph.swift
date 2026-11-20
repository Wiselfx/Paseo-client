#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

struct StatusGlyph: View {
    let status: WorkspaceSetupStatus?

    var body: some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small).tint(Palette.secondaryInk)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.successInk)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Palette.failureInk)
        case .blocked:
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(Palette.warning)
        default:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(Palette.tertiaryInk)
        }
    }
}
#endif
