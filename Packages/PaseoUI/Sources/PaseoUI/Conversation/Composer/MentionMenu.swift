#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// M8d: @-mentions of files in the composer. `MentionIndex` lazily walks the open workspace's
/// tree once per conversation (breadth-first, pruned and capped); the popover filters in memory.
/// Lives in the composer's slash-menu slot; taps on folders drill in.

struct MentionIndexRow: Identifiable, Hashable {
    var path: String
    var isDirectory: Bool

    var id: String { path }
}

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

/// The @-mention popover. Same chrome as the slash menu. Tap a row: files insert, folders drill in.
struct MentionMenu: View {
    let rows: [MentionIndexRow]
    let isBuilding: Bool
    let onPick: (MentionIndexRow) -> Void


    var body: some View {
        ComposerMenuContainer(accessibilityIdentifier: "composer.mentionMenu") {
            if isBuilding, rows.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading files…")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            mentionRow(row)
                        }
                    }
                }
                .frame(maxHeight: 248)
                .scrollIndicators(.hidden)
            }
        }
    }

    private func mentionRow(_ row: MentionIndexRow) -> some View {
        Button {
            onPick(row)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: row.isDirectory ? "folder" : "doc")
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 20)
                Text("@" + row.path.trimmingSuffix(while: { $0 == "/" }))
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if row.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.glyph(.small, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.isDirectory ? "Folder \(row.path)" : "File \(row.path)")
        .accessibilityAddTraits(row.isDirectory ? [] : .isButton)
    }
}

private extension String {
    func trimmingSuffix(while predicate: (Character) -> Bool) -> String {
        var end = endIndex
        while end > startIndex, predicate(self[index(before: end)]) {
            end = index(before: end)
        }
        return String(self[..<end])
    }
}
#endif
