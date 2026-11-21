#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The parsed terminal, by output identity: every remount reads the same parse
/// synchronously instead of re-parsing (a remount storm on a 1 MB log is a jump
/// plus repeated work). `NSCache` reads are O(1) and thread-safe.
enum TerminalParseCache {
    nonisolated(unsafe) private static let table: NSCache<NSString, ParsedTerminalBox> = {
        let cache = NSCache<NSString, ParsedTerminalBox>()
        cache.countLimit = 16
        return cache
    }()

    /// Stable per content: length plus hash (a display cache — a collision shows
    /// the wrong tail until the output changes again, at ~2^-64 odds).
    static func key(for output: String) -> String {
        "\(output.utf8.count)-\(output.hashValue)"
    }

    static func entry(for output: String) -> ClaudeCodeBlock.ParsedTerminal? {
        table.object(forKey: key(for: output) as NSString)?.value
    }

    static func store(_ parsed: ClaudeCodeBlock.ParsedTerminal, for output: String) {
        table.setObject(ParsedTerminalBox(value: parsed), forKey: key(for: output) as NSString)
    }
}
/// The label for a rewind scope in the menu and the confirm dialog (upstream copy, en.ts).
func rewindScopeTitle(_ scope: RewindScope) -> String {
    switch scope {
    case .conversation: "Rewind conversation"
    case .files: "Rewind files"
    case .both: "Rewind conversation and files"
    case .unknown: "Rewind to this message"
    }
}
#endif
