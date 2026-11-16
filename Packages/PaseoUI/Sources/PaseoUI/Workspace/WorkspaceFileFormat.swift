#if canImport(UIKit)
import Foundation
import PaseoStore

/// Small formatting and path helpers for the Files page. Kept out of the views so the pages stay
/// declarative and the string fiddling has one home.
enum WorkspaceFileFormat {
    /// The workspace-relative path for an entry: what the daemon sends is either relative to the
    /// checkout root or absolute; both are made relative here.
    static func relativePath(_ path: String, cwd: String) -> String {
        var root = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if root.hasSuffix("/") { root = String(root.dropLast()) }
        let prefix = root + "/"
        if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        if path.hasPrefix("./") { return String(path.dropFirst(2)) }
        return path
    }

    /// `foo/bar/baz.txt` as `baz.txt`.
    static func lastComponent(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
    }

    /// The directory a path lives in, relative: `foo/bar` → `foo`; `foo` → "" (root).
    static func containingDirectory(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
    }

    /// 842 B, 1.4 MB, 2.1 GB. The daemon sends bytes (FileExplorerEntrySchema
    /// `size`, messages.ts:2937-2943); formatting is PaseoFormat's (UX-SPEC §0.2).
    static func bytes(_ size: Int) -> String {
        PaseoFormat.bytes(size)
    }

    /// `2026-11-08T20:56:19Z` → `3m ago`, `yesterday`, `11/3/26, 4:56 PM`. Uses the shared
    /// `PaseoFormat` formatters instead of building one per row (audit B N10). Unknown input is
    /// shown trimmed.
    @MainActor
    static func relativeModified(_ modifiedAt: String) -> String {
        let trimmed = modifiedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = PaseoDate.parse(trimmed) ?? epoch(trimmed) else { return trimmed }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds >= 7 * 86_400 { return PaseoFormat.dateTime(date) }
        return PaseoFormat.relative(date)
    }

    /// "size · relative date" for a row; either half may be missing.
    @MainActor
    static func metaLine(size: Int, modifiedAt: String?) -> String? {
        var parts: [String] = []
        if size > 0 { parts.append(bytes(size)) }
        if let modifiedAt, !modifiedAt.isEmpty {
            parts.append(relativeModified(modifiedAt))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func epoch(_ string: String) -> Date? {
        // Epoch seconds or milliseconds, all digits.
        guard let value = Double(string), value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
    }
}
#endif
