# R6: the conversation, split into narrow views

Branch: `r6-conversation`, from `foundation` after R4 is merged (R3 is merged too). Read
`docs/tickets/_R-common.md`, then `docs/UX-SPEC.md` §3–§4.5 and `docs/refactor/PLAN.md` §RC1–RC7,
§RC10, §RI. Evidence: `docs/refactor/audits/B-perf.md` N1, N2, N7 and N8.

**Owns:** `Conversation/Screen/`, `Conversation/Transcript/`, `Conversation/Composer/`,
`Conversation/Turn/`, `Conversation/Mascot/`, `Draft/` and `Voice/`. `Conversation/Sheets/` and
`Conversation/Prose/` are **not** yours: R4 did the sheets and R9 owns prose. Calling prose views
is fine.

Runs in parallel with R5 (Shell), R7 and R8. The shell passes the same callbacks as today.
`ClaudeChatView` keeps its public init (`public typealias` is fine if you rename).

**Goal:** typing touches only the composer, and streaming touches only the last turn row and the
status line. Behavior and look stay the same except where this ticket says otherwise.

## 1. `ChatController` (new, `Conversation/Screen/ChatController.swift`)

`@MainActor @Observable final class ChatController`, one per open agent. The screen holds it in
`@State`, created once per `store.agentId`.

**Move into the controller** every `@State` of `ClaudeChatView` that isn't a SwiftUI-only handle
(`@FocusState`, `ScrollPosition`, `ScrollViewProxy` and `@Environment` stay in views):
- sheet routing;
- find state (`findOpen`, `findQuery`, `findIndex`, `findFlash`, `findAnchor`, the search task);
- follow and anchor state;
- pending rewind and message actions, rename and archive state;
- `permissionResolvedLines`, `hiddenSubagentIds`, `openFilePath`;
- slash and mention state;
- the queue and attachment store references;
- the dictation controller and the voice engine;
- the mascot machine and its baselines.

The controller's methods take over the logic now in the `ClaudeChatView` extensions:
- `send`;
- `jumpToPrompt` (it records intent; the transcript view performs the scroll);
- `performPendingRewind`;
- `forkInto`;
- `retractMessage` / `deleteTurn`;
- slash loading;
- mention indexing;
- draft save scheduling.

**Delete the per-view `toast` state.** Toasts go through `@Environment(\.toast)` (R4 `ToastCenter`).

## 2. Screen = small view structs with narrow reads

`ChatScreen` (rename of `ClaudeChatView`) body:

```swift
VStack(spacing: 0) {
    ChatHeaderBar(store: store, controller: controller)     // struct
    if controller.find.isOpen { ChatFindBarView(controller: controller) }
    TranscriptView(store: store, controller: controller)     // struct
    SubagentPill(store: store, controller: controller)       // struct
    ComposerView(mode: .conversation, store: store, controller: controller)  // struct
}
.environment(\.chatActions, controller.actions)
.modifier(MascotDriver(store: store, session: session, controller: controller))
.modifier(ChatSheets(store: store, session: session, controller: controller))
```

**Rule:** `ChatScreen.body` reads **no** `store` or `session` property except identity
(`store.agentId` for `.id`). Each struct reads only what it draws. Put a comment block at the top of
each struct listing the store properties it reads; the lead reviews against that list.

**Header** (`ChatHeaderBar`):
- `ShellHeader(leading: .sidebar(onOpenSidebar), title: { titleMenu }, trailing: { GlassIconButton("sidebar.right", "Open workspace panel") })`.
- Delete the chat's `connectionBanner` and `bannerRow`. The shell owns the one banner (R5).
- The title menu keeps its items and order, and gains the RH order (§5 below).
- The rename alert message: delete the sentence "The name shown in the sidebar and the header."
  (audit C #21). Keep "Rename agent", "Name", "Cancel" and "Rename".
- "Copy agent ID" uses `Clipboard.copy(_:toast:)` with "Agent ID copied".

## 3. Mascot driver (no scans)

`MascotDriver: ViewModifier` with its own body. Each input is read from the R3 O(1) values:

| Input | Source |
|---|---|
| failed tool calls | `store.timeline.failedToolCalls` (seq-aware: entries with `seq >= mascotSeqFloor` are live) |
| running subagents | `store.timeline.runningSubAgentCount` |
| compaction | `store.timeline.lastCompactionStatus` |
| activity | `store.timeline.latestRowKind` + `latestRowId` |
| busy, pending and attention counts | `session.runningAgentCount`, `session.pendingPermissionCount`, `session.attentionCount` |

Same `onChange` logic and same seeding as `ChatMascot.swift` today. **Delete** the computed scans
`mascotActivitySignature`, `liveFailedToolCallIds`, `failedToolCallIds`, `runningSubagents`,
`lastCompactionStatus`, `busySessions`, `pendingInteractions` and `attentionCount`. Keep the 1 s sleep
ticker as today: it runs only while `mascot.state != .sleeping`, and also stops while
`\.isSurfaceObscured` is true (R4/R5 environment).

## 4. Transcript

**Rows are equatable values.**
- `ChatActions` is `@MainActor @Observable final class`, created once by the controller and put in
  the environment. It holds:
  - `openFile`, `markdown`, `rewind(scope, messageId)`, `edit`, `rerun`, `fork`, `forkInFlight`,
    `deleteTurn`, `retract`, `loadImage`;
  - the flags `canFork`, `canRewrite`, `rewindChoices`;
  - `func cutRow(for userRow: TimelineRow) -> TimelineRow?`, using
    `store.timeline.rowIndex(forSeqEnd:)` (O(1); delete `boundaryBefore`'s `firstIndex` scan).
- `TurnRow` (rename of `ClaudeTurnView`) takes exactly: `turn: Turn`, `isLatest: Bool`, `findSeq: Int?`
  (non-nil only if the find target is inside this turn), `flashSeq: Int?` (same rule) and
  `isLanding: Bool`. It conforms to `Equatable` (all inputs), and is used as `TurnRow(...).equatable()`.
  It reads closures from `@Environment(\.chatActions)`. Its subviews (`ClaudeUserBubble` and the
  rest) take their callbacks from the actions object, not from init closures.
- **The `ForEach`:** `ForEach(store.turns) { turn in … }`. No `Array(enumerated())`.
  `isLatest = turn.id == lastId`, with `lastId` computed once before the `ForEach`.
- **Find inputs:** `findSeq` / `flashSeq` are computed per row only while find is open; otherwise
  they are nil without any scan.

**Following the tail** (replaces the per-commit animated `scrollTo`):
- Delete `.onChange(of: store.turns.last) { scrollToBottom(proxy) }`.
- Apply `.defaultScrollAnchor(.bottom, for: .sizeChanges)` (iOS 18) while
  `controller.isFollowing`. Use `.defaultScrollAnchor(.top, for: .sizeChanges)` while not following
  or while `anchoringToAnswer`. Growth at the tail then keeps the bottom pinned with no animation,
  and the reader's line stays put when not following. Use one modifier with a computed anchor:
  `.defaultScrollAnchor(controller.followAnchor, for: .sizeChanges)`.
- **Opening a conversation:** `.defaultScrollAnchor(.bottom, for: .initialOffset)`. Delete the
  `onAppear` `scrollToBottom(animated: false)`.
- **"Back to end"** and focusing the composer:
  `withAnimation(Motion.glide.resolved(...)) { scrollPosition.scrollTo(edge: .bottom) }`.
- **Send anchor (M7d):** one `scrollPosition.scrollTo(id: sentTurnId, anchor: .top)` with
  `Motion.glide`, then `anchoringToAnswer = true`. That sets the anchor to `.top` until the content
  overflows the viewport (the same 16 pt rule as today), then `isFollowing = true`.
- **Pending permission cards** appearing while following need nothing extra (the size change is
  anchored).
- **`onScrollGeometryChange` action:** O(1) work only.
  - It keeps the follow / unfollow thresholds (≤ 16 pt from the bottom → following; > ⅓ viewport
    → not following).
  - It also keeps the history auto-load and the restore anchor.
  - Move `reportReadingPosition()` and `revealTurnRail()` out of the per-frame action:
    - call them from `.onScrollPhaseChange` (`.interacting` / `.decelerating` → reveal the rail;
      `.idle` → report the reading position);
    - also call them at most every 100 ms while scrolling, through a timestamp check in the action.
- **The rail's touch strip:** while the rail is visible, set `shellDrawer.trailingEdgeReserved = true`
  (R5 bridge; read `@Environment(\.shellDrawer)`, which may be nil in previews); false when it hides.
- The glide-lead and landing-line code stays (P6-F), moved into `TranscriptView`.

**States** (audit C #22 and the empty agent):
- A failed load shows `InlineBanner(.failure, title: <error>, action: ("Try again", reload))` inside
  the transcript area. `reload` is the store's existing load entry point.
- An existing agent with zero turns shows `EmptyState(systemImage: nil, title: "No messages yet")`,
  not the new-session greeting. That wording is approved.

## 5. One composer

`ComposerView(mode: .draft(DraftSession) | .conversation, …)`, built from today's `ChatComposer` card.

- `Draft/DraftChatView.swift` deletes its own `TextField` card and uses `ComposerView(mode: .draft)`.
  The draft-only behaviors are inputs:
  - the collapsed pill at rest (UX-SPEC §4.1, unchanged);
  - the provider in the model chip;
  - the workspace line above.
- **The text binding** is `store.draft` (conversation) or `draft.text` (draft). Only `ComposerView`
  and its children read it.
- **Derived values:** `canSend`, `isTall`, `slashQuery` and `mentionQuery` are computed inside
  `ComposerView`'s body (not in the screen). `isTall` uses an O(1)-ish check: count `\n` with an
  early exit at 5, or `utf8.count > 400`. No `components(separatedBy:)`.
- **Bubble size:** 17 pt (UX-SPEC §4.1, amended). In `ClaudeUserBubble`, the bubble font becomes
  `Font.paseo(.body)` and the line spacing becomes `4`. It keeps radius `Radius.bubble`.
- **Cursor:** the cursor and selection tint are `Palette.ink`, not orange (audit C copy §).
- **Placeholder:** one string in both modes, taken from upstream `en.ts`. Find the composer
  placeholder key; cite it. If upstream has several, use the generic one.
- **Hardware keys:**
  - ⌘↩ sends (`.keyboardShortcut(.return, modifiers: .command)` on the send button);
  - in the find bar, Return goes to the next match and ⇧Return to the previous one
    (`.onSubmit` plus `.onKeyPress` for shift);
  - ⌘F opens find. The header's menu item keeps working.
- **Tap targets:** every composer control has a 44 pt hit area (`.frame(minWidth: 44,
  minHeight: 44).contentShape(.rect)`) without changing its visuals. This covers the attachment
  remove (20 → 44 hit), the find bar's next / previous / close, and the message copy.

## 6. Off-main images (audit B N7, N8)

- **Attach:**
  - `ComposerAttachments` decode, resize to 2048 px and JPEG-encode inside
    `Task.detached(priority: .userInitiated)`. Use `CGImageSourceCreateThumbnailAtIndex` with
    `kCGImageSourceThumbnailMaxPixelSize: 2048` and `kCGImageSourceCreateThumbnailFromImageAlways`.
  - The tray shows a placeholder tile with `InlineProgress` until it's ready.
- **Inline images** (`actions.loadImage(path)`):
  - read through R3's `WorkspaceFiles.fetch(path:)`, never `read`;
  - decode and downscale to the display width × screen scale off main, using the same thumbnail API;
  - cache by `(workspaceId, path)` in an `NSCache` owned by the controller.

## 7. Interaction grammar here (PLAN §RH)

- **The title menu, in order:**
  1. "Jump to message…" (when available);
  2. "Search in conversation";
  3. "Rename…";
  4. "Copy agent ID";
  5. a divider;
  6. "Archive agent" (destructive).
- **Archive agent:** a confirmation only while running (existing text). Otherwise archive at once,
  then show a toast "Agent archived" with Undo, which calls the existing unarchive path
  (`refresh_agent_request`, as History uses). "Agent archived" is approved wording.
- **Haptics:** send = `Haptics.send()`; turn finished while visible = `Haptics.settle()`
  (existing). No other new haptics.

## Proof

- `swiftc -parse` on every touched file.
- Style lint 0 in your folders.
- In your final message, the per-struct "reads" list (§2).
- **Unsure:** `defaultScrollAnchor(_:for:)`, `ScrollPosition.scrollTo(edge:)`, `onScrollPhaseChange`,
  `.equatable()` with `@Observable` environment, and `CGImageSource` options.
