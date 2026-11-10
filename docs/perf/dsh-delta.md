# DSH Claude-style delta review (reference 2026-11-08 → clone 2026-11-10)

Read-only review. No repo file was modified. All line numbers are from `/tmp/dshnew` at HEAD
`bbefb4c` (2026-11-10) unless marked "our client".

## 0. Scope correction (read this first)

- The reference clone is at `f4b342d` (2026-11-08 08:58:57 -0700). The new clone is at `bbefb4c`
  (2026-11-10 00:18:16 -0700). `git log f4b342d..HEAD` = **48 commits**.
- **The turn-nav commits named in the task (`00bc6fe`, `44854f9`, `f051a57`) are already in the
  reference snapshot.** They are dated 2026-11-08 05:09–08:02 -0700, i.e. 1–4 hours *before*
  the reference HEAD. `md5sum` of `turn-nav.ts` is identical in both trees. So they are not new in
  `/tmp/dshnew`; the "rebuild" is not part of this delta.
- What those commits actually did is small: `44854f9` added the pointer-steering maths
  (`TURN_NAV_STEER_INSET_PX`, `railMost()`, `onPointerMove`) and `f051a57` made same-frame pointer
  moves use the last recorded place. The card, glide, landing line and Alt+↑/↓ keys already existed
  before them.
- Our client still lacks the *current* turn-nav behaviour, so §1 extracts the full current spec
  and compares it with `ChatTurnRail.swift` / `ChatTranscript.swift`.

Everything below is grouped by the task's priorities. "Applies?" means "should the iPhone client
adopt it"; web/desktop-only is marked **no**.

---

## 1. Turn-nav / prompt rail

### 1.1 What the named commits changed

| commit | file:line | before → after |
|---|---|---|
| `44854f9` | `turn-nav.ts:62` | new `TURN_NAV_STEER_INSET_PX = 8` (pointer steering rest zone at each end of the rail) |
| `44854f9` | `turn-nav.ts:204-209` | new `railMost()` = `max(0, count*24 - railHeight)`; `setOffset()` now uses it instead of recomputing inline |
| `44854f9` | `turn-nav.ts:406-441` | new `onPointerMove`: while the card is open, pointer height over the rail's lines maps proportionally to `list.scrollTop` between the ends' rests; `pointer.x < rail.left` (over the text) freezes the list (`share = -1`) |
| `44854f9` | `turn-nav.ts:412,638` | new `cancelPointerFrame` / `pointer` state; cancelled on close and teardown |
| `f051a57` | `turn-nav.ts:409-416` | before: `if (!open \|\| cancelPointerFrame !== null) return` (a pending frame dropped later moves). after: record `pointer` on **every** move, then `if (cancelPointerFrame !== null) return`; the pending frame reads the newest place. Fixes the list scrolling away from the row about to be pressed |
| `00bc6fe` | — | merge of PR #284 (branch `feat/turn-nav-rebuild`); no code beyond the above |

### 1.2 Full current behaviour spec (the contract our client should port)

**Rail geometry** (`turn-nav.css:13-27`)
- `position: absolute; right: 12px; width: 28px; top: band/2; transform: translateY(-50%)`.
- `band = conversation viewport height − composer height` (`--dsh-composer-height`, default 152px).
- `height = count × 24`; `max-height = min(max(0, band − 64), 240px)`; `overflow: hidden`.
- Hidden entirely in a container ≤ 900px wide.
- One mark per turn at **24px pitch**; a mark is a 20px dash, `scaleX(0.6)`, `border-l4`; a turn
  outside the loaded window is `opacity 0.6; scaleX(0.4)`; the current turn is `scaleX(1)` and
  `label-primary` (`turn-nav.css:46-58`).
- Track `transform: translateY(-offset)` with `transition: transform 150ms ease-standard,
  opacity 120ms feedback` (`turn-nav.css:39-41`).
- Fade masks: 24px top/bottom gradient when `offset > 0` / `offset < most`
  (`turn-nav.css:29-37`).
- Follow: the current mark is centred when it is not already well inside
  (`turn-nav.ts:213-224`).

**Card** (`turn-nav.ts:290-404`, `turn-nav.css:70-153`)
- Opens on `pointerenter` (hover), closes on `mouseleave` after a 100 ms grace
  (`POPOVER_CLOSE_DELAY`, `shared/popover.ts:133`).
- 288px wide, `max-width: page-width − 16`; laid over the rail **row-for-row**: list height = rail
  box height, each row 24px, each row's dash aligned to its mark.
- Rows: prompt text (ellipsized) + trailing dash; current row `label-primary` weight 500; hover row
  `hover-bg` + `label-primary`; `focus-visible` brand outline.
- Card fades in/out (`opacity 120ms`), no transform; the rail's marks fade to `opacity 0` while
  open (`turn-nav.css:43-45, 70-80`).
- Wheel: the list scrolls (`overflow-y: auto; overscroll-behavior: contain`), the page under the
  card does not move.

**Pointer steering** (`turn-nav.ts:406-441`)
- `share = clamp((pointer.y − rail.top − 8) / (rail.height − 16), 0, 1)`; `list.scrollTop =
  round(share × railMost())`.
- Left of the rail lines (`pointer.x < rail.left`, i.e. over the row text) → list stands still.
- Frame-coalesced: one `requestFrame` at a time; every move updates `pointer`; the frame reads it
  in its read phase and writes in the scroll phase.

**Jump + landing** (`turn-nav.ts:412-474`, `turn-nav.css:155-194`)
- Pressing a row presses the host's mark, which pages history in if the turn is unloaded, then
  lands it.
- `glideLanding`: the host's instant `scrollTop` write is taken back and the **last 480px**
  (`TURN_NAV_GLIDE_LEAD_PX`) is glided with `easeScrollFor`; reduced motion jumps instantly.
- Landing line: a 2px accent line (`--dsw-alias-brand-primary`, #D97757) at `top: -8px` over the
  landed turn's first row; keyframes `0% opacity 0 scaleX .5 → 25% opacity 1 scaleX 1 → 70%
  opacity 1 → 100% opacity 0`, duration `1400ms` ease-out; reduced motion: no animation (line
  stands for its time).
- Landing waits up to 10s for an unloaded turn's row to arrive.

**Keys** (`turn-nav.ts:485-512`)
- Alt+↑ / Alt+↓ jump to the previous/next turn from the one being read; a repeat within 1200ms
  steps on from the last target; the keys stand down while a draft, a dialog or `dsh-plugin-msg-nav`
  holds them.

### 1.3 Our client today

- `Packages/PaseoUI/Sources/PaseoUI/Conversation/ChatTurnRail.swift`
  - 24pt touch strip, **8pt slots** that shrink to `max(1, viewportHeight*0.8/count)` (line 67).
    A 400-prompt conversation gets ~1.6pt ticks — unreadable and unusable to scrub.
  - Magnification radius 3 with a raised-cosine falloff (line 226), preview bubble 260×48
    (lines 140-160), jump on release, selection haptics throttled to 35 ms.
  - Reveal: 1.5 s idle timer (`ChatTranscript.swift:678-690`).
  - No card, no proportional steering, no fade masks, no landing line, no keyboard nav, no
    unloaded-turn treatment.
- `ChatTranscript.swift`
  - `jumpToTurn` (line 700): `withAnimation(.smooth(duration: 0.55)) { proxy.scrollTo(id) }` —
    animates the **whole** distance; no glide-lead, no landing line.
  - `jumpToPrompt` (line 691) fetches the window via `store.jump(toPromptSeq:)` first — this part
    already matches the host contract.
  - `ChatTurnNavSheet` (line ~230): every prompt, 48pt rows, spinner while loading. Good, but the
    row pitch does not match any rail and unloaded rows are not distinguished.
- `ChatOutlineItem` has no `loaded` flag, so the rail cannot draw unloaded turns fainter.

### 1.4 Applies to our iPhone client?

| DSH behaviour | Applies? | Why |
|---|---|---|
| Hover card over the rail | **no** | Pointer hover is desktop. Our "Jump to message" sheet already lists every prompt (UX-SPEC §4.3) |
| Proportional pointer steering | **no** | Pointer. A touch equivalent (drag the list) is possible but the sheet already covers the need |
| 24px pitch, 28px width, max-height `min(band−64, 240)`, fade masks, current-marker follow | **yes** | Pure layout/motion; our compressed 1–8pt slots are worse on long conversations |
| Glide-lead (instant jump + last 480px glide) | **yes** | Motion; our 0.55 s whole-distance animation makes the reader wait |
| Landing line | **yes, with a palette change** | Wayfinding. DSH uses orange #D97757; UX-SPEC §0.1 forbids orange as state, so use `ink` |
| Unloaded turns fainter + paging jump | **yes** | Our rail already jumps through `store.jump(toPromptSeq:)`, but does not mark unloaded turns |
| Alt+↑/↓ | **no** | Hardware keyboard is desktop-only in this client (PARITY) |
| 10s landing wait, 1200ms key repeat | **no** | Part of the hover/keyboard path |

### 1.5 Concrete changes (Packages/PaseoUI)

1. **`Conversation/ChatTurnRail.swift`** — replace the compressed-slot scrub with the DSH rail:
   - fixed `slotHeight = 24` (or a scaled pitch that keeps ≥ 10 marks), `stripWidth = 28`,
     `maxHeight = min(viewportHeight − composerHeight − 64, 240)`;
   - a scrollable track (`offset` clamped to `max(0, count*pitch − maxHeight)`) with 24pt fade
     masks at both ends;
   - a current marker that centres itself when it leaves the window (port `follow()`);
   - add `loaded: Bool` to `ChatOutlineItem` and draw unloaded ticks at 0.4 opacity / 0.4 scale.
2. **`Conversation/ChatTranscript.swift` `jumpToTurn` (line 700)** — adopt glide-lead: scroll
   instantly to just above the target (or the nearest estimated offset), then
   `withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(id, anchor: .top) }`. Keep the
   `store.jump(toPromptSeq:)` paging path in `jumpToPrompt`.
3. **`Conversation/ChatTranscript.swift`** — add the landing line over the landed turn's first
   row: 2pt `ink` rule at `top: -8pt`, `scaleX 0.5 → 1 → fade`, 1400 ms ease-out, reduced-motion
   off. (Use ink, not orange — UX-SPEC §0.1.)
4. **`Conversation/ChatTurnRail.swift` `ChatTurnNavSheet`** — set row height to the rail pitch
   (24pt) and render unloaded rows fainter, so the sheet and the rail agree.

---

## 2. Performance commits

### 2.1 Named commits

#### `41a2032` — chat-follow smoothing
- **file:line**: `features/chat-follow/chat-follow.ts:183-186, 362-366, 419-470`
- **before → after**: the follow slide was driven by the column's height delta
  (`before = slideHeight`, `grew = box − slideHeight`) and only ran when the column already
  overflowed (`before < scrollerHeight`). Sibling rows in the same frame could make the host's
  actual `scrollTop` move by more or less than the column grew, so the slide skipped or pushed the
  text. After: `slideScrollTop` records the scroller position after each resize batch; the slide
  is driven by `moved = scrollTop − slideScrollTop`; `moved < 0` stops the slide, `moved > 0` starts
  it; the `before < scrollerHeight` gate is gone.
- **applies?**: partially. Our follow logic (`ChatTranscript.swift:245-276`, `scrollToBottom` at
  283) is threshold-based (`distanceFromBottom ≤ 16` / `> viewportHeight/3`) and re-anchors to the
  bottom on every `store.turns.last` change with a 0.2 s animation. The DSH bug (sibling rows
  changing the pin) is a web ResizeObserver artefact; SwiftUI does not expose that. The real
  analogue is animation churn: a 0.2 s `scrollToBottom` restarted on every turn change.
- **concrete change**: `Conversation/ChatTranscript.swift` — throttle/coalesce `scrollToBottom`
  during streaming (e.g. only re-anchor when the tail actually moved and the previous animation
  has settled), or use a single persistent offset binding instead of repeated `withAnimation`
  `scrollTo`. Low priority.

#### `8aa3e36` + `aab1b8f` (D90) — row-skip height cache
- **file:line**: `features/row-skip/row-heights.ts:1-62` (new), `row-skip.ts:48-90, 99-130,
  158-240`, `row-skip.css:16-19`
- **before → after**: rows were only skipped (`content-visibility: auto`) after a real layout at
  the current width, so switching back to a long session laid out every row first (D90: ~1.5 s
  task, ~1 s style recalc for two 100-row sessions). After: each row's real height is cached by
  `node key | flow kind | group part` (LRU 4096); on a remount batch the height is written as
  `contain-intrinsic-size` **before first layout** and the row is skipped from frame one. The
  cache is cleared when the column width or interface font size changes; streaming rows are not
  cached.
- **applies?**: **no**. SwiftUI `LazyVStack` does not lay out off-screen rows; there is no
  `content-visibility` and no height-estimation jump. Session-switch cost here is view
  re-creation, not row layout.
- **concrete change**: none. If session switching is measured slow, the SwiftUI fix is state
  preservation (keep the transcript view/store alive), not a height cache.

#### `2935761` — long-session per-frame cost
- **file:line**: `chat-follow.ts:71-120, 205-220, 636-670`; `process-follow.ts:55-110`;
  `active-first.ts:42-115`; `chat-fold/process-fold.ts:22-50`; `date-groups.ts:298-305`;
  `workspace/archived-list.ts:169-295`
- **before → after**:
  - back-to-end button placement moved from the write phase (`placeFollowTail` reading
    `getBoundingClientRect` in `sync`) to a read phase (`readFollowTail`/`writeFollowTail`);
  - "is streaming" now scans the last 3 blocks of the column instead of
    `column.querySelector(FOLLOW_RUNNING_SELECTOR)` over the whole transcript;
  - process groups: one query per flow per batch (`turnGroups`) instead of one per touched node;
  - sidebar "active first" reorder only runs when a mutation is inside a session row;
  - archived list: signature covers only the visible window (`order.slice(0, cursor)`), and a row
    already in place is not re-inserted (`container.children[at] !== row`);
  - date groups prune detached labels from their set.
- **applies?**: partially. Our `.onScrollGeometryChange` action (`ChatTranscript.swift:245-276`)
  runs every frame and calls:
  - `reportReadingPosition()` (line 671) — `store.turns.first(where:)` is **O(turns)** per frame;
  - `revealTurnRail()` (line 678) — cancels and re-creates a `Task` every frame;
  - `restoreHistoryAnchor` / `loadOlderIfNeeded` — O(1), guarded.
  The DSH read/write split and DOM scans have no SwiftUI equivalent (SwiftUI does not force
  layout in a scroll handler), but the O(n) report and the Task churn do.
- **concrete change**: `Conversation/ChatTranscript.swift`
  - make `reportReadingPosition()` O(1): keep the topmost visible turn in
    `TranscriptScrollTrack` (it already tracks `visibleTurnIds`; add an ordered structure or
    update a `topVisibleTurn` on `onAppear`/`onDisappear`);
  - only call `store.promptOutline.reportReadingPosition` when the anchor seq actually changed;
  - throttle `revealTurnRail()` so it does not cancel/restart the idle Task on every frame
    (e.g. only reset the timer when it is not already scheduled).

#### `4b38c12` — chat-reveal scan cost
- **file:line**: `chat-reveal/reveal-diff.ts:108-320`; `reveal-text.ts:1-43` (new);
  `reveal-params.ts:14-16, 60-75`; `reveal-paint.ts:118-130`; `reveal-engine.ts:183-215`
- **before → after**: every batch walked the container's whole text tree with a `TreeWalker`
  (O(chars)) and rebuilt the index; character lookups were linear. After: tail-only
  `characterData` mutations append to the existing index (`appendRevealSnapshot`); structural
  changes rebuild; entry lookup and slicing use binary search (`revealEntryAt`); a global
  `CHAT_REVEAL_ACTIVE_LIMIT = 2048` bounds overlapping runs, and oversized batches are shown
  without reveal (`min(BURST_LIMIT, available)`).
- **applies?**: partially. Our `ClaudeRevealProse` is a mask sweep, not a per-character Highlight
  API, so there is no text-tree walk. But `pieceRefs(markdown)` is recomputed in `body` on every
  streaming delta (`ClaudeRevealProse.swift:88`), re-splitting the source, and
  `ClaudeMarkdownView(document: .cached(trimmed))` re-parses. The incremental-index idea applies.
- **concrete change**: `Chat/ClaudeRevealProse.swift` — memoise `pieceRefs` by `markdown`
  identity and only recompute the tail piece; avoid re-parsing unchanged pieces. Keep the
  existing `tailStart`/`tailLength` incremental sweep.

#### `bb343ab` — write-phase layout reads
- **file:line**: `caret.ts:296-520`; `chat-fold/message-fold.ts:70-90, 203-215`;
  `context-stats/meter-ring.ts:246-365`; `effort/slider.ts:547-560`
- **before → after**: `getComputedStyle`, `getBoundingClientRect`, `clientLeft/scrollLeft` were
  read in the write phase, invalidating earlier writes and forcing a 13–14k-element style recalc
  (40–50 ms). After: all reads moved to the pass's read phase; the write phase only compares and
  writes. Measured: 18 s recording, write-phase full-page recalcs 18 → 2; send task 649 → 534 ms.
- **applies?**: **no**. SwiftUI does not expose forced layout reads; layout is the framework's
  job and there is no `getComputedStyle` equivalent.
- **concrete change**: none.

### 2.2 Other perf commits (brief)

| commit | technique | applies? | change |
|---|---|---|---|
| `541bb6f` | session switch is one bus broadcast (`observeSession`, D91); batch additions shared (`batchAdditions`/`observeMarker`); header-band placed in one pass; message fold reads only bubbles the batch touched | no — web MutationObserver / React remount model | none |
| `83b5d41` | assistant-text growth skips the user-message fold scan; structural changes request a full pass | no — DOM observers | none |
| `6a64556` | release size observers when the page removes a message/bubble | no — DOM observers | none |
| `c850a48` | release scroll/wait holds for detached conversations on session switch | no — DOM/JS memory | none |
| `0ef537b` | release context-stats bindings for detached surfaces (30 switches → stable ~38k nodes / 45 MB) | no — DOM/JS memory | none |
| `a27dede` | one selection/addition read per batch; colour cache; seat watch released on teardown | no — DOM/JS | none |
| `96a432f` | convert column widths before paint during large sidebar batches (page zoom) | no — web zoom | none |
| `482e6ee` | cap the decompressed-asset cache in the node engine | no — node host | none |
| `2075774` | budget lowercase copies in host search | no — host search | none |
| `d329956` | batch-measure date-label widths (30 forced layouts → 1; 2.7 s → instant) | no — web layout; our home hero has no model chart | none |
| `f0e1bc1` | release the right-bar slot registration when the header band is switched off | no — web slot registry | none |

---

## 3. Sidebar, composer, message-actions, sound-cues, effort dots

| commit | what changed (before → after) | file:line | applies? | concrete change |
|---|---|---|---|---|
| `da7ce7b` | "in progress" marker default moves from trailing to **leading** (row start); title follows it, actions keep the trailing edge | `contracts/src/prefs.ts:385`; `sidebar-status.ts:10` | optional | Our `SidebarWorkspaceRow.swift:17,26` draws the status dot trailing and has no side setting. Only adopt if we want DSH's default; UX-SPEC is silent. If adopted, move `PaseoStatusDot` to the leading edge and keep the unread dot trailing |
| `87c671e` | with the marker leading, a row whose leading seat is a foreign plugin's content no longer keeps the 26px trailing column, so its time aligns with the other rows | `sidebar-status.css:10-17` | no | Only relevant with a leading marker + foreign sidebar content; our rows have neither |
| `1be7ddf` | the "Show N more sessions" overflow row's left inset now matches the session title start (26px leading mode / 24px trailing) | `sidebar-status.css:16-27`; `parts-table.ts:80` | no | Our `SidebarDirectory.swift` has a hidden-workspaces row but no overflow row (grep found none) |
| `e2ef497` | hover-peek sidebar: suppress the host layout frame's 0.3 s track transition while peeking, so closing slides out once instead of twice | `sidebar-peek.css:29-35` | no | Web hover peek; our sidebar is an edge drawer (`PaseoShellView`) |
| `e52d546` | a `<section>` footer plugin block keeps its layout space above the account row instead of being gathered into the account menu | `account/footer-mirror.ts:112-130`; `footer-takeover.css:86-110` | no | Our sidebar footer is avatar + New session pill + usage; no plugin blocks |
| `5e0854f` | compact composer: with no right-hand control, the model label truncates in place instead of wrapping the toolbar to a second line | `composer/responsive.css:54-64` | no | Our `ComposerModelChip` (`ChatComposer.swift:726-753`) uses `.lineLimit(1)` in a non-wrapping `HStack`; SwiftUI has no flex-wrap path |
| `04555ae` | custom username field keeps its own draft during IME composition; no save/write-back mid-composition; Escape restores the pre-edit value | `settings/settings.ts:150-360` | no | Our client has no username field (the greeting reads a name only: `ClaudeHomeHero.swift:59`) |
| `1b016a8` | answer-row action buttons (rerun/delete) move before the usage + time cluster | `message-actions/message-actions.ts:276-282` | no | Our message actions are on user bubbles only (`ChatTurns.swift`); answer rows have no action buttons |
| `bf1afd9` | four sound settings (master + permission + completion + volume) collapse to one **Off / Soft / Clear** setting, default Off; Off installs nothing | `contracts/src/prefs.ts:414-421`; `contracts/src/sound.ts:18-31`; `sound-cues.manifest.ts` | **already done** | Our `Chat/SoundCues.swift` already ships Off/Soft/Clear with default Off. No change |
| `58773b7` | the effort slider's top-rung dot matrix goes from 235 blocks × 4 CSS animations (940 animation instances) to **one canvas**; drag p95 12.6 → 6.4 ms, settle 12.4 → 6.3 ms, release max 56.3 → 18.7 ms, animations 943 → 0 | `effort/matrix-field.ts:1-211` (new); `matrix.ts`; `slider.ts:547-560` | no | Our client deleted the slider; UX-SPEC §4.2 mandates the list control. No `EffortLadder.swift` exists. No change |
| `3c15c89` | selected radio ring in a question card: filled blue disc + radial white centre → 5px blue border with the row's own surface centre (dark theme showed a white disc) | `question-card/question-card.css:132-160` | no | Our permission cards use buttons (`ClaudePermissionCard.swift`), not radio rings |
| `e45d0fc` | model picker hides the "More models" row (and its divider) when level 1 already lists every provider; the empty footer disappears too | `model/model-picker.ts:324-330`; `model-picker.css:41-46` | no | Our model picker is a sheet (`ClaudeAgentControlsSheet.swift`) with no "More models" row |
| `ab0f30b` / `7ebedda` | the account menu's armed marker only hides the account menu's own card, not every host menu | `account/account-footer.css:339-360` | no | Our settings avatar is a plain button; no armed-window concept |
| `3f2075e` / `6a57056` / `f0e1bc1` | header band: title width no longer locked to the previously measured (clipped) width; the chip cluster returns to the host row when it does not fit; the right-bar slot is released on teardown | `header-band/header-band.ts:397-460, 520-555` | no | Our `ChatHeader.swift` is a simple title + menu; no lifted band or chip cluster |
| `f4b342d` / `709ddab` / `0ef537b` | context-stats footer: the first number no longer makes the composer jump; compact bottom bar collapses blank stat rows; bindings released on session switch | `context-stats/footer-layout.css`; `parts-table.ts`; `stats-binding.ts` | minor | Our context ring is in the composer toolbar (`ChatComposer.swift:511-525`). The "first number jump" analogue: the ring appears only when `percentUsed/usedTokens/maxTokens` are all present, so the toolbar can shift when the first reading arrives. Optional: always render the 16pt ring (empty track) when the host reports a window, so the slot is reserved |

---

## 4. Ranked action list

1. **`Conversation/ChatTurnRail.swift` — rebuild the rail geometry to the DSH contract.** Fixed
   24pt pitch, 28pt strip, `maxHeight = min(band − 64, 240)`, scrollable track with 24pt fade
   masks, current-marker follow, unloaded ticks at 0.4. This fixes the 1–8pt compressed slots that
   make long conversations unusable. (Highest value; pure layout, no dependency.)
2. **`Conversation/ChatTranscript.swift` `jumpToTurn` — glide-lead + landing line.** Instant
   scroll to just above the target, then a ~0.3 s `.smooth` glide; 2pt ink landing line over the
   landed turn's first row (1400 ms ease-out, reduced-motion off). Adopt DSH's motion, substitute
   ink for orange per UX-SPEC §0.1.
3. **`Conversation/ChatTranscript.swift` `onScrollGeometryChange` — cut the per-frame cost.**
   O(1) reading-position report (track the topmost visible turn), only write
   `promptOutline.reportReadingPosition` when the anchor changes, throttle
   `revealTurnRail()`'s Task churn.
4. **`Chat/ClaudeRevealProse.swift` — incremental piece parsing.** Memoise `pieceRefs` by
   markdown identity; only recompute the tail piece on append. Ports the spirit of `4b38c12`
   without the DOM text-tree machinery.
5. **`Conversation/ChatTurnRail.swift` `ChatTurnNavSheet` — align with the rail.** 24pt row
   pitch and unloaded rows fainter, so the sheet and the rail read as one control.
6. **Optional: `Conversation/ChatComposer.swift` `contextMeter` (line 511).** Reserve the 16pt
   ring slot when the host reports a window, so the first usage reading does not shift the
   toolbar (the `f4b342d` analogue).
7. **Optional: `Sidebar/SidebarWorkspaceRow.swift`.** Move the status dot to the leading edge to
   match DSH's new default (`da7ce7b`). Only if the lead wants DSH parity; UX-SPEC does not
   specify, and the trailing dot doubles as the unread attention dot.

### Not applicable (web/desktop-only), no change
Row-skip height cache (`8aa3e36`/`aab1b8f`), write-phase layout reads (`bb343ab`), all
MutationObserver/bus/JS-memory perf (`541bb6f`, `83b5d41`, `6a64556`, `c850a48`, `0ef537b`,
`a27dede`), page zoom (`96a432f`), node asset cache (`482e6ee`), host search (`2075774`), home
chart batch measure (`d329956`), hover peek (`e2ef497`), footer plugin blocks (`e52d546`),
composer flex truncation (`5e0854f`), username IME (`04555ae`), answer-row action order
(`1b016a8`), effort dot canvas (`58773b7`), question-card radio (`3c15c89`), model "More models"
(`e45d0fc`), account armed window (`ab0f30b`/`7ebedda`), header band (`3f2075e`/`6a57056`/
`f0e1bc1`), sidebar overflow/foreign-row alignment (`1be7ddf`/`87c671e`).

### Repo-internal, not user-visible (no change)
Test/refactor/CI/data/release commits (`bbefb4c`, `618e116`, `5a29fc2`, `27476dc`, `f3f6e4c`,
`bfda697`, `5c6161e`, `10e7017`, `4918015`, `0457255`, `3a4b732`, `55777f9`, `9365e20`,
`df462de`/`7bbb6f5`/`0012c4e`/`c8249d6` merges, `f96251f` AGENTS.md/test-header command table).

### Already done in our client
Sound-cues Off/Soft/Clear single setting (`bf1afd9`) — `Chat/SoundCues.swift`.
