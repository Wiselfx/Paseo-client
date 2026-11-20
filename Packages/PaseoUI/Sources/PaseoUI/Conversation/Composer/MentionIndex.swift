#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// The lazily built, in-memory file index for one workspace (per conversation view).
@MainActor @Observable
final class MentionIndex {
    private(set) var rows: [MentionIndexRow] = []
    private(set) var isBuilding = false
    private(set) var truncated = false

    static let entryCap = 2000
    static let depthCap = 5
    /// Never worth offering in a mention: dependency directories and VCS metadata.
    static let skippedDirectories: Set<String> = [
        ".git", "node_modules", ".build", ".venv", "__pycache__", "Pods", "DerivedData",
        ".next", "dist", ".cache", "build",
    ]

    /// BFS walk of the workspace (breadth-first keeps shallow rows first). The walk skips
    /// noise directories, stops at `entryCap`, and leaves `rows` sorted shallow-first.
    ///
    /// The walk runs on a scratch copy of `WorkspaceFiles`, so the Files panel never moves.
    func build(using shared: WorkspaceFiles) async {
        guard !isBuilding, rows.isEmpty else { return }
        isBuilding = true
        let files = shared.makeScratch()
        var out: [MentionIndexRow] = []
        var queue: [String] = [""]
        var index = 0
        while index < queue.count {
            if out.count >= MentionIndex.entryCap {
                truncated = true
                break
            }
            let dir = queue[index]
            index += 1
            await files.list(dir.isEmpty ? nil : dir)
            guard files.phase == .ready else { continue }
            for entry in files.entries {
                if MentionIndex.skippedDirectories.contains(entry.name) { continue }
                out.append(MentionIndexRow(path: entry.path, isDirectory: entry.isDirectory))
                if entry.isDirectory {
                    let depth = entry.path.split(separator: "/").count
                    if depth < MentionIndex.depthCap { queue.append(entry.path) }
                }
                if out.count >= MentionIndex.entryCap {
                    truncated = true
                    break
                }
            }
        }
        rows = out
        isBuilding = false
    }

    /// Ranks matches for `query`: recent mentions first (1000-point bonus), then prefix,
    /// then path-component prefix, then substring. Directories edge files; shallower first.
    func matches(query: String, recent: [String]) -> [MentionIndexRow] {
        let q = query.lowercased()
        let recentSet = Set(recent)
        if q.isEmpty {
            var seen = Set<String>()
            var shallow: [MentionIndexRow] = []
            for row in rows where row.path.split(separator: "/").count <= 2 {
                if seen.insert(row.path).inserted { shallow.append(row) }
            }
            let recentRows = recent.compactMap { path in rows.first { $0.path == path } }
            var merged: [MentionIndexRow] = []
            for row in recentRows + shallow where seen.insert(row.path).inserted {
                merged.append(row)
            }
            return Array(merged.prefix(6))
        }
        var scored: [(row: MentionIndexRow, score: Int)] = []
        for row in rows {
            let path = row.path.lowercased()
            var score = 0
            if path == q {
                score = 120
            } else if path.hasPrefix(q) {
                score = 100
            } else if path.split(separator: "/").contains(where: { $0.hasPrefix(q) }) {
                score = 70
            } else if path.contains("/" + q) {
                score = 60
            } else if path.contains(q) {
                score = 40
            } else {
                continue
            }
            if row.isDirectory { score += 5 }
            if recentSet.contains(row.path) { score += 1000 }
            scored.append((row, score))
        }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                let d0 = $0.row.path.split(separator: "/").count
                let d1 = $1.row.path.split(separator: "/").count
                if d0 != d1 { return d0 < d1 }
                return $0.row.path.localizedCaseInsensitiveCompare($1.row.path) == .orderedAscending
            }
            .map(\.row)
            .prefix(6)
            .map { $0 }
    }
}
#endif
