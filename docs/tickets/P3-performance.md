# P3: performance and under-the-hood pass

Worker: DeepSeek (fresh). Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/UX-SPEC.md` §0.4 and §1 first.

## The problem (user, on device)
The app stutters and lags where a React Native app doesn't. Worst: the swipe that opens the left
sidebar and the right workspace panel (`Chat/EdgeDrawer.swift`, `Chat/PaseoShellView.swift`). But not only
there: find the rest (transcript scrolling while streaming, opening a long chat, typing in the composer,
sidebar list, workspace panel tabs, sheets).

## How to work
There is no Instruments here, so this is a code-level investigation that must hold up to proof.
1. **Investigate first.** Write `/tmp/reviews/perf-audit.md`: each suspected hot path with file:line, *why*
   it costs (what invalidates, how often, how much work per invalidation), and the fix. Rank by user impact.
2. **Then fix**, highest impact first, one commit per fix with a message saying what it removes.
3. Behaviour and look must not change (same animation curves, same gestures, same layout), except where a
   fix requires it; say so then.

## Things to check (not a script; find more)
- **Per-frame state writes during a drag.** If the drawer progress lives in `@State` high in the shell, every
  finger move re-evaluates the shell's `body` and everything under it (sidebar + chat + panel). Fix shape: keep
  per-frame values in the smallest possible view, or apply them via `.offset`/`.visualEffect`/
  `GeometryEffect` so children are not re-evaluated; make the heavy children `Equatable`/stable so SwiftUI
  skips them; no layout changes per frame (offset, not frame/padding).
- `@GestureState` vs `@State` for drag values; `.simultaneousGesture` on a large tree making the scroll view
  and drag fight.
- **Scroll-driven writes:** `onScrollGeometryChange` actions in `Conversation/ChatTranscript.swift` write
  state and call into stores (`reportReadingPosition`, `revealTurnRail`, history anchor) on every scroll
  frame. Only write when a value actually changes; throttle what can be throttled.
- `@Observable` reads that are too broad (a view reading a whole store re-renders on any change to it);
  computed properties doing O(n) work in `body` (e.g. `outlineItems`, `store.turns.filter`, `TurnBuilder`
  runs) on every render, `Array(x.enumerated())` in hot `ForEach`, unstable ids.
- Markdown parsed again on every render / every streamed token for the whole message (`ClaudeProse`,
  `ClaudeMarkdownView`); highlight/attributed-string building on the main thread; caching by content.
- `AnyView`, `.id()` that resets subtrees, `GeometryReader` churn, `.drawingGroup` misuse, materials/blur
  and shadows stacked inside scrolling content, `matchedGeometryEffect` leftovers.
- Main-thread work: JSON decode of big timeline pages, file reads, image decoding, `DateFormatter`/
  `NumberFormatter` created per render.
- Timers/tasks that tick while nothing changes (mascot, status line, relative timestamps).

## Off-limits (another worker owns them right now)
`Conversation/ChatComposer.swift`, `Conversation/DraftChatView.swift`, `Chat/ClaudeStyle.swift`, the
Markdown theme *sizes* in `Chat/ClaudeChatComponents.swift` (performance changes elsewhere in that file are
fine). If a hot path is in one of those, write it up in the audit instead.

## Compile gate
Push your branch (never `main`/`foundation`): `git push -q origin p3-performance`, then
`ssh -i ~/.ssh/paseo_build_ed25519 -o BatchMode=yes claude@host.orb.internal build p3-performance`.
Loop until `** BUILD SUCCEEDED **` with no new warnings. It accepts nothing else.

## Done
PaseoCore clean build + all tests green, Mac gate green, audit file written, commits on `p3-performance`.
Final message: the ranked list, what you fixed, what you left and why.
