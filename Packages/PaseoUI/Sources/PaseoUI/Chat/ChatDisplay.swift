import Foundation

/// M7f (`Chat display`, Settings → General → Chat): how much of the conversation is on screen.
/// Persisted as `paseo.chatDisplay`; default Full.
///
/// - `full`: the current layout — work groups fold on their own, answers render fully.
/// - `collapseToolCalls`: work groups start collapsed even while their turn runs (find expands
///   whatever holds a match).
/// - `collapseTurns`: completed turns older than the last show the prompt plus the first
///   ~6 lines of the reply with **Show more**; **Show less** folds back.
enum ChatDisplayMode: String, CaseIterable {
    case full
    case collapseToolCalls
    case collapseTurns

    static let storageKey = "paseo.chatDisplay"

    var label: String {
        switch self {
        case .full: "Full"
        case .collapseToolCalls: "Collapse tool calls"
        case .collapseTurns: "Collapse turns"
        }
    }
}
