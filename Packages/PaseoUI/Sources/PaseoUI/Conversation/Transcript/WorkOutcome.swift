#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// What came of a call, at the line's end: a failed exit, a failure, a stop.
struct WorkOutcome: View {
    let call: ToolCall

    private var words: (text: String, failed: Bool)? {
        var exit: Int?
        if case .shell(_, _, _, let code?) = call.detail, code.isFinite, abs(code) < 1e9 {
            exit = Int(code)
        }
        if let exit, exit != 0 { return ("Exit \(exit)", true) }
        switch call.status {
        case .failed: return ("Failed", true)
        case .canceled: return ("Stopped", false)
        default: return nil
        }
    }

    /// The outcome as it is spoken, for a row whose label replaces this view.
    var accessibilityText: String? { words?.text }

    var body: some View {
        if let words {
            Text(words.text)
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(words.failed ? Palette.failureInk : Palette.tertiaryInk)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
#endif
