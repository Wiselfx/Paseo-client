# Overall performance audit — Paseo iOS client (iPhone)

Read-only. No daemon contact, no code changes, no commits. Linux VM: no Instruments, no Xcode.
Everything below is a code claim you can check at the cited line, or an explicitly labelled guess.
Where a number is quoted it comes from the P3 microbenchmark file (`/tmp/reviews/perf-audit.md`) or is
marked as a guess. Nothing here is a measurement I made on a device.

Upstream history note: `/home/paseo/dev/paseo-reference` is a shallow checkout (`git log` = 1 commit),
but the full history is reachable with `--all` (6,426 commits). `git log -i --grep=perf -- packages/app`
and repo-wide with `--all` produced the list in §3.

---

## 1. Ranked findings (one list, by expected user-visible impact)

Legend: **S/M/L** = effort. Confidence: high = I read the code and the cost follows; medium = code is
clear but the per-frame magnitude is a guess; low = speculation.

### 1. Every streamed token is decoded, merged and published on the main actor with no coalescing or backpressure
**Impact: highest. This is the streaming jank and a chunk of the idle jank.**
- `PaseoKit/DaemonConnection.swift:76,81` — both `AsyncStream`s are `.unbounded`.
- `PaseoStore/HostSession.swift:119-124` — `eventTask = Task { for await event in client.events { await self.handle(event:) } }`.
  `HostSession` is `@MainActor`, so the task inherits the main actor.
- `HostSession.swift:288-308` — `handle(event:)`; `.agentStream` → `conversations[id]` → `store.handleStream(payload)`.
- `HostSession.swift:737-760` — `handleStream`; `.timeline` → `timeline.applyStream` + `updateTurns()`.
- `HostSession.swift:869-874` — `updateTurns()` → `turnBuilder.turns(...)` + `promptOutline.timelineChanged`.
- `TimelineState.swift:110-135` — `applyStream` mutates `rows`; `appendText` (`:177`) / `appendRow` (`:194`).

Why it costs: the daemon coalesces one `agent_stream` per ~60 ms, but the client commits each delta to
`@Observable` state on the main actor and re-evaluates `ClaudeChatView.body` (header, transcript ForEach,
composer) every time. `.unbounded` means a slow main thread buffers events without limit: memory growth,
then a catch-up burst. Upstream `e22ad117f` ("Stream assistant text at a steady rate instead of in arrival
lumps") added a leading+trailing coalescer (first delta flushes immediately, 60 ms window) and commits the
reducer queue on a frame; `8dd4da6ee` ("Keep mobile streaming and panel motion stable under JS stalls")
notes the same class of stall.
**Fix:** a per-agent coalescing queue in `HostSession` that merges consecutive `.timeline` deltas and
commits once per display frame (leading flush, trailing timer as a ceiling). Change both streams to
`.bufferingNewest(64)` or add real backpressure. **M**. Confidence: high on the structure, medium on the ms.

### 2. Per token, the whole visible message is re-parsed three ways (Markdown, rich detection, file-link linkify)
**Impact: highest while a turn is running; the single biggest per-token main-thread cost.**
- `Conversation/ChatTurns.swift:225` and `:355` — `FilePathLinks.linkifiedForProse(message.text)` in `body`.
- `Chat/ClaudeRevealProse.swift:80-95,100-110` — `pieceRefs(markdown)` → `richPieces(source)`.
- `MarkdownDocumentModel.swift:24-40` — `.cached(trimmed)` memo keyed on the **full source**.
- `Rich/ClaudeRichSplice.swift:17-30` — `RichContentCache.detect` keyed on the **full source**.
- `Conversation/FilePathLinks.swift:61-85` — `linkified` (4 regex passes) and `:95-115` — `protectedRanges`
  compiles **three `NSRegularExpression`s per call**.

Why it costs: while streaming, `message.text` is a new string per token, so every cache misses and the
entire growing message is re-parsed: CommonMark parse (~0.38 ms / 8 k chars), rich-content detection
(multiple line passes), and 4 regex linkify passes (~0.70 ms / 8 k). That is ~1–2 ms per token on the
main thread, per visible message, before any layout. `protectedRanges` adds ~15 µs/token of regex
compilation. Upstream `f35b0b8b7` ("Split streaming markdown into memoized blocks for mobile perf") splits
at paragraph boundaries so only the last block re-parses.
**Fix:** (a) make the three `protectedRanges` regexes `static let` like `pathRegex` (**S**); (b) split prose
into paragraph/block pieces and memoize each piece (upstream's shape), or key the caches by
`(prefix source, tail)` so only the new tail is parsed (**L**). Confidence: high on the code, medium on the ms.

### 3. The sidebar mounts every row and re-derives O(workspaces × agents) with date parsing on every store change
**Impact: high — sidebar scroll/update cost, and a stall if an agent update lands mid-drag.**
- `Sidebar/PaseoSidebar.swift:79-84` — `ScrollView { VStack { navigation; directory } }` (non-lazy).
- `Sidebar/SidebarRoll.swift:15-23` — `content().background { GeometryReader … }` builds the content **even when
  collapsed** (it is measured to get the height, then the frame is set to 0).
- `Sidebar/SidebarDirectory.swift:228-252` — `sortedWorkspaces` → `activityDate(for:)` per workspace.
- `SidebarDirectory.swift:406-420` — `activityDate` scans **all `session.agents`** and parses up to 5 ISO dates.
- `SidebarDirectory.swift:376-404` (`sortedGroups`), `:275-330` (`dateBuckets`) — same scan per group/bucket.
- `Sidebar/SidebarWorkspaceRow.swift:78` — `agents(in:)` filters the whole agent array **per row**.
- `SidebarWorkspaceRow.swift:117-175` — `metaRow` calls `activityDate(for:)` up to **three times per row**
  (dot, age, separator logic).

Why it costs: building the sidebar is O(W×A) with up to 5 `PaseoDate.parse` calls per workspace per pass,
and it runs on every `session.agents` / `workspaceDirectory` change. `SidebarRoll` builds every workspace row
of a collapsed project, so a 200-workspace project mounts 200 rows. During a drag, any `agent_update`
re-evaluates `PaseoSidebar.body` mid-gesture. Upstream `a743a2249` ("Keep large sidebars responsive") and
`9603397ae` ("limit initial sidebar workspace rendering") are the same fix.
**Fix:** build `[workspaceId: [AgentSnapshot]]` and a per-workspace activity date once per body evaluation
(or derive them in the store) and pass them down; make the directory a `LazyVStack`; make `SidebarRoll`
skip building content when collapsed (cache the measured height). **M**. Confidence: high.

### 4. Diff views mount every line in a non-lazy VStack, and rebuild the diff model in `body`
**Impact: high when opening/reviewing a large diff; freezes the UI for large changes.**
- `Workspace/WorkspaceChangesDiffView.swift:47-49` — `private var model: DiffModel { DiffModel(file:…) }` and
  `sideModel` are computed properties; `DiffModel.init` (`:798-860`) flattens every hunk and measures the
  longest line.
- `WorkspaceChangesDiffView.swift:300-310` — `visibleRows` filters **all** rows.
- `WorkspaceChangesDiffView.swift:470-480` — `unifiedScroll`: `ScrollView(scrollAxes) { VStack { ForEach(visibleRows) } }`
  (non-lazy).
- `WorkspaceChangesDiffView.swift:632-665` — `lineRow` is a `Button` with 4 `Text`s and `.textSelection`.
- `Chat/ClaudeToolDetail.swift:120-160` — `ClaudeDiffView`: `ScrollView { VStack { ForEach(lines) } }` (non-lazy,
  capped at 300 pt) and `ClaudeDiffLine.parse` (`:90-110`) runs in `body`.

Why it costs: a 5,000-line diff creates 5,000 buttons/rows, all laid out on the main thread. `DiffModel` is
rebuilt on every body evaluation (including each `visibleRows` change). Upstream `b599d38a7` ("Make large
diffs open quickly and scroll as one surface"), `3998ea11d` ("Keep large diffs responsive") and `50623965b`
("Make line wrapping responsive in large diffs") all virtualize/bound this work.
**Fix:** `LazyVStack` with estimated row heights; memoize `DiffModel`/`SideBySideModel` per
`(file, hideWhitespace)`; collapse hunks by default; consider a `Canvas`/TextKit renderer for the line
gutter. **M/L**. Confidence: high.

### 5. The workspace panel is always mounted and keeps live subscriptions/work running while closed
**Impact: high — background work and memory that never stops, plus off-screen re-renders during drags.**
- `Chat/PaseoShellView.swift:193-220` — `panelSurface` is always in the `ZStack`; `WorkspacePanel` is always
  in the tree.
- `Workspace/WorkspacePanel.swift:123-140` — `.task(id: workspace?.id)` loads `checkout`, `gitExtras`,
  starts setup observation **at shell creation**, even if the panel is never opened.
- `WorkspacePanel.swift:372-400` — `content` keeps the current page mounted; switching tabs unmounts, but
  closing the panel does not.
- `Workspace/WorkspaceTerminalsView.swift:67-70` — `.task` calls `store.open(workspaceId:cwd:)`, which
  subscribes the directory and attaches SwiftTerm; it stays attached while the panel is closed.
- `Workspace/WorkspaceChangesView.swift:115-125` — `.task` loads status, diff, commits, PR timeline; the
  `CheckoutStore` diff subscription (`CheckoutStore.swift:155-175`) keeps publishing.
- `TerminalsStore.swift:120-145` — `open` subscribes and refreshes terminals/scripts.

Why it costs: terminal output and diff updates re-render an off-screen page (and its `AnyView`/Text trees)
while the drawer moves; the checkout/diff load at launch is wasted work. Upstream `bd748b6ed` ("gate side
effects on stack route focus"), `78a3083fe` ("avoid stream updates in hidden chats"), `044546ae0` ("skip PR
queries when sidebar is closed") are exactly this.
**Fix:** gate the panel `.task` and page work on `progress > 0` (or an `isPanelVisible` environment value);
unmount the page content when closed while keeping the remembered tab id; detach terminals and release the
diff subscription when closed. **M**. Confidence: high.

### 6. One WKWebView per `visualize` / SVG rich block
**Impact: high memory and process count; medium CPU.**
- `Rich/ClaudeRichBlocks.swift:643-730` — `RichWebCard` → `SandboxedHTMLView`.
- `Rich/SandboxedHTMLView.swift:36-80` — `makeUIView` creates a `WKWebView`; `RichHTMLDocument` installs a
  `MutationObserver` height reporter.
- `RichHTMLDocument.swift:1-40` — `heightReporter` posts on every DOM mutation.

Why it costs: each block gets its own `WKWebView` (separate web process, tens of MB). A conversation with
several visualizations/SVGs carries several web processes; the JS observer posts height changes that write
`@State contentHeight` and re-render. This is a well-known SwiftUI anti-pattern.
**Fix:** render SVG natively (no new dependency: parse the simple subset or draw via `CoreGraphics`), or use
one shared off-screen `WKWebView` and reparent it, or snapshot the rendered page once and show the image.
Gate on visibility. **L**. Confidence: high on the cost, medium on the best fix.

### 7. The shell body depends on `session.agents` and `workspaceDirectory`, so every update rebuilds all three surfaces
**Impact: medium-high — amplifies every store change into a shell rebuild.**
- `Chat/PaseoShellView.swift:78-84` — `body` → `GeometryReader` → `shell(width:height:)`.
- `PaseoShellView.swift:133-146` — `shell` reads `selectedWorkspace` (`session.workspaceDirectory`).
- `PaseoShellView.swift:153-160` — `sidebarSurface` (builds `PaseoSidebar`).
- `PaseoShellView.swift:104-112` — `.onChange(of: session.agents)` / `.onChange(of: session.workspaceDirectory.hasLoaded)`
  are evaluated while building `body`, so they are dependencies.

Why it costs: any `agent_update` or workspace update re-evaluates `PaseoShellView.body` and rebuilds the
sidebar/chat/panel view values. The heavy children are structs (their bodies are skipped), but `PaseoSidebar.body`
re-runs (finding #3) and the whole `shell` tree is diffed. Upstream `21d43bc24` ("eliminate cascading
rerenders with granular Zustand selectors") and `559c0200e` ("Reuse workspace and subagent lists while
replies stream") are the React equivalent.
**Fix:** move the agent/workspace observations into small modifier views that do not invalidate the shell
body; pass the selected agent/workspace as value inputs. **M**. Confidence: medium-high.

### 8. `IncrementalTurnBuilder` memcmps the whole rows array and copies the turns prefix per token
**Impact: medium — scales with chat length.**
- `PaseoStore/IncrementalTurnBuilder.swift:91-115` — `firstChangedRow` memcmps every row's bytes.
- `IncrementalTurnBuilder.swift:58` — `Array(turns[0..<reusedCount])` allocates a new turns array per update.
- `HostSession.swift:877-884` — `latestPromptSeq` scans `timeline.rows` backwards to the last user message.

Why it costs: per token, O(total row bytes) memcmp + O(turns) array copy + O(rows) backward scan. For a
2,000-row chat this is tens of µs and a lot of allocations per token, on top of finding #1.
**Fix:** track the last row's identity/version instead of memcmp; keep a cached `latestPromptSeq` updated on
append. **M**. Confidence: medium.

### 9. No backpressure on the event streams; conversation/checkout stores are never closed
**Impact: medium — memory growth over a long session.**
- `DaemonConnection.swift:76,81` — `.unbounded`.
- `HostSession.swift:167-180` — `closeCheckout` / `closeConversation` exist but are **only called by tests
  and `paseo-probe`** (verified by grep).
- `HostSession.swift:140-160` — `conversations` / `checkouts` dictionaries grow for the connection's life.

Why it costs: unbounded buffers grow when the main thread lags; every opened conversation keeps its
`TimelineState`, `turns`, `PromptOutline`, subagents, background work and uploader forever, and every
checkout keeps a diff subscription. Upstream `fd22784e2`/`33cf6cf33` ("defer replica persistence until user
inactivity") and `d4435bd01` ("retain recently used workspaces longer", with an LRU cap) show the same
lifecycle discipline.
**Fix:** `.bufferingNewest(n)` on both streams; call `closeConversation`/`closeCheckout` when the UI no
longer shows them, or cap with an LRU. **S/M**. Confidence: high.

### 10. `ClaudeCodeHighlighter` is main-actor JavaScriptCore; large code blocks highlight on the main thread
**Impact: medium — a visible stall the first time a big code block is shown.**
- `ClaudeCodeHighlighter.swift:8` — `@MainActor public final class ClaudeCodeHighlighter`.
- `ClaudeCodeHighlighter.swift:20-45` — `highlight` runs highlight.js, cache key = theme+language+**full source**.
- `ClaudeMarkdownView.swift:246-250` — `defaultHighlightedCode` called from `codeText`, i.e. from `body`.

Why it costs: the first render of a large code block (up to 100 k UTF-16 chars) runs a JS engine on the main
thread. A 50 KB block is plausibly tens of ms (guess). The cache key hashes the whole source.
**Fix:** move highlighting off the main actor (dedicated global actor / `Task.detached`), cache with a cheap
key, highlight only the mounted block. **M**. Confidence: medium-high.

### 11. The mascot crab runs a `TimelineView(.animation)` at display rate forever; running dots animate continuously
**Impact: medium — constant GPU/CPU load that competes with drags and scrolls.**
- `Mascot/ClaudeCrabView.swift:196-200` — `TimelineView(.animation)` whenever `mascotEnabled` and not reduce
  motion; it plays even when the state is `.sleeping` (32 frames).
- `Sidebar/PaseoStatusDot.swift:18-22` — `.repeatForever` opacity animation for every running workspace/terminal.
- `Chat/ClaudeStatusLine.swift:149,188` — 4 Hz `Timer.publish` writing `@State now`.
- `ClaudeStatusLine.swift:231-240` and `Conversation/ChatWorkGroup.swift:139-145` — `TimelineView(.animation)`
  drawing a **masked** copy of the text (`mask` forces an offscreen pass) at display rate while a turn runs.

Why it costs: continuous animations keep the compositor and the main thread busy even when the user is
idle; masked text is an offscreen render pass. During a drawer drag or a transcript scroll these compete
for the same frames. The P3 audit already fixed the idle mascot ticker and the 30/60 Hz caps; the crab and
the sweeps are the remainder.
**Fix:** drive the crab from a display-link callback only while it is visible and the mascot is not
sleeping; stop the running dots when the sidebar is not visible; replace the masked sweeps with a `Canvas`
draw or a lower rate; drop the 4 Hz timer and ride the same TimelineView. **S/M**. Confidence: medium.

### 12. `ClaudeMarkdownView.render` returns `AnyView` for every block; `ForEach` ids are offsets
**Impact: medium — defeats SwiftUI diffing inside every prose block.**
- `ClaudeMarkdownView.swift:137-235` — `private func render(_:) -> AnyView` (type erasure per block).
- `ClaudeMarkdownView.swift:120` — `ForEach(Array(blocks.enumerated()), id: \.offset)`.
- Also `:180` (list items `id: \.offset`), `:195` (table rows `id: \.self`).

Why it costs: `AnyView` hides the block type from the diff engine, so every prose re-render rebuilds the
whole block subtree. Offset ids are unstable when a block is inserted/removed.
**Fix:** replace `AnyView` with a `@ViewBuilder` switch returning `some View`; use stable block identities
(e.g. the block's source range or a hash). **M**. Confidence: medium-high.

### 13. `localImageLoader` closure identity changes on every chat body evaluation
**Impact: medium — re-runs `ClaudeProse`/`ClaudeRevealProse` bodies per token.**
- `Conversation/ChatComposer.swift:608-625` — `var localImageLoader` creates a new closure each evaluation.
- `Conversation/ChatTurns.swift:16,179,225,341,355` — passed into `ClaudeProse`.

Why it costs: a new closure changes `ClaudeProse`'s input, so its body re-runs, and `ClaudeRevealProse.body`
re-runs `pieceRefs(markdown)` for every visible message on every token.
**Fix:** build the loader once per `(session, workspaceId)` (a `let` on the chat view, or a cached closure).
**S**. Confidence: medium.

### 14. Up to five simultaneous `DragGesture`s over the transcript/panel; direction decided only after the first event
**Impact: medium — gesture arbitration and per-event cost on every touch.**
- `Chat/EdgeDrawer.swift:47-60` — `content.simultaneousGesture(gesture)`.
- `EdgeDrawer.swift:62-105` — `onChanged` writes `@State progress` every event; `directionDecided` guard.
- `Chat/PaseoShellView.swift:178-189` — two `edgeDrawerDrag`s on the conversation surface.
- `PaseoShellView.swift:217-222` — one on the panel card.
- `Workspace/WorkspacePanel.swift:246-256` — `withPanelDismiss` adds one to the header and to the agents/files
  pages.

Why it costs: every touch on the transcript is offered to 2–5 `DragGesture`s plus the scroll view's pan;
SwiftUI must arbitrate. Each armed drawer writes `@State progress`, invalidating `ConversationCard` and
`PanelCard`. A vertical scroll still pays the first-event cost of each drawer gesture.
**Fix:** attach one drawer gesture per surface with a computed edge; use `.highPriorityGesture` for the edge
zones and `.simultaneousGesture` only on an open surface; don't attach the second drawer gesture when the
panel is closed. **M**. Confidence: medium.

### 15. `ClaudeMergedFileCall.diffStat` re-parses the unified diff on every body evaluation
**Impact: low-medium — repeated work on every token while the active turn runs.**
- `Chat/ClaudeFileCalls.swift:108-140` — `diffStat` splits the diff string and counts lines per call.
- `Chat/ClaudeFileCalls.swift:200-215` — `WorkRow.merging` re-walks the group's rows.
- `Conversation/ChatWorkGroup.swift:50-65` (`seatGlyph`), `:186-230` (`summaryText`) — O(rows) per evaluation.

Why it costs: the active work-group card re-renders per token; `diffStat` re-parses the same diff string.
**Fix:** compute `diffStat` once when the call is appended (store it on `ClaudeMergedFileCall`); memoize
`summaryText`/`seatGlyph` per group. **S**. Confidence: medium.

### 16. `ClaudeHistoryView` recomputes groups/dates per evaluation; `relativeAge` builds a `DateFormatter` per row
**Impact: low-medium — history sheet scrolling.**
- `Chat/ClaudeHistoryView.swift:44-75` — `agents` / `groups` computed in `body`; every agent's date is parsed.
- `ClaudeHistoryView.swift:471-485` — `relativeAge` creates a `DateFormatter` per row.

**Fix:** precompute group keys once per `agentLifecycle.entries` change; cache a `DateFormatter`. **S**.
Confidence: high.

### 17. `CommandCenterView.sections` recomputes all groups per keystroke; sorts with `activityDate` in the comparator
**Impact: low-medium — search latency.**
- `Sidebar/CommandCenterView.swift:252-270` — `sections` rebuilds every group.
- `CommandCenterView.swift:320-335` — `workspaceRows` sort comparator calls `activityDate` (parses dates).
- `CommandCenterView.swift:336-350,440` — `projectRows` same.
- `CommandCenterView.swift:527` — `activityDate`.

**Fix:** decorate-sort-undecorate; debounce the query; memoize the result. **S/M**. Confidence: high.

### 18. Transcript scroll readout is O(turns) per frame and recreates a `Task` per frame
**Impact: low-medium — long-transcript scrolling (the reported "not perfect").**
- `Conversation/ChatTranscript.swift:245-266` — `onScrollGeometryChange` → `reportReadingPosition()`,
  `revealTurnRail()`, `loadOlderIfNeeded()`.
- `ChatTranscript.swift:671-677` — `reportReadingPosition` scans `store.turns` for the first visible turn.
- `ChatTranscript.swift:678-690` — `revealTurnRail` cancels and creates a `Task` per frame.
- `ChatTranscript.swift:650-660` — `outlineItems` O(turns)/O(prompts) per evaluation.

**Fix:** only recompute when the top visible row changes (track it in `TranscriptScrollTrack`), throttle
`revealTurnRail` to one task handle, cache `outlineItems`. **S**. Confidence: medium (P3 left this; the cost
is single-digit µs per frame plus allocations).

### 19. `SidebarRoll` and the work-group card measure themselves through `GeometryReader` preferences
**Impact: low-medium — extra layout passes, per token for the work-group card.**
- `Sidebar/SidebarRoll.swift:15-23` — `GeometryReader` background + `onPreferenceChange` → `contentHeight`.
- `Conversation/ChatWorkGroup.swift:161-172` — same pattern, and the frame height feeds back into layout.

**Fix:** use `onGeometryChange` (iOS 18+) or a fixed estimate; break the feedback loop. **S**. Confidence: medium.

### 20. Rich cards: `LPLinkView` + `LPMetadataProvider` network fetches; local images decode on the main thread
**Impact: low-medium — memory and main-thread decode.**
- `Rich/ClaudeRichBlocks.swift:184-260` — `RichLinkCard` (`LPLinkView`, `LPMetadataProvider`).
- `ClaudeRichBlocks.swift:386-470` — `RichRemoteImage` (`AsyncImage`).
- `ClaudeRichBlocks.swift:475-560` — `RichLocalImage` → `UIImage(data:)` in `.task` on the main actor.
- `Chat/ChatComposer.swift:608-625` — the loader reads the file through the daemon and decodes in memory.

**Fix:** gate on visibility; decode/downscale off the main thread (`CGContext`/`UIGraphicsImageRenderer` in a
`Task.detached`) and cache; keep the metadata cache. **S/M**. Confidence: medium.

### 21. `FilePathLinks.protectedRanges` compiles three `NSRegularExpression`s per call
**Impact: low — per streaming token.**
- `Conversation/FilePathLinks.swift:95-115`.

**Fix:** `static let` like `pathRegex`. **S**. Confidence: high.

### 22. Markdown / rich / linkify caches evict-all at 64 entries
**Impact: low-medium — re-parsing when scrolling back, memory churn.**
- `MarkdownDocumentModel.swift:32-40`, `Rich/ClaudeRichSplice.swift:17-30`, `Conversation/FilePathLinks.swift:107-115`.

Why it costs: during streaming every token adds a key; after 64 the table is cleared, so the previous
message's parse is lost. This is a deliberate P3 trade-off, but 64 is small for a long answer.
**Fix:** an LRU with a cost bound, or a larger cap. **S**. Confidence: high.

### 23. `ChatWorkGroup` card's `ScrollView` + `frame(height: contentHeight)` + preference loop
**Impact: low — per token while the active group grows.**
- `Conversation/ChatWorkGroup.swift:161-172`.

**Fix:** measure once and clamp; or a `LazyVStack` with a fixed cap. **S**. Confidence: medium.

### 24. `ClaudeStatusLine`'s 4 Hz `Timer.publish` + masked `TimelineView(.animation)` sweep
**Impact: low — continuous small redraws while a turn runs.**
- `Chat/ClaudeStatusLine.swift:149,183-188,231-240`.

**Fix:** lower the sweep rate or draw it in a `Canvas`; drop the separate timer. **S**. Confidence: medium.

### 25. Settings / controls sheets use non-lazy `ScrollView { VStack }` pages
**Impact: low — only while those sheets are open.**
- `Chat/PaseoSettingsView.swift:228,313,352,728,873,1219,1329,1385,1421,1574,1728`.
- `Chat/ClaudeAgentControlsSheet.swift:175,220,265,330,375`; `Chat/DraftControlsSheet.swift:113,182,223,263`.

**Fix:** `LazyVStack` where the lists are long. **S**. Confidence: high (low user impact).

### 26. Continuous corners and `.textSelection(.enabled)` are used widely
**Impact: low — many small layers.**
- `Chat/ClaudeChatComponents.swift:100-115` (`RoundedRectangle(.continuous)`), `ClaudeMarkdownView.swift:155-160`,
  `Chat/ClaudeToolDetail.swift:120-160`, and others.

**Fix:** use plain `RoundedRectangle` where the continuous corner is not visible; limit `.textSelection` to
prose. **S**. Confidence: medium.

### 27. Launch: `AppModel.init` connects immediately; the panel loads checkout/diff at shell creation
**Impact: low-medium — cold-launch first paint.**
- `App/Sources/AppModel.swift:70-78` — `init` starts `connectToSaved`/`connect`.
- `Workspace/WorkspacePanel.swift:123-140` — the panel's `.task` runs at shell creation.

**Fix:** defer the panel work until first open; show the shell as soon as the session exists. **S/M**.
Confidence: high.

### 28. `ChatFind` scans all turns per query; `restoreScroll` scans turns
**Impact: low.**
- `Conversation/ChatFind.swift:60-100`, `ChatTranscript.swift:660-670`.

**Fix:** index text once per timeline. **M**. Confidence: medium.

---

## 2. Drawer-specific findings (from the original task)

The P3 fixes (progress read only in `ConversationCard`/`PanelCard`, `ShellOpenState`, memoized prose,
cached formatters) are real: `PaseoShellView.body` no longer reads `drawerProgress`/`panelProgress`, so a
finger move does not re-evaluate the sidebar/chat/panel. What is left:

1. **`ConversationCard.body` / `PanelCard.body` still re-run every frame and re-create full-screen layers.**
   `PaseoShellView.swift:567-650`. The card's `.background { EdgeDrawerCard() }` is a full-bleed
   `RoundedRectangle(.continuous).fill(...).ignoresSafeArea()`; the overlays are a full-screen
   `EdgeDrawerDim` (`Color.black.opacity`, `.contentShape(.rect)`, `.onTapGesture`) and a 0.5 pt
   `EdgeDrawerHairline` stroke. Per frame the dim's opacity changes and the hairline's stroke opacity
   changes, so both layers are re-rendered. **Fix:** keep the dim as a single `RoundedRectangle` with an
   animatable `opacity` (SwiftUI can animate the value instead of rebuilding the view), and let the
   hairline's opacity animate rather than re-creating the stroke. **S/M**. Confidence: medium.

2. **The settle animation animates `@State progress`, re-evaluating the card bodies ~120 times.**
   `PaseoShellView.swift:366-378`. That is intended, but the card's content is a stored value; only the
   offset/dim/hairline need to animate. **Fix:** if the layers above are cheap enough, leave it; otherwise
   drive the offset/dim from a `CanvasLink`-style animation that writes only the layer values. **M**.
   Confidence: medium (guess).

3. **Gesture contention (finding #14).** Up to five simultaneous `DragGesture`s over the scroll view.
   The transcript's own scroll readout (#18) adds per-frame work to a vertical drag.

4. **The moving card contains live animations that never stop:** the crab (#11), the status-line sweep
   (#11/#24), and the work-group sweep (#11). During a drawer drag these keep the GPU busy. This is a
   plausible contributor to "drawers are laggy while swiping" even when the conversation is idle.
   **Fix:** pause the crab and sweeps while a drawer is open (or reduce their rate). **S/M**. Confidence: medium (guess).

5. **An `agent_update` mid-drag re-evaluates the shell body and the sidebar** (#7/#3). The sidebar's
   O(W×A) rebuild lands in the middle of the gesture. **Fix:** same as #7. **M**. Confidence: medium.

6. **`SidebarRoll` builds collapsed rows and measures them with a `GeometryReader`** (#3): the sidebar
   under the moving card is not a cheap cached layer. **Fix:** lazy content + cached heights. **M**.
   Confidence: medium.

---

## 3. Upstream techniques that translate to SwiftUI

From `git log --all -i --grep=perf -- packages/app` (and repo-wide) in `/home/paseo/dev/paseo-reference`.
The checkout is shallow at HEAD; `--all` reaches the full history.

| commit | technique | SwiftUI translation |
| --- | --- | --- |
| `e22ad117f` | Leading+trailing coalescer; reducer commits on a frame; reveal paced by backlog, not arrival | Batch `agent_stream` deltas per frame in `HostSession`; keep the full text in the store and reveal a paced slice (finding #1) |
| `f35b0b8b7` | Split streaming markdown at paragraph boundaries; memoize each block so only the last re-parsers | Split `ClaudeRevealProse` into memoized paragraph pieces (finding #2) |
| `7557992df` | Isolate composer editing; publish draft after paint; live-text source | Keep the `DraftObserver` pattern; consider an `UITextView` bridge that publishes after paint |
| `8c4e54eac` | Keep composer typing in the frame budget; after-paint publication | Same as above; measure body-eval count per keystroke |
| `7f011d16c` | Throttle draft persistence to 200 ms checkpoints | Already have a 500 ms debounce; verify it fires off the main thread |
| `a743a2249` | Build workspace activity once; share the derived sidebar model | Precompute `[workspaceId: agents]` + activity dates once per sidebar evaluation (finding #3) |
| `9603397ae` | Limit initial sidebar workspace rendering (20 rows) | `LazyVStack` + cap initially mounted rows (finding #3) |
| `0d7a234e6` | Preserve unchanged sidebar collection/row identity | Stable `ForEach` ids; avoid rebuilding the directory array (finding #3) |
| `559c0200e` | Skip workspace/subagent list rebuilds on stream ticks | Don't let `store.turns` changes invalidate the sidebar/panel (finding #7) |
| `21d43bc24` | Granular store selectors; 15–20 rerenders/keystroke → 1–2 | Small observer modifiers; pass values, not whole stores (finding #7) |
| `78a3083fe` | Avoid stream updates in hidden chats | Gate the panel/terminal subscriptions on visibility (finding #5) |
| `bd748b6ed` | Gate side effects on stack route focus | Same (finding #5) |
| `044546ae0` | Skip PR queries when the sidebar is closed | Same (finding #5) |
| `8dd4da6ee` | Re-render only changed history rows; stable row identity; keep panel props across JS stalls | Stable `ForEach` ids (already), and keep the panel's state while closed |
| `b599d38a7` | Virtualize large diff rendering | `LazyVStack` for diffs (finding #4) |
| `3998ea11d` | Bound expensive text shaping to the viewport; canvas headers | Same (finding #4) |
| `50623965b` | Estimate off-screen heights; measure rows as they enter the window | Same (finding #4) |
| `d31179765` | Preserve identity at data producers; prepare text for the visible window | Memoize `DiffModel` (finding #4) |
| `33a52d0ae` | Compute grapheme geometry only for final wrap fragments | Applies to wrapped diff lines |
| `72b67f48e` | Coalesce terminal output before IPC; feed xterm back-to-back | Coalesce terminal byte frames in `TerminalsStore` |
| `700840da5` | Convert `ScrollView` to an inverted `FlatList` | The transcript is already a `LazyVStack`; keep it |
| `4f7813d3a` | Forward-order virtualized list; per-row size estimates; one owner of the scroll offset | The transcript's `ScrollViewReader` + `scrollPosition` is the analogue; keep one owner |
| `67eddbd6a` | Memoize animation context values | Memoize `SidebarRoll`/panel animation state |
| `d4435bd01` | Retain warm workspaces with an LRU cap; defer focus during switches | Cap `conversations`/`checkouts` (finding #9) |
| `2a0a0ff65` | Bound native workspace mount work; pace list mounting | Same (finding #5) |
| `8d424e039` | Cache timeline slices by tail identity; bound per-delta work | Same as finding #8 |

Not applicable: server-side diff generation, relay encryption, Zustand/React specifics, Reanimated.

---

## 4. Batches for separate tickets (disjoint file sets)

Each batch touches a disjoint set of files, so they can run in parallel.

- **Batch A — Streaming pipeline (PaseoCore):** `PaseoKit/DaemonConnection.swift`,
  `PaseoStore/HostSession.swift`, `PaseoStore/TimelineState.swift`,
  `PaseoStore/IncrementalTurnBuilder.swift`, `PaseoStore/PromptOutline.swift`.
  Findings #1, #8, #9. Tests: `HostSessionTests`, `TimelineStateTests`, `IncrementalTurnBuilderTests`.
- **Batch B — Prose rendering (PaseoUI + one Core file):** `Chat/ClaudeRevealProse.swift`,
  `ClaudeMarkdownView.swift`, `Conversation/FilePathLinks.swift`, `MarkdownDocumentModel.swift`,
  `Rich/ClaudeRichSplice.swift`, `PaseoStore/Rich/RichContentDetector.swift`,
  `Conversation/ChatTurns.swift`. Findings #2, #12, #13, #21, #22.
- **Batch C — Sidebar (PaseoUI):** `Sidebar/PaseoSidebar.swift`, `Sidebar/SidebarDirectory.swift`,
  `Sidebar/SidebarWorkspaceRow.swift`, `Sidebar/SidebarRoll.swift`,
  `Sidebar/SidebarProjectGroup.swift`, `Sidebar/WorkspaceLabels.swift`. Findings #3, #19.
- **Batch D — Workspace panel and pages:** `Workspace/WorkspacePanel.swift`,
  `Workspace/WorkspaceTerminalsView.swift`, `Workspace/WorkspaceChangesView.swift`,
  `Workspace/WorkspaceFilesView.swift`, `PaseoStore/CheckoutStore.swift`,
  `PaseoStore/TerminalsStore.swift`, `PaseoStore/GitExtras.swift`. Findings #5, #9.
- **Batch E — Diffs:** `Workspace/WorkspaceChangesDiffView.swift`, `Workspace/WorkspaceCommitDiffView.swift`,
  `Chat/ClaudeToolDetail.swift`, `Chat/ClaudeFileCalls.swift`. Findings #4, #15.
- **Batch F — Chat view, transcript, composer:** `Conversation/ClaudeChatView.swift`,
  `Conversation/ChatTranscript.swift`, `Conversation/ChatComposer.swift`,
  `Conversation/ChatWorkGroup.swift`, `Conversation/ChatMascot.swift`,
  `Mascot/ClaudeCrabView.swift`, `Chat/ClaudeStatusLine.swift`, `Conversation/ChatHeader.swift`,
  `Conversation/DraftChatView.swift`. Findings #11, #13, #15, #18, #23, #24.
- **Batch G — Shell and drawer:** `Chat/PaseoShellView.swift`, `Chat/EdgeDrawer.swift`. Findings #7, #14,
  and the §2 drawer items.
- **Batch H — Rich/media:** `Rich/ClaudeRichBlocks.swift`, `Rich/SandboxedHTMLView.swift`,
  `ClaudeMediaView.swift`, `MediaState.swift`. Findings #6, #20.
- **Batch I — Lists and settings:** `Chat/ClaudeHistoryView.swift`, `Sidebar/CommandCenterView.swift`,
  `Chat/PaseoSettingsView.swift`, `Chat/ClaudeAgentControlsSheet.swift`,
  `Chat/DraftControlsSheet.swift`. Findings #16, #17, #25.
- **Batch J — App launch:** `App/Sources/AppModel.swift`, `App/Sources/RootView.swift`. Finding #27.

Suggested order: A, B, C, D (biggest wins), then E, F, G, H, I, J.

---

## 5. How to measure (no Instruments on this Linux VM)

On a Mac with Instruments:

1. **Time Profiler** (apple arm64, main thread). Look for `HostSession.handle(event:)`,
   `ConversationStore.handleStream`, `IncrementalTurnBuilder.turns(from:)`, `MarkdownDocumentModel.init`,
   `RichContentDetector.detect`, `ClaudeCodeHighlighter.highlight`, `DiffModel.init`,
   `PaseoSidebar.body`, `ClaudeChatView.body`, `LayoutEngine` / `_NSLayoutArray` calls.
2. **SwiftUI** template: counts `ViewBody` invocations per view type. Compare `ClaudeChatView`,
   `PaseoSidebar`, `ClaudeRevealProse`, `ClaudeMarkdownView` body counts per token / per scroll frame.
3. **Core Animation / Metal Hierarchy**: offscreen passes (`CA::Render::prepare`), blit cost, mask cost
   (the sweeps in #11), corner-radius continuous paths, `UIVisualEffectView` (glass) sampling.
4. **Animation Hitches** (or `os_signpost` around the drag): frame duration vs commit vs render during a
   drawer drag and during the settle animation; note hitches > 1 frame.
5. **Memory Graph / Allocations / VM Tracker**: `WKWebView` web processes (#6), `conversations` /
   `checkouts` growth (#9), the three cache tables (#22), image decodes (#20).
6. **Network / daemon frame timeline**: count `agent_stream` deltas/sec vs commits/sec (#1); look for
   catch-up bursts.
7. **Signposts to add** (`os_signpost(.intervalBegin/.intervalEnd, .pointsOfInterest)`):
   `HostSession.handle(event:)`, `ConversationStore.updateTurns()`, `TimelineState.applyStream`,
   `IncrementalTurnBuilder.turns(from:)`, `MarkdownDocumentModel.init`,
   `RichContentDetector.detect`, `ClaudeCodeHighlighter.highlight`, `DiffModel.init`,
   `SidebarDirectory` evaluation, `ClaudeChatView.body`, `PaseoSidebar.body`, `ClaudeRevealProse.body`.
   `IncrementalTurnBuilder.turnsBuiltLastUpdate` already exists as a counter.
8. **On-device without Xcode:** `MXMetricManager` hang/frame metrics (if available), or a debug screen
   that shows a display-link FPS counter and the last event-commit latency. `os_proc_available_memory`
   for memory pressure.
9. **Linux microbenchmarks** (the P3 approach): copy the exact functions into a throwaway SwiftPM package
   and measure `MarkdownDocumentModel`, `RichContentDetector.detect`, `FilePathLinks.linkified`,
   `ClaudeCodeHighlighter.highlight`, `DiffModel.init`, `sortedWorkspaces`/`activityDate`,
   `IncrementalTurnBuilder.turns(from:)`. Release build, aarch64 Linux; read as ratios, not phone numbers.
10. **One number to get first:** instrument `HostSession.handle(event:)` to count events/sec and the time
    spent in `store.handleStream`; instrument `ClaudeChatView.body` to count evaluations per second. That
    single pair tells you whether #1 is the dominant cost before any refactor.

---

## 6. Honest confidence notes

- The code claims (what is called, when, and with what inputs) are read directly and are high confidence.
- The per-frame/per-token millisecond estimates are extrapolated from the P3 microbenchmarks and are
  **guesses**; only ratios are trustworthy.
- The drawer lag has multiple plausible causes (gesture arbitration, live animations in the moving card,
  an agent update landing mid-drag, the O(W×A) sidebar rebuild). I did not isolate which dominates; the
  fixes are independent and all worth doing.
- The upstream commit messages describe measured wins in the React Native app; they are evidence that the
  technique matters, not evidence of the same magnitude in SwiftUI.
