#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The tool call's status, as a 6 pt dot with a spinner while it runs. The dot is its own
/// accessibility element so VoiceOver speaks the status; with Differentiate Without Color on, a
/// failure is an "x" rather than only a red dot.
struct ClaudeStatusDot: View {
    var status: ToolCallPresentation.Status

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        switch status {
        case .running: ProgressView().controlSize(.mini)
        case .succeeded:
            Circle().fill(Palette.successInk).frame(width: 6, height: 6)
                .accessibilityElement()
                .accessibilityLabel("Succeeded")
        case .failed:
            if differentiateWithoutColor {
                Image(systemName: "xmark")
                    .font(.glyph(.small, weight: .bold))
                    .foregroundStyle(Palette.failureInk)
                    .accessibilityLabel("Failed")
            } else {
                Circle().fill(Palette.failureInk).frame(width: 6, height: 6)
                    .accessibilityElement()
                    .accessibilityLabel("Failed")
            }
        case .canceled:
            Circle().strokeBorder(Palette.tertiaryInk, lineWidth: 1).frame(width: 6, height: 6)
                .accessibilityElement()
                .accessibilityLabel("Canceled")
        }
    }
}
#endif
