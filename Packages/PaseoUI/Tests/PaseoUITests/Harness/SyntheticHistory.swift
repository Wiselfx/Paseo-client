import Foundation
import PaseoProtocol

/// A finished conversation as the daemon would send it: one tail page of timeline entries. The
/// content of turn `i` depends only on `i`, so every run (and every scenario) sees the same history.
enum SyntheticHistory {
    static let agentId = "agent-1"
    static let epoch = "synthetic-epoch"
    static let firstSeq = 100

    /// What turn `index` contains, for the report's labels.
    static func kind(_ index: Int) -> String {
        switch index % 10 {
        case 0: "prose"
        case 1: "code14"
        case 2: "code30"
        case 3: "table"
        case 4: "listTable"
        case 5: "quote"
        case 6: "list"
        case 7: "work6"
        case 8: index % 20 == 8 ? "mermaid" : "proseTable"
        default: "mixed"
        }
    }

    static func page(turns: Int) throws -> FetchAgentTimelineRequest.Response {
        var entries: [[String: Any]] = []
        var seq = firstSeq
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for index in 0..<turns {
            let turnId = "turn-\(index)"
            for item in items(forTurn: index) {
                let stamp = formatter.string(from: Date(timeIntervalSince1970: 1_790_000_000 + Double(seq) * 3))
                entries.append([
                    "provider": "synthetic", "item": item, "turnId": turnId, "timestamp": stamp,
                    "seqStart": seq, "seqEnd": seq,
                ])
                seq += 1
            }
        }
        let payload: [String: Any] = [
            "requestId": "synthetic-tail", "agentId": agentId, "direction": "tail", "epoch": epoch,
            "reset": false, "staleCursor": false, "gap": false,
            "window": ["minSeq": firstSeq, "maxSeq": seq - 1, "nextSeq": seq],
            "startCursor": ["epoch": epoch, "seq": firstSeq],
            "endCursor": ["epoch": epoch, "seq": seq - 1],
            "hasOlder": false, "hasNewer": false, "entries": entries,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(FetchAgentTimelineRequest.Response.self, from: data)
    }

    // MARK: Turns

    static func items(forTurn index: Int) -> [[String: Any]] {
        var rng = SplitMix64(seed: 0xC0FF_EE00 &+ UInt64(index) &* 7919)
        var out: [[String: Any]] = []
        out.append(["type": "user_message", "text": userText(index, &rng)])

        let kind = kind(index)
        if kind == "mixed" {
            out.append(["type": "assistant_message", "text": SyntheticText.paragraph(&rng, sentences: 2)])
        }
        let toolCount = kind == "work6" ? 6 : (index % 4 == 0 ? 0 : 1 + index % 3)
        if toolCount > 0 || index % 6 == 0 {
            out.append(["type": "reasoning", "text": SyntheticText.paragraph(&rng, sentences: 2)])
        }
        for k in 0..<toolCount { out.append(toolCall(turn: index, k: k, &rng)) }
        out.append(["type": "assistant_message", "text": answer(index, kind: kind, &rng)])
        return out
    }

    private static func userText(_ index: Int, _ rng: inout SplitMix64) -> String {
        if index % 5 == 0 {
            // A long, multi-line request.
            var lines = ["Please look into the following and tell me what you find:"]
            for _ in 0..<(3 + rng.int(3)) { lines.append("- " + SyntheticText.sentence(&rng, words: 7 + rng.int(9))) }
            lines.append("")
            lines.append(SyntheticText.paragraph(&rng, sentences: 2))
            lines.append("Thanks.")
            return lines.joined(separator: "\n")
        }
        if index % 7 == 0 { return SyntheticText.paragraph(&rng, sentences: 2) }
        return SyntheticText.sentence(&rng, words: 4 + rng.int(8))
    }

    private static func answer(_ index: Int, kind: String, _ rng: inout SplitMix64) -> String {
        func p(_ n: Int = 2) -> String { SyntheticText.paragraph(&rng, sentences: n) }
        switch kind {
        case "prose":
            return SyntheticText.paragraphs(&rng, count: 3 + rng.int(2), sentences: 2...5)
        case "code14":
            return [p(), SyntheticText.codeBlock(&rng, lines: 14), p(1)].joined(separator: "\n\n")
        case "code30":
            return [p(), SyntheticText.codeBlock(&rng, lines: 30), p(2)].joined(separator: "\n\n")
        case "table":
            return [p(1), SyntheticText.tableRows(&rng, rows: 3 + index % 4), p(2)].joined(separator: "\n\n")
        case "listTable":
            let list =
                "- " + SyntheticText.sentence(&rng, words: 8) + "\n- " + SyntheticText.sentence(&rng, words: 10)
                + " Details:\n\n" + SyntheticText.tableRows(&rng, rows: 3, indent: "  ") + "\n\n- "
                + SyntheticText.sentence(&rng, words: 7)
            return [p(1), list, p(1)].joined(separator: "\n\n")
        case "quote":
            return [SyntheticText.quote(&rng, lines: 3), p(3)].joined(separator: "\n\n")
        case "list":
            return [p(1), SyntheticText.bullets(&rng, count: 6), p(1)].joined(separator: "\n\n")
        case "work6":
            return SyntheticText.paragraphs(&rng, count: 2, sentences: 2...4)
        case "mermaid":
            return [p(1), SyntheticText.mermaid, p(2)].joined(separator: "\n\n")
        case "proseTable":
            return [p(2), SyntheticText.tableRows(&rng, rows: 4)].joined(separator: "\n\n")
        default:
            // mixed: everything once.
            return [
                p(2), SyntheticText.quote(&rng, lines: 2), SyntheticText.bullets(&rng, count: 4),
                SyntheticText.codeBlock(&rng, lines: 26), SyntheticText.tableRows(&rng, rows: 3), p(2),
            ].joined(separator: "\n\n")
        }
    }

    private static func toolCall(turn: Int, k: Int, _ rng: inout SplitMix64) -> [String: Any] {
        let callId = "call-\(turn)-\(k)"
        let file = "Sources/App/File\(turn)x\(k).swift"
        let detail: [String: Any]
        let name: String
        switch (turn + k) % 5 {
        case 0:
            name = "Bash"
            var out: [String] = []
            for line in 0..<(4 + rng.int(8)) { out.append("line \(line): " + SyntheticText.sentence(&rng, words: 5)) }
            detail = [
                "type": "shell", "command": "swift test --filter Suite\(k)", "cwd": "/work/repo",
                "output": out.joined(separator: "\n"), "exitCode": 0,
            ]
        case 1:
            name = "Read"
            detail = ["type": "read", "filePath": file, "content": "let value\(k) = \(rng.int(100))\nprint(value\(k))"]
        case 2:
            name = "Edit"
            detail = [
                "type": "edit", "filePath": file, "oldString": "let a = 1", "newString": "let a = 2",
                "unifiedDiff": "@@ -1,2 +1,2 @@\n-let a = 1\n+let a = 2\n print(a)",
            ]
        case 3:
            name = "Grep"
            detail = [
                "type": "search", "query": "needle\(k)", "toolName": "grep",
                "content": "\(file):3: needle\(k)\n\(file):9: needle\(k)", "filePaths": [file],
                "numFiles": 1, "numMatches": 2,
            ]
        default:
            name = "Write"
            detail = ["type": "write", "filePath": file, "content": "struct Made\(k) {}\n"]
        }
        return [
            "type": "tool_call", "callId": callId, "name": name, "status": "completed",
            "error": NSNull(), "detail": detail,
        ]
    }
}
