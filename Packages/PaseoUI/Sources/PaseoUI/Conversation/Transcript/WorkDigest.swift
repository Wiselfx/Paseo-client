#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// A work run between two pieces of prose, as at most two lines:
///
///     ✦ Thought for 12s                        ›
///     ⚒ Called 7 tools  edited 3 files and …   ›
///
/// All the run's thinking is one section and all its tool calls are the other, both folded by
/// default and both building their content only when opened. Folded, each is one fixed-height
/// line that shows the live state while the run streams, so a thinking model or a burst of
/// calls never makes the transcript jump.
struct WorkDigest: View {
    let group: Turn.WorkGroup
    /// The run is the turn's newest segment while the turn runs.
    let isTail: Bool
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?

    @State private var memo = WorkDigestMemo()

    var body: some View {
        let digest = memo.digest(for: group)
        VStack(alignment: .leading, spacing: 0) {
            if !digest.thoughts.isEmpty {
                WorkThoughtSection(
                    rows: digest.thoughts,
                    seconds: digest.thoughtSeconds,
                    isLive: isTail && digest.endsInThought,
                    highlighted: highlightedSeq.map { seq in
                        digest.thoughts.contains { $0.seqStart <= seq && seq <= $0.seqEnd }
                    } ?? false,
                    findTarget: findTarget)
            }
            if !digest.steps.isEmpty {
                WorkToolsSection(
                    steps: digest.steps,
                    callCount: group.toolCallCount,
                    failures: digest.failures,
                    summary: digest.summary,
                    live: isTail ? digest.running : nil,
                    highlightedSeq: highlightedSeq,
                    findTarget: findTarget,
                    onOpenFile: onOpenFile)
            }
        }
    }

    /// What the calls of a run amounted to, lowercased to follow "Called N tools": "edited 3
    /// files and ran 2 commands". Empty when nothing more specific than the count can be said.
    nonisolated static func summaryText(_ group: Turn.WorkGroup) -> String {
        var editedFiles = Set<String>()
        var readFiles = Set<String>()
        var commands = 0
        var searches = 0
        for row in group.rows {
            guard case .toolCall(let call) = row.item else { continue }
            switch call.detail {
            case .edit(let path, _, _, _), .write(let path, _): editedFiles.insert(path)
            case .read(let path, _): readFiles.insert(path)
            case .shell: commands += 1
            case .search: searches += 1
            default: break
            }
        }
        var parts: [String] = []
        if !editedFiles.isEmpty { parts.append(counted(editedFiles.count, "edited", "file")) }
        if commands > 0 { parts.append(counted(commands, "ran", "command")) }
        if !readFiles.isEmpty { parts.append(counted(readFiles.count, "read", "file")) }
        if searches > 0 { parts.append(counted(searches, "searched", "time")) }
        return parts.formatted(.list(type: .and))
    }

    private nonisolated static func counted(_ count: Int, _ verb: String, _ noun: String) -> String {
        "\(verb) \(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
#endif
