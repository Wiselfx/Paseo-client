#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The tool call's status, as a 6 pt dot with a spinner while it runs.
struct ClaudeStatusDot: View {
    var status: ToolCallPresentation.Status

    var body: some View {
        switch status {
        case .running: ProgressView().controlSize(.mini)
        case .succeeded: Circle().fill(Palette.successInk).frame(width: 6, height: 6)
        case .failed: Circle().fill(Palette.failureInk).frame(width: 6, height: 6)
        case .canceled: Circle().strokeBorder(Palette.tertiaryInk, lineWidth: 1).frame(width: 6, height: 6)
        }
    }
}
#endif
