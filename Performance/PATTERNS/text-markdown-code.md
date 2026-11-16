# Text, markdown, code

Rules: PF-8, PF-9, PF-11, PF-21, PF-26. MUST: M16, M17, M18, M20. Checks: C47, F15. Core: `RichContentDetector`, `StreamingIdentityTests`.

## 1. Settled pieces draw once (`d20e8c3`, `6a5d058`; markdown bodies per update 11 to 25 -> 1)
```swift
public struct ClaudeMarkdownView: View, Equatable {
    nonisolated public static func == (lhs: ClaudeMarkdownView, rhs: ClaudeMarkdownView) -> Bool {
        lhs.isStreaming == rhs.isStreaming && lhs.theme == rhs.theme
            && lhs.document.source == rhs.document.source && lhs.document.blocks == rhs.document.blocks
    }
}   // applied as ClaudeMarkdownView(...).equatable(); the closures are stable objects' methods, not part of ==
```

## 2. Split the message once per update (`1358201`)
```swift
private final class PieceMemo { var source: String?; var home: String?; var refs: [PieceRef] = [] }
@State private var memo = PieceMemo()
private func pieceRefs(_ source: String) -> [PieceRef] {
    if memo.source == source, memo.home == home { return memo.refs }
    ...
}
```
The reveal writes four `@State` values per delta, so the body runs three times: three splits per delta -> 1.

## 3. Scans are O(n) (`6e324e1`; 179 of 949 samples at long-chat open)
BAD: `let rest = text[i...]; if rest.count >= 7, rest.prefix(7).lowercased() == "http://"`: `count` on a suffix is O(n), the loop O(n^2).
GOOD: only an `h` can open the scheme, and the full check walks at most 8 characters (`httpSchemeLength`). Derived indexes are lazy: `ConversationStore.mediaIndex`
is built when the media sheet asks (`510c546`), not in `updateTurns` on main.

## 4. Warm off main, then read the same cache (`9f14d48`, `75e289d`)
`ProseWarmup.startForOpen` splits, parses and highlights the newest 16 turns in `Task.detached`, filling the thread-safe caches under the keys the views use;
a miss still computes synchronously. `CodeHighlightMirror` lets a code block draw a finished highlight on its first pass (one layout, not plain then highlighted).

## 5. One SwiftUI `Text`, not a text view per paragraph (`81b1fb2`, pass 8.1)
Inline-code paragraphs are one `Text` with the `InlineCodeRenderer` pill; the `UITextView`+TextKit 1 stack per paragraph is gone. Long-chat open stayed 0.8 to 1.1 s: the text engine
was not the dominant cost. Do not swap a text engine "for speed" without a sampled run.

Floor: the first ~50 markdown bodies cost ~560 ms (cold SwiftUI type reflection). It is not a bug; see [DECISIONS.md](../DECISIONS.md) F2.

If you remember nothing else:
- Pieces are Equatable by layout inputs; only the tail piece is "streaming"; split and parse once per update (memo).
- Never call `count` on a suffix in a scan loop; build derived indexes when asked for.
- Anything that can exceed 4 ms (parse, highlight, scan) is warmed off main into a bounded, thread-safe cache.
