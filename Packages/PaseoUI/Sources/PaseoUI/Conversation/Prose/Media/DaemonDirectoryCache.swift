#if canImport(UIKit)
import Foundation
import PaseoStore

// MARK: - DaemonDirectoryCache (G10/G11 §12)

// NOTE: RemoteImagePipeline/G10: every file card and video poster needs its parent
// listing for the size, and N cards in one directory remount together. Without this,
// one directory costs N listings per remount. The cache holds one listing per
// (workspace, dir) — one in-flight fetch (coalesced: late joiners await the same
// fetch) and the result for 30 s — and answers synchronously on the first pass so a
// remount shows the size on frame one instead of flashing the bare row.

/// One coalesced parent listing per directory, for card sizes.
@MainActor
final class DaemonDirectoryCache {
    static let shared = DaemonDirectoryCache()

    private struct Entry {
        var result: [FileExplorerEntry]?
        var at: Date
    }

    private var table: [String: Entry] = [:]
    private var waiters: [String: [CheckedContinuation<[FileExplorerEntry]?, Never>]] = [:]
    /// Long enough to cover a remount storm, short enough that a rename never lies.
    private let ttl: TimeInterval = 30

    private func key(workspaceID: String, dir: String) -> String {
        "\(workspaceID)\0\(dir)"
    }

    /// The listing when it is already here and fresh, for the first body pass.
    func cached(workspaceID: String, dir: String) -> [FileExplorerEntry]? {
        guard let entry = table[key(workspaceID: workspaceID, dir: dir)],
            let result = entry.result,
            Date().timeIntervalSince(entry.at) < ttl
        else { return nil }
        return result
    }

    /// The listing, fetching once when N cards ask together: late joiners await the
    /// in-flight fetch instead of starting their own.
    func entries(
        workspaceID: String, dir: String,
        fetch: (String, String) async -> [FileExplorerEntry]?
    ) async -> [FileExplorerEntry]? {
        if let hit = cached(workspaceID: workspaceID, dir: dir) { return hit }
        let cacheKey = key(workspaceID: workspaceID, dir: dir)
        if waiters[cacheKey] != nil {
            return await withCheckedContinuation { continuation in
                waiters[cacheKey, default: []].append(continuation)
            }
        }
        waiters[cacheKey] = []
        // Direct await, no Task: the fetch closure is workspace-scoped and
        // non-Sendable, and this cache never leaves the main actor.
        let result = await fetch(workspaceID, dir)
        table[cacheKey] = Entry(result: result, at: Date())
        for waiter in waiters[cacheKey, default: []] {
            waiter.resume(returning: result)
        }
        waiters[cacheKey] = nil
        return result
    }
}
#endif
