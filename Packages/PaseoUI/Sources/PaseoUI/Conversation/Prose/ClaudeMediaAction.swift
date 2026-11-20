import Foundation

@nonexhaustive public enum ClaudeMediaAction: Equatable, Sendable {
    case beginSelection, toggleRecent(String), attachSelected, cancelSelection
    case removeDraft(String), open(ClaudeMedia), close, toggleControls
    case requestPhotos, copyFileName(ClaudeMedia), edit(ClaudeMedia), share(ClaudeMedia), download(ClaudeMedia)
    case videoViewerAppeared(ClaudeMedia), videoViewerDisappeared(ClaudeMedia)
}
