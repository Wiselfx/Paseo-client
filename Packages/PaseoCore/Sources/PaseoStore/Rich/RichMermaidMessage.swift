import Foundation

// V2.4 — a mermaid failure must say something a reader can act on. WebKit reports every
// JavaScript throw as the same sentence ("A JavaScript exception occurred"), so the host
// document catches the render rejection itself and returns mermaid's own text. This is the
// one-line reduction the card shows.

/// The renderer's message, reduced to the single line the diagram card can show.
public enum RichMermaidMessage {
    /// The first non-empty line, trimmed and capped. Nil when the renderer said nothing
    /// useful (the card then falls back to its own failure line).
    public static func oneLine(_ raw: String, limit: Int = 240) -> String? {
        let line = raw
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard var text = line, !text.isEmpty else { return nil }
        if text.count > limit {
            text = String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return text.isEmpty ? nil : text
    }
}
