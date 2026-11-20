#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Provider subagent status: dot color and sentence-case label.
enum SubagentStatusWord {
    static func label(_ status: ProviderSubagent.Status) -> String {
        switch status {
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .canceled: "Canceled"
        case .unknown: "Unknown"
        }
    }

    static func dot(_ status: ProviderSubagent.Status) -> Color {
        switch status {
        case .running: Palette.accentInk
        case .completed: Palette.successInk
        case .failed: Palette.failureInk
        case .canceled, .unknown: Palette.tertiaryInk
        }
    }
}
#endif
