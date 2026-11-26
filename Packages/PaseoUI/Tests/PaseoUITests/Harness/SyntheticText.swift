import Foundation

/// Deterministic prose and markdown blocks. No URLs, no images, nothing that needs a network.
enum SyntheticText {
    private static let words = [
        "the", "transcript", "layout", "offset", "cell", "measure", "estimate", "height", "reader",
        "scroll", "history", "turn", "answer", "bubble", "spacing", "content", "frame", "settle",
        "invalidate", "compensate", "hosting", "view", "pass", "update", "stable", "visible", "older",
        "newer", "reply", "message", "block", "table", "row", "column", "width", "gap", "above",
        "below", "line", "wrap", "pixel", "render", "queue", "state", "value", "result", "sample",
        "**bold claim**", "`inline_code`", "*emphasis*", "and", "with", "when", "because", "while",
        "so", "then", "but", "from", "into", "after", "before",
    ]

    static func sentence(_ rng: inout SplitMix64, words count: Int) -> String {
        var parts: [String] = []
        for _ in 0..<count { parts.append(words[rng.int(words.count)]) }
        let joined = parts.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + "."
    }

    static func paragraph(_ rng: inout SplitMix64, sentences: Int) -> String {
        var out: [String] = []
        for _ in 0..<sentences { out.append(sentence(&rng, words: 8 + rng.int(14))) }
        return out.joined(separator: " ")
    }

    static func paragraphs(_ rng: inout SplitMix64, count: Int, sentences: ClosedRange<Int>) -> String {
        var out: [String] = []
        for _ in 0..<count {
            out.append(paragraph(&rng, sentences: sentences.lowerBound + rng.int(sentences.count)))
        }
        return out.joined(separator: "\n\n")
    }

    static func codeBlock(_ rng: inout SplitMix64, lines: Int) -> String {
        var out = ["```swift", "struct Sample\(rng.int(90)) {"]
        for k in 0..<max(lines - 3, 1) {
            out.append("    func step\(k)(_ value: Int) -> Int { value &+ \(rng.int(500)) }")
        }
        out.append("}")
        out.append("```")
        return out.joined(separator: "\n")
    }

    static func tableRows(_ rng: inout SplitMix64, rows: Int, indent: String = "") -> String {
        var out = [
            "\(indent)| Name | Role | Cost |",
            "\(indent)|------|------|------|",
        ]
        let roles = ["parser", "layout", "render", "cache", "queue"]
        for k in 0..<rows {
            out.append("\(indent)| item\(k) | \(roles[rng.int(roles.count)]) | \(rng.int(900)) |")
        }
        return out.joined(separator: "\n")
    }

    static func bullets(_ rng: inout SplitMix64, count: Int) -> String {
        var out: [String] = []
        for _ in 0..<count { out.append("- " + sentence(&rng, words: 5 + rng.int(12))) }
        return out.joined(separator: "\n")
    }

    static func quote(_ rng: inout SplitMix64, lines: Int) -> String {
        var out: [String] = []
        for _ in 0..<lines { out.append("> " + sentence(&rng, words: 8 + rng.int(10))) }
        return out.joined(separator: "\n")
    }

    static let mermaid = [
        "```mermaid",
        "graph TD",
        "  A[Start] --> B{Check}",
        "  B -->|yes| C[Done]",
        "  B -->|no| D[Retry]",
        "  D --> B",
        "```",
    ].joined(separator: "\n")
}
