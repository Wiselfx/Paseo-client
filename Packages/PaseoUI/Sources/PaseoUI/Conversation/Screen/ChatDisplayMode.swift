import Foundation

/// M7f (`Chat display`, Settings → General → Chat): how much of the conversation is on screen.
/// Persisted as `paseo.chatDisplay`; default Full.
///
/// - `full`: every turn in full. A turn's thinking and tool calls are always folded into their
///   two summary lines (`WorkDigest`); there is no separate mode for that any more.
/// - `collapseTurns`: completed turns older than the last show only the prompt, the outcome line
///   and the answer, without the copy / fork footer. Every finished turn already folds its work
///   behind the outcome line, so both modes open the work with the same single tap; the answer
///   always renders in full (UX spec §4.3 forbids clipping a message behind "Show more").
enum ChatDisplayMode: String, CaseIterable {
    case full
    case collapseTurns

    static let storageKey = "paseo.chatDisplay"

    var label: String {
        switch self {
        case .full: "Full"
        case .collapseTurns: "Collapse turns"
        }
    }
}
