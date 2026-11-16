# Identity and streaming

Rules: PF-3, PF-5, PF-9. MUST: M08, M09, M20. Checks: C01, H01, F17. Core test: `StreamingIdentityTests`.
`.id(x)` makes `x` part of the view's identity: when `x` changes SwiftUI destroys the subtree and builds a new one.

## 1. A streaming row's `seqEnd` as content id (`298cb66`; 113 hitches/766 ms worst -> 33/110 ms; 145 creates/s)
BAD (ChatTurns.swift): `ClaudeProse(markdown: message.text, ...).id("row:\(finalProse.seqEnd)")`: `seqEnd` moves per delta, every markdown piece, text view and code block rebuilt per token.
GOOD: the id lives on an overlay of the row's own size; content identity stays `seq:<seqStart>`.
```swift
func rowAnchor(_ seqEnd: Int) -> some View {
    overlay { Color.clear.allowsHitTesting(false).accessibilityHidden(true).id("row:\(seqEnd)") }
}
```
`scrollTo("row:<seq>", anchor: .center)` still works; groups use `.id("group:\(group.rows.first?.seqStart ?? 0)")`.

## 2. One changing fact fed to every piece (`1358201`; 40 views re-evaluated at completion -> the tail only)
BAD: `isStreaming: isStreaming` on every markdown piece, so the turn ending flips all of them.
GOOD (ClaudeRevealProse.swift): `isStreaming: isStreaming && ref.isTailMarkdown`, and memoise the split (`PieceMemo`: three splits per delta -> 1).

## 3. One slot for both states (`628fc0c`; completion stall 345 -> 138 ms)
BAD: streaming prose inside the work stack, moved after the header at completion: a different place in the tree, every piece rebuilt exactly when the user looks.
GOOD: `answerProse` is one slot (`if let answerProse ... .rowAnchor(answerProse.seqEnd)`) for the running and the finished answer.

## 4. Pin it with a Core test (`StreamingIdentityTests`)
Replay a recorded stream; assert every row keeps `seqStart` and every segment keeps its `id` while `seqEnd` moves
(and assert `seqEnd` did move, or the test proves nothing). Template: [tests](../TEMPLATES/tests.swift.md).

Ids you may use: entity ids (`agentId`, `workspaceId`, `row.id`), `seqStart`, constants. Never: `seqEnd`, `.count`, `.text`, `UUID()`, `Date()`, an array offset of a list that grows.

If you remember nothing else:
- Content identity never follows a value that changes while text streams; anchors are overlays (`rowAnchor`).
- Each piece gets only the facts true for it, and an item stays in one place in the tree across its states.
- Pin identity stability with a replay test in Core.
