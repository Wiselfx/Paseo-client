#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The parsed terminal, by output key (see `key(for:)`): every remount reads the same parse
/// synchronously instead of re-parsing (a remount storm on a 1 MB log is a jump plus repeated
/// work). `NSCache` reads are O(1) and thread-safe.
enum TerminalParseCache {
    nonisolated(unsafe) private static let table: NSCache<NSString, ParsedTerminalBox> = {
        let cache = NSCache<NSString, ParsedTerminalBox>()
        cache.countLimit = 16
        return cache
    }()

    /// UTF-8 bytes hashed at each end of the output for the key.
    static let sampleBytes = 512

    /// Stable per content, and O(1) however large the output is: the UTF-8 byte count plus a hash
    /// of the first and last `sampleBytes` bytes. `body` asks for the key on every pass until a
    /// parse lands, so hashing the whole output here would cost O(output) per pass. The sample
    /// can miss a change in the middle: two outputs of the same length that agree at both ends
    /// share a key, and the cache then shows the other output's tail until the length changes
    /// again (a stale display, never a crash).
    static func key(for output: String) -> String {
        let utf8 = output.utf8
        var hasher = Hasher()
        for byte in utf8.prefix(sampleBytes) { hasher.combine(byte) }
        for byte in utf8.suffix(sampleBytes) { hasher.combine(byte) }
        return "\(utf8.count)-\(hasher.finalize())"
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
