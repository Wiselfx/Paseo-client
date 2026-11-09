import Foundation

/// M7f (`Chat display`, Settings → General → Chat): how much of the conversation is on screen.
/// Persisted as `paseo.chatDisplay`; default Full.
///
/// - `full`: the current layout — work groups fold on their own, answers render fully.
/// - `collapseToolCalls`: work groups start collapsed even while their turn runs (find expands
///   whatever holds a match).
/// - `collapseTurns`: completed turns older than the last show the prompt plus the turn
///   summary; the answer itself always renders in full (UX spec §4.3 forbids clipping a
///   message behind "Show more").
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
