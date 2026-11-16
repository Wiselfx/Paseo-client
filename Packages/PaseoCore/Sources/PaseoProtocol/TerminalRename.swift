import Foundation

// Terminal rename: the daemon sets the terminal's title; the UI shows it in the tab strip.
//
// Source: messages.ts `RenameTerminalRequestSchema`, `RenameTerminalResponseSchema`.

/// Source: messages.ts `RenameTerminalRequestSchema`.
public struct RenameTerminalRequest: PaseoRequest {
    public static let type = "terminal.rename.request"
    public static let responseType = "terminal.rename.response"
    public var requestId = ""
    public var terminalId: String
    /// The new title shown for the terminal.
    public var title: String

    public init(terminalId: String, title: String) {
        self.terminalId = terminalId
        self.title = title
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var success: Bool
        public var error: String?
    }
}
