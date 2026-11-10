# Refactor and polish plan (R-round)

Written by the lead, 2026-11-10, after a whole-codebase read: PaseoUI is ~41k lines, PaseoCore ~31k,
and most of it was written by about a dozen workers. **Goal:** make the app feel like one thing,
designed by one person.

- **What matters most:** smoothness, responsiveness and performance.
- **Then:** Apple-level polish and Claude taste.

This plan is the contract for the implementation round. `docs/UX-SPEC.md` still rules behavior. This
document rules structure, motion and the order of work. Sections marked **(audit)** cite the
three read-only audits run for this plan, saved under `docs/refactor/audits/`.

---

## 0. Diagnosis: why it doesn't feel like one app yet

The features work. The problems come from how they were built, not from any single bug:

1. **Views observe too much.** `ClaudeChatView` holds about 60 `@State`s and 18 `onChange`s. Its body reads
   `store.draft` (composer), `store.timeline.rows` (four O(rows) scans for the mascot) and
   `session.agents` (mascot presence). So:
   - **Every keystroke** re-evaluates the whole conversation: header, transcript `ForEach`, and every
     visible turn row. Turn rows take about 12 closures, so they are never equal and their bodies
     re-run too. The P3 `DraftObserver` fixed only one of the reads (`ChatComposer.swift:442,463`,
     `slashQuery`, `mentionQuery`, all inside the chat's body).
   - **Every streamed commit** (≤60 Hz after P5-A) runs four full timeline scans in `ChatMascot.swift:36-108` and re-renders all
     visible turns.
   - **Any agent update anywhere** (another agent's status) re-renders the open chat.
2. **Gesture-driven drawers in pure SwiftUI.** Two or three `simultaneousGesture` `DragGesture`s sit over the transcript's
   `ScrollView`. Every finger move writes `@State` progress, and the settle is a SwiftUI animation that
   ignores the finger's release velocity. That is why the drawers feel "laggy" even after P3. The
   finger and the surface are separated by SwiftUI's graph on each frame, and release has a speed
   discontinuity.
3. **Streaming scroll fights the user.** `onChange(of: store.turns.last)` → `withAnimation(.easeOut(0.2))
   { proxy.scrollTo("bottom") }` starts a new animated scroll **per commit**, up to 60 overlapping
   animations a second. This is the jitter and "rubber" feel while answers stream.
4. **Per-call cost in the design system.** `ClaudeTypography.serif/sans/mono` run `CTFontCreateWithName`
   plus a PostScript compare (`ClaudeFontResources.isAvailable`), and read `UserDefaults` for the text
   scale, **on every call, from bodies**. `ClaudePalette.background` and others read `UserDefaults`
   (`pureBlackActive`) in their dynamic provider on every resolve. Font-size changes rebuild the whole
   app through `RootView .id(rebuildKey)`, which drops the shell state.
5. **No shared components, so each worker made its own.** Three copies of the sidebar button header
   (`PaseoShellView.swift:314`, `ChatHeader.swift:13`, `DraftChatView.swift:123`). Two composers (`ChatComposer`, `DraftChatView`'s own `TextField` card). **Two
   connection banners shown at the same time** (`PaseoShellView.swift:229`, `ChatHeader.swift:177`).
   Hand-rolled navigation in Settings (`PaseoSettingsView` `page` switch: no swipe-back, a refresh
   button on every page). Hardcoded `.font(.system(size:))`, colors, radii and animation literals
   everywhere **(audit A)**.
6. **The folders lie.** `Chat/` holds settings, pairing, shell, history, design tokens and the voice engine;
   `Conversation/` holds the chat. New code lands wherever the last worker looked.

The plan fixes the causes in this order:

1. foundations (design system, observation rules, components);
2. the two surfaces you touch most (shell and conversation);
3. every other screen against the same components;
4. a final consistency sweep.

---

## 1. Rules for this round (added to AGENTS.md for UI work)

These rules are what makes the codebase coherent. Every ticket's review checks them.

**R-1. Observation is narrow.**
- A view reads only what it draws. Stores reach a leaf view as values or as a narrow `@Observable`
  child, never as "the whole session".
- Derived state that costs more than O(1) lives in the store, maintained incrementally, not in a
  computed property read from `body`.
- No `onChange(of:)` on a computed value that scans a collection.

**R-2. Rows are equatable values.** Transcript turns, sidebar rows, history rows and file rows take value
inputs plus one actions object from the environment (`ChatActions`, `SidebarActions`, …), and
conform to `Equatable` so SwiftUI skips them when nothing changed. No closures in row initializers.

**R-3. One owner per gesture surface; finger-tracked motion runs in UIKit.** Anything that tracks a finger across
the screen (the drawers, the panel) is a UIKit container driven by `UIPanGestureRecognizer`. It hands
off to a velocity-matched `UISpringTimingParameters(dampingRatio: 1)` (critically damped, per
UX-SPEC §0.4). SwiftUI hosts the content and learns only open/closed.

**R-4. Tokens only.**
- Colors come from `Palette`, fonts from `Typography` (via the environment), spacing from `Space`,
  radii from `Radius`, animations from `Motion`, feedback from `Haptics`.
- A literal `.font(.system(size:))`, `Color(red:)`, `.cornerRadius(n)` or `.animation(.spring…)` outside
  `DesignSystem/` fails review. The check is a grep in `Tools/style-lint`.

**R-5. Components before screens.** If two screens need the same thing, it is a component in
`DesignSystem/Components/`.

**R-6. No new features in this round.** Behavior changes only where this plan says so. Upstream copy
stays verbatim.

---

## 2. Workstreams

Each workstream becomes one or more tickets with disjoint file sets. IDs are R-round tickets
(`docs/tickets/R*.md`, written from this plan).

### RA. Design system foundation (blocks everything else)

**RA1. `DesignSystem/` module inside PaseoUI.** One folder, one import surface:

- **`Palette`** (rename of `ClaudePalette`; keep a `typealias ClaudePalette = Palette` only for the duration of the
  round).
  - Collapse duplicates:
    - `primaryInk`, `shimmerInk` → `ink`;
    - `secondary` (a non-adaptive gray 0.56) → `secondaryInk`;
    - `sidebarBackground` → `background` (§1.1 says the canvases are equal).
  - Resolve Pure black once: `ClaudeAppearance` publishes it into a static that the app updates
    on change. No `UserDefaults` read inside `UIColor` providers.
  - The OCU palette values stay on branch `ocu-ui`; RA does not change any value. It only
    consolidates.
- **`Typography`**:
  - **Font availability is resolved once.** Use a `static let` for each face; fallback chains are
    computed at registration.
  - **Text scale is environment values**, not `UserDefaults` per call:
    - `\.contentScale` and `\.codeScale` are injected by `RootView` from `@AppStorage`;
    - the sizes are applied with `Font.custom(_:size:relativeTo:)`, so Dynamic Type stays.
    - **Delete `RootView .id(rebuildKey)`**: a font-size or Pure-black change must not reset the shell.
  - **API:** `Font.claude(.body)`, `.claude(.serifTitle)`, … as **named roles**, not sizes:

    | Role | Size and face |
    |---|---|
    | `display` | serif 28 |
    | `title` | serif 20 |
    | `headline` | sans 17 semibold |
    | `body` | sans 17 |
    | `prose` | serif 17 |
    | `callout` | sans 15 |
    | `subhead` | sans 13 medium |
    | `footnote` | sans 13 |
    | `caption` | sans 12 |
    | `mono` | 14 |
    | `monoSmall` | 12 |

  - The roles map to the sizes in use today. The audit's literal-size census (audit A) gives the
    mapping table; any size not in the table is rounded to the nearest role and listed in the ticket's
    final message.
- **`Space`**: 4, 8, 12, 16, 20, 24, 32. **`Radius`**: `chip 8`, `card 12`, `bubble 18`, `sheet 40`, `display 55`
  (the values in use on `foundation`; OCU shape values stay on `ocu-ui`).
- **`Motion`**, the only animation source:

  | Token | Value | Used for |
  |---|---|---|
  | `settle` | `.smooth(0.32)` | surfaces |
  | `disclosure` | `.smooth(0.2)` | expand/collapse |
  | `feedback` | `.easeOut(0.12)` | press states, small fades |
  | `fade` | `.easeOut(0.2)` | |
  | `reveal` | the prose reveal | |
  | `glide` | `.smooth(0.3)` | scroll glides |

  - Every token has a `reduceMotion` variant through `Motion.resolve(_:reduceMotion:)`.
  - The DSH timing constants (`ClaudeMotion`) move here unchanged.
  - `ClaudeMotion.tick` is deleted (unused).
- **`Haptics`** stays; it caches `isEnabled` through a `UserDefaults` observer instead of reading per event.
  The three bypasses go through it (`ComposerQueue.swift:36`, `PaseoTerminalKeyBar.swift:25`, `ConnectView.swift:128`).
- **Token bugs found by audit A** (fix in RA1):
  - `sans()` ignores the content text scale while `serif` / `mono` apply it, so text-size settings
    only half work.
  - The fallback fonts drop the requested size (`.system(style)`).
  - `secondary` (a fixed gray 0.56) has 181 uses and does not adapt to dark mode. All of them map to
    `secondaryInk` (or `tertiaryInk` where the old gray was used for icons; the ticket lists each
    choice).
  - `codeBackground` / `codeSurface` → one `codeSurface`.
  - The terminal's hand-copied colors and `ClaudePaletteWarm.controlActive` (#DD7757) → palette tokens.
  - The diff tints → `Palette.diffAdded` / `diffRemoved`, shared by every diff view and every +N/−N.
  - The `"paseo.appearance"` key is defined twice; `PaseoSettingsKeys` moves to `DesignSystem/`.
- **The inline code style never renders:** `InlineCodeRenderer` (`ClaudeMarkdownView.swift:418`) is never applied
  through `.textRenderer`, so `InlineCodeAttribute` is set but not drawn. Fix it and verify on device
  (backticked text in prose gets the `inlineCodeFill` plate). This is a visible bug.

**RA2. Components** (`DesignSystem/Components/`), each replacing every duplicate the audit found **(audit A §2)**:

| Component | Replaces | Shape |
|---|---|---|
| `ShellHeader` | 3 copies of the menu button + title + trailing button | leading sidebar/back button, center title (optionally a `Menu`), trailing slot; 44 pt glass circles; 48 pt bar |
| `GlassIconButton` | ad-hoc `.glassEffect(in: .circle)` buttons | symbol + a11y label, 44 pt target |
| `SheetScaffold` | `SheetHeader` (26 files), the 5 hand-rolled serif headers, the 44 pt Settings variant, the "Done" / "Close" / "Cancel" dismissals | A `NavigationStack` with a **native iOS 26 toolbar**: `ToolbarItem(placement: .cancellationAction) { Button(role: .close) }` (the system glass xmark), the title through `.navigationTitle` + `.toolbarTitleDisplayMode(.inline)`, and a confirm action as `Button(role: .confirm)` where a sheet commits something. Detents, `presentationBackground(Palette.background)`, the corner radius (one value) and the drag-indicator policy (§RE) all live in this one component. Native swipe-back, Liquid Glass and VoiceOver come for free. **Decision 5** settles where the close button goes. |
| `InlineBanner` | both connection banners, inline errors | icon + text + optional action; `.info` / `.warning` / `.failure` |
| `Toast` + `ToastCenter` | six toast implementations (1.5/2/2.5 s; top 58 / bottom 18 / bottom 96), schedule `showToast` closures | one overlay at the shell root, environment `\.toast`; supports an Undo action (archive undo) |
| `EmptyState` | each screen's own | symbol, title, detail, optional action; calm, centered, `secondaryInk` |
| `LoadingState` | `ProgressView` vs `ClaudeLoader` mixing | `ProgressView` with `.controlSize(.small)` for inline; `ClaudeLoader` only in the transcript |
| `Chip` / `Pill` | model chip, fast chip, filter pills, branch badge | one fill (`Palette.chip`), one height (32), one font |
| `CopyButton` | multiple copy buttons | symbol swap to checkmark for 2 s, haptic `.selection` |
| `ListRow` + `PressableRowStyle` | rows with no pressed state | standard row: leading glyph, title/subtitle, trailing accessory; pressed = `chip` fill with `Motion.feedback` |
| `SectionHeader` | settings and sidebar section labels | one style |
| `PrimaryButton` / `SecondaryButton` (`ButtonStyle`s) | 21 hand-rolled ink capsules, mixed `.bordered` / `.borderedProminent` | ink capsule 44 pt with a pressed state and a built-in progress state (`isWorking`); the secondary is the chip fill |
| `StatusDot` | `ClaudeStatusDot` + `PaseoStatusDot` | one set of states (running / attention / failed / idle / unread) |
| `StatePill` | `VerdictPill`, `StatePill`, `ScheduleStatePill`, … | one capsule, 11 pt medium, tinted fill at 0.14 |
| `DiffStat` | six +N/−N renderers | one view, mono digits, `diffAdded` / `diffRemoved` |
| `AppearancePicker` | the `WelcomeView` and Settings copies | one picker |

**RA3. Folder and naming pass** (pure moves, no code changes). One commit; the Mac gate proves it compiles.

```
PaseoUI/
  DesignSystem/      Palette, Typography, Space, Radius, Motion, Haptics, Components/
  Shell/             ShellContainer (RB), ShellView, ShellHeader use, ConnectionBanner
  Sidebar/           (as now) + CommandCenter
  Conversation/
    Screen/          ChatScreen, ChatController, ChatActions
    Transcript/      Transcript, TurnRow, WorkGroup, Rail, Find, Landing
    Composer/        Composer (one, both modes), Attachments, Mentions, Slash, Queue, Dictation
    Prose/           Markdown, RevealProse, Rich*, FilePathLinks, CodeHighlighter
    Mascot/          Crab, MascotDriver
    Sheets/          controls, context, subagents, background work, turn nav, message text
  Draft/             DraftScreen (uses Composer)
  Workspace/         Panel, Files, Changes, Diff, Terminals, PR
  Settings/          SettingsRoot + pages (NavigationStack)
  History/ Schedules/ Pairing/ Voice/ Notifications/
```

Type names use their folder's noun, not a vendor prefix:
- `ClaudeChatView` → `ChatScreen`;
- `PaseoShellView` → `ShellView`, keeping a public typealias for `App/`.

The `Claude*` prefix stays only where a type mirrors a Claude-app element on purpose (`ClaudeCrab`, `ClaudeLoader`).

**RA4. Dead code removal**, from the audit's unused list **(audit A §4)**. Each deletion is verified with a whole-repo
grep, including `App/`:
- `ClaudeMotion.tick` / `.roll`;
- `sidebarBackground`;
- `ClaudeMediaPlaceholder` / `ClaudeVideoFileCard` / `ClaudeVideoFileViewer`;
- `HostColor` / `HostBadgeDisplay` / `HostAppearance` and their persistence (the removed sidebar badge);
- `PairingConnectOutcome`;
- `WorkspaceBaseBranchRow`.

`ClaudeMediaState` is test-only: delete it with its test only if nothing in UI uses it.
`InlineCodeRenderer` is **not** dead; it gets wired (RA1).

**RA5. `Tools/style-lint`**, a grep script listing the token violations of R-4 per file. Run before merge; the
count must only go down. It ends at zero outside `DesignSystem/`.

### RB. Shell: a UIKit drawer container (smoothness #1)

Replace the SwiftUI gesture shell with `ShellContainerController: UIViewController`. It hosts three
`UIHostingController`s (sidebar, conversation, panel) and is wrapped by a
`UIViewControllerRepresentable`.

- **Gestures:**
  - One `UIPanGestureRecognizer` on the conversation view.
    - `gestureRecognizerShouldBegin` checks velocity: horizontal-dominant only, and in the right
      direction for the current state.
    - It also checks the hit view: it never begins when the touch lands inside a
      horizontally-scrollable `UIScrollView` (code blocks, diffs, tables), or inside a `UITextView`
      with a selection.
  - The sidebar opens from a **full-width rightward pan** on the conversation, as Claude iOS does, not
    only the 24 pt edge. A rightward swipe in a chat has no other meaning. The left
    `UIScreenEdgePanGestureRecognizer` stays as the guaranteed path.
  - The panel opens from a trailing edge pan (24 pt) and closes like `UINavigationController`'s
    interactive pop: an edge pan, or a horizontal pan anywhere that doesn't start in horizontally
    scrolling content.
  - The transcript's vertical pan and ours: `shouldRecognizeSimultaneously` = false. Ours fails fast
    on vertical intent; the scroll view requires nothing of ours.
- **Motion:**
  - During the pan, set `transform` / `frame.origin.x` on the hosting views' layers directly, plus the
    dim view's `alpha` and the hairline layer's `opacity`. **Zero SwiftUI invalidation per frame.**
  - On release:
    - project with UIKit's deceleration (`velocity * 0.998 / (1 - 0.998)` / 1000);
    - decide open/closed;
    - animate with `UIViewPropertyAnimator(duration: 0.32 or computed,
      timingParameters: UISpringTimingParameters(dampingRatio: 1, initialVelocity: v / remaining))`.
  - The release velocity carries into the settle, with no speed jump. The animator is interruptible:
    a touch mid-settle grabs the surface where it is (`pauseAnimation`, read `fractionComplete`).
- **Material:**
  - Corner radius: the display radius (`UIScreen.main.displayCornerRadius` is private, so keep 55
    via the constant).
  - Use `cornerCurve = .continuous` and `layer.cornerRadius` + `masksToBounds` on the conversation
    and panel containers, which is cheaper than a SwiftUI clip shape per frame.
  - The dim is one `UIView` with a black background, alpha `0.25 / 0.55 × progress`, and its tap closes.
  - The hairline is a `CAShapeLayer` stroke, 0.5 pt, `ink 10 %`.
  - Reduce Motion: a 0.2 s ease-out, no spring.
- **SwiftUI side:**
  - `ShellView` provides the three content views and receives `isSidebarOpen` / `isPanelOpen` as
    plain booleans, for accessibility and pausing.
  - Pause the crab, the status sweep and the work-group sweep while a drawer is open or in motion.
    Pass `\.isSurfaceObscured` in the environment; the views gate their `TimelineView` with
    `.paused(isObscured)`.
- **Accessibility:** when a drawer is open the covered surface gets `accessibilityElementsHidden`, the
  scrim is an accessibility "Close" button, and the escape gesture (two-finger Z) closes.
- **Haptics:** `.selection` once per open/close commit, as now. `prepare()` fires on pan begin.
- **Kept behavior:**
  - every UX-SPEC §1 rule (constant corner, full bleed, parallax 0.3, dim inside the shape,
    one settle);
  - the panel mounts its pages only while visible (P5-D);
  - the panel identity per workspace.
- **Deleted:** `EdgeDrawerDrag`, `ConversationCard`, `PanelCard`, `PanelDismissDrag`,
  `withPanelDismiss`, `PanelVisibilityTracker`. The container calls `onVisibilityChange`.
- **Mac:** the container only works with touch. On Mac (later) the same container
  lays out the sidebar as a fixed column. Not in this round; no `#if` beyond what compiles.

Risk: **high**, Apple-API-heavy, so it goes to DeepSeek. The acceptance list is in §4.

### RC. Conversation: split the god view (responsiveness #1)

**RC1. `ChatController` (`@Observable @MainActor final class`, one per open agent).** It holds every
non-visual state now in `ClaudeChatView`'s 60 `@State`s:

- find state;
- follow and anchor state;
- pending rewind and message actions;
- slash commands;
- the mention index;
- dictation and the voice engine;
- the queue;
- attachments;
- the toast route.

The screen owns one `@State var controller`. Views read only the controller properties they draw.

**RC2. Screen = small views with narrow reads.** `ChatScreen` body: `ShellHeader`, `ChatFindBar?`,
`Transcript`, `SubagentPill`, `Composer`. Each is a separate `View` struct taking the store and the
controller. Nothing in `ChatScreen.body` reads `store.draft`, `store.turns`, `store.timeline` or
`session.agents`.

**RC3. Mascot driver out of the view.** `MascotDriver` (a class) subscribes to the store with
`withObservationTracking`, or receives explicit events from `ConversationStore`. Its inputs are
maintained incrementally in **PaseoStore** (new O(1) counters on `TimelineState`, updated in the
reducer):

- `failedToolCallIds` (append-only, with seq);
- `runningSubAgentCount`;
- `lastCompactionStatus`;
- `latestRowKind`.

`HostSession` exposes `runningAgentCount`, `pendingPermissionCount` and `attentionCount`, maintained on
agent updates. The four O(rows) scans and three O(agents) scans in `ChatMascot.swift` go away.
PaseoCore unit tests cover the counters, including prepend of older pages (must not count as live)
and epoch reset.

**RC4. Transcript rows are equatable.**

- **`ChatActions`** is a final class in the environment. It carries `openFile`, `rewind`, `edit`,
  `rerun`, `fork`, `forkInFlight`, `deleteTurn`, `retract` and `markdown`, plus the capability flags
  (`canFork`, `canRewrite`, `rewindChoices`). These are stable for the screen's life.
- **`TurnRow`** takes only `turn`, `isLatest`, `highlightedSeq` (only when it targets this
  turn, else nil) and `isLanding`. It is `Equatable`, using `Turn: Equatable` plus the version
  counter P5-A added. It gets `.equatable()`.
- `ForEach(store.turns)`, no `Array(enumerated())`; "is latest" is `turn.id == store.turns.last?.id`,
  computed once.
- **Result:** a streamed token re-renders exactly one turn row.

**RC5. Following the tail without fighting the user.**

- **Replaced:** the per-commit `onChange(of: store.turns.last) { withAnimation { scrollTo("bottom") } }`.
- **Following:** `.defaultScrollAnchor(.bottom, for: .sizeChanges)` (iOS 18) keeps the bottom pinned
  while content grows: no animation, no per-token `scrollTo`.
- **Not following** (the user scrolled up more than ⅓ screen): switch the size-change anchor to `.top`
  (via state) so the reader's position never moves.
- **Back to end:** one `.smooth(0.3)` `scrollTo`.
- **Send anchor (M7d):** a single `scrollTo(id, anchor: .top)` with `Motion.glide`, then the
  size-change anchor goes to `.top` until the answer overflows, then back to `.bottom`.
- `onScrollGeometryChange` does only O(1) work. The reading-position and rail-reveal updates move to
  `onScrollPhaseChange` plus a coalesced readout (at most 30 Hz) instead of running on every
  geometry frame.

**RC6. One composer.**

- `Composer` is one view with two modes: `.draft`, the pill↔card of UX-SPEC §4.1, and
  `.conversation`, always the card.
- `DraftChatView` uses it; its own `TextField` card is deleted. Mode-specific chips are inputs.
- The text field binds to a `ComposerModel` text property that lives in the controller, not on
  `ConversationStore`. It syncs to `store.draft` (persistence, mention/slash detection) through the
  existing debounce. **A keystroke re-renders only the `Composer` subtree.**
- **Send-button enablement and the expand control:** cheap `Bool`s maintained by `ComposerModel` on
  text change (`isEmpty`, `isTall` by newline count plus a length heuristic). No trimming of the
  whole draft in `body`.

**RC7. One connection banner.** It lives in `ShellView`, above whichever surface is shown (chat or
draft), from `session.connection`. Delete `ChatHeader.connectionBanner`.

Wording, using the existing strings, no new copy:
- "Reconnecting…" with a small spinner;
- after `.failed`: "Can't reach the host. Check that the daemon is running." plus Disconnect.

**RC8. Prose and rich content (perf batch H plus the open audit leftovers).**

- `ClaudeCodeHighlighter` runs off the main actor: a dedicated actor owns the JSContext. The cache
  key is `(theme, language, hash(source), count)`, and highlighting happens only once a block mounts.
  The first paint is plain mono; the highlighted text swaps in without a size change.
- **SVG and `visualize`:**
  - **SVG:** one shared, offscreen `WKWebView` renders to a snapshot image (`takeSnapshot`), cached
    by content hash. The chat shows the image; tap opens the live web view in a sheet.
  - **HTML:** the card keeps a live `WKWebView`, but only while on screen. Off screen it becomes the
    snapshot, so at most two live web views exist at once.
- Local and remote images decode and downscale off main (`CGImageSource` thumbnail at display size,
  cached). `LPLinkView` metadata is fetched only on appear and cached by URL (it is today; check).

**RC9. Status line and crab.** The crab's `TimelineView` and the sweeps already run at 30 Hz or sleep
(P6-F). Add `.paused` when obscured (RB) and when `scenePhase != .active`.

**RC10. Main-thread decode fixes (audit B N7, N8).**

- **Attach pipeline:** decode, resize to 2048 px and JPEG-encode in a detached task. The tray shows a
  placeholder tile with a spinner until the image is ready.
- **Inline image loader:** it gets its own read path. A `WorkspaceFiles.readBytes(path)` call returns
  the data instead of writing the shared `files.read` state, which today makes concurrent images
  overwrite each other. Decode and downscale off main, and cache by `(workspace, path, mtime)`. This
  is a correctness fix as well as a perf fix.
- `ChatTranscript.boundaryBefore` (O(rows) per visible turn, audit B N2) → `TimelineState` keeps a
  `rowIndex(forSeq:)` dictionary, maintained by the reducer. Lookup is O(1).

### RD. Workspace panel (perf batch E plus coherence)

- **Quadratic diff first (audit B N3):** `model` is a computed property read per row (`model.totalWidth` in
  `lineRow`). Make the model a stored value built once per input, and pass `totalWidth` into rows.
  Draft anchors are grouped once per render into `[lineKey: [Draft]]`.
- **File viewer (audit B N4):**
  - decode and highlight off main into a cached `FileRenderModel`;
  - the text renders as a `LazyVStack` of line rows (gutter plus text per row) once a file exceeds
    500 lines; smaller files keep the single selectable `Text`;
  - "Select all / Copy" goes through the model, not a re-decode.
- **Changes page lists (N9) are lazy**, and the per-file overlay menu becomes a per-row context menu.
- **Formatters (N10):** one shared `PaseoFormat.relative(_:)` and `PaseoFormat.date(_:)` (static
  formatters), used everywhere a row formats a date.
- **Diffs (E):** `LazyVStack` rows. `DiffModel` / `SideBySideModel` are memoized per
  `(file.id, file.revision, hideWhitespace, wrap)` in a small cache owned by the Changes page and
  built off main for files over 1,000 lines, with a spinner row meanwhile. Hunks over 400 lines
  start collapsed with "Show N more lines". Line rows are plain `Text`s; the row `Button` goes and a
  single tap handler on the row selects it. `.textSelection` only in the expanded single-line sheet.
- `ClaudeDiffView` in tool details: the same lazy rows and memoized parse. `diffStat` is computed
  once in the model, not per body (finding #15).
- **Panel header:**
  - built from `ShellHeader`: a `chevron.left` back, the workspace name, and a trailing menu
    (actions currently scattered across pages);
  - the tabs are one segmented control (system `Picker(.segmented)`, tinted ink) with the UX-SPEC §0.3
    symbols;
  - the remembered tab and scroll per workspace stay.
- **Files, Changes and Terminals pages:** `ListRow`, `EmptyState` and `LoadingState` everywhere.
  Toolbars become a single trailing menu per page. Pull-to-refresh (`.refreshable`) is added on Files and Changes;
  the page refresh buttons are deleted.

### RE. Settings, sheets and secondary screens (perf batch I plus Apple navigation)

- **Settings becomes a real `NavigationStack`** with `navigationDestination(for: SettingsPage.self)`:
  - swipe-back works;
  - pages nest (Providers → provider; Projects → project);
  - the large-title root collapses to an inline title on scroll, as in the Claude app.
- **Page look:** pages use `List` with `.insetGrouped` styling, restyled to the palette
  (`listRowBackground(Palette.panel)`, `scrollContentBackground(.hidden)`).
- **Refresh:** a refresh button appears only on pages that load remote state, as `.refreshable`.
- **Split** `PaseoSettingsView.swift` (1,913 lines) into one file per page under `Settings/`.
- **Every sheet goes through `SheetScaffold`.** The audit's sheet census **(audit A §5)** lists each
  sheet's current detents and indicator. The new policy:
  - full-height task sheets (Settings, History, Schedules, Search): `.large`, drag indicator
    hidden, `SheetHeader`;
  - pickers and quick actions (controls sheet, context sheet, message text, branch switcher):
    `.medium` + `.large`, indicator visible, header with close;
  - confirmation: `confirmationDialog` only. `.alert` is only for text input (rename).
- **History and Command Center (finding #16/#17):**
  - groups precomputed once per input change, in a small `@Observable` model;
  - one cached `RelativeDateTimeFormatter`;
  - search is debounced at 120 ms and filters precomputed lowercase keys.

### RH. Interaction grammar (one way to do each thing)

The rules every screen follows. The lead decides them here; audit C lists where the code deviates.

- **Objects** (agent, workspace, project, schedule, terminal, file, history entry) answer the same
  three ways:
  1. **Tap** opens the object.
  2. **Long-press** shows a context menu. The verbs are always in the same order:
     - Open-variants (Open, Open in panel);
     - edit verbs (Rename, Pin/Unpin, Mark as unread, Labels…);
     - copy verbs (Copy ID / Copy path);
     - a divider, then the destructive verb (Archive / Delete / Close), `role: .destructive`.
  3. **Swipe** exists only where the container is a `List` (History, Settings lists, Schedules),
     with the same mapping everywhere: trailing = the destructive verb (no full swipe), leading = Pin
     or Mark unread. The sidebar (a lazy stack under a moving card) uses long-press only. Swipe
     there would fight the drawer.
- **Destructive verbs:** undo if the daemon supports it (a toast with Undo, 4 s), else a
  `confirmationDialog` naming the object. Never both.
- **Every object's menu in the header** (the agent title menu) shows the same verbs as its row's
  context menu, in the same order.
- **Refresh:** `.refreshable` on lists that show remote state; no refresh buttons in toolbars.
- **Async actions:** the control shows its own progress (`PrimaryButton(isWorking:)`), and the
  result is a toast only when the change isn't visible on screen.
- **Haptics:** one per user intent.

  | Haptic | Used for |
  |---|---|
  | `.selection` | toggles, picks, drawer commits |
  | `.send` | send |
  | `.success` / `.failure` | async results the user waited for |
  | `.settle` | a turn finished while visible |

  Never haptics on appearance, and never two for one action.
- **Keyboard:**
  - return sends only where the composer setting says so;
  - every sheet with a single text field focuses it on appear;
  - scroll dismisses interactively everywhere.

### RI. Flow fixes (audit C top 25, resolved)

Each item is the lead's decision. The number is audit C's rank.

**Shell and panel**
1. **The panel follows the screen's workspace**, the draft's included. `ShellView` keeps
   `currentWorkspaceId = conversation?.agent?.workspaceId ?? draft?.workspaceId`; the panel and
   Mention in chat both use it. Mention in chat inserts into the draft's text.
2. **One banner** (RC7).
4. **Panel dismissal:** RB's hit-test rule fixes it (no dismissal pan starting inside horizontally
   scrolling content). Files becomes a real `NavigationStack` (folder push, swipe-back); while the
   Files stack is deeper than its root, the edge swipe means "back", not "close panel".

**Naming, entry points and hosts**

3. **Hosts live in Settings → Hosts**, and that is the only place:
   - the current host gets a checkmark, and tapping another host switches to it;
   - the last row is "Add host" (the existing `AddHostMethodsSheet`);
   - the Connections page merges into Hosts (one list of saved endpoints);
   - "Remove host" lives only in each host's detail page (swipe on the row = Remove, with a
     confirmation);
   - Search keeps "Switch host…", which opens the same page.
5. **One name: "New session"** (the user's approved wording) for every draft entry point. Upstream's
   "New agent" stays only where it labels an upstream concept that isn't the draft.
6. **Tapping a workspace with no agents opens a draft in it**, everywhere. The toast goes.
9. **Features never become unreachable.** Search always lists History, Schedules and Usage as
   actions, and the Settings → Sidebar toggles only hide the sidebar rows. Usage needs one switch.

**Settings and data safety**

7. **No app reset** for a text-size or appearance change (RA1).
10. Settings and Schedules become `NavigationStack`s (RE); back goes to the parent.
11. **Unsaved edits:** schedule editor, file editor, commit, Create PR, new workspace and project
    settings set `interactiveDismissDisabled(isDirty)`, and their back/close asks
    `confirmationDialog("Discard changes?")` (the existing "Discard changes…" wording family) when
    dirty.
18. **Remove project** lives in the sidebar project menu and in the project page. Both use one
    `ProjectActions.remove` with the same confirmation and the same toast. The sidebar project menu gains
    "Project settings…", and the Settings → Projects list links to the same page.
19. Merged into item 3.

**Toasts and destructive actions**

8. **Toasts go through `ToastCenter`** at the shell root, above sheets: one overlay window level
   (`UIWindow` at `.alert + 1`, or the top-most presented controller), so a toast from a sheet is
   visible.
12. **Archiving an agent is the same everywhere:**
    - it confirms only while the agent is running ("This agent is still running. Archiving it will
      stop the agent.");
    - otherwise it archives at once and offers **Undo** in a toast when the daemon supports
      unarchive (`refresh_agent_request` unarchives; History uses it already);
    - the verb is always destructive-styled.
13. Swipe actions follow RH; schedule rows gain the context menu (Pause/Resume, Run now, Edit,
    Delete).
16. **VoiceOver:**
    - the covered surface is hidden from accessibility;
    - the scrim is a button;
    - `accessibilityAction(.escape)` closes drawers and sheets;
    - `ToastCenter` posts `UIAccessibility.post(.announcement)`.
17. **Haptics:** the row tap that also settles a drawer fires only the settle's haptic. The rule
    is "the shell owns the haptic when it moves a surface".

**Copy and feedback**

20. **Jargon:**
    - "Copy agent ID" stays in the header menu and History only, both with the same toast;
    - permission and feature-flag names become plain sentences (the ticket lists each
      replacement for the lead's sign-off, with no invented upstream copy);
    - "Unsupported item: x" is hidden in release builds;
    - "host" is the user-facing noun and "daemon" only appears in troubleshooting text.
21. **Wrong copy fixed:**
    - the rename message drops the claim about the sidebar;
    - the pull-to-refresh hint becomes true once `.refreshable` exists;
    - the composer placeholder is one string in both modes, upstream's.
22. **Every error gets a Retry:** `InlineBanner(.failure, action: "Try again")` on the transcript load and the sidebar
    directory, plus pull-to-refresh on the sidebar.
23. Covered by item 20.
24. **Subagents:** "Archive finished" becomes **"Hide finished"**, not destructive and not confirmed.
    It is app-side; it says what it does.
25. **Opening an archived agent** shows the row's progress while it unarchives, then opens it. A failure
    shows a toast.

**Smaller items from the same audit**
- **Find bar:** Return goes to the next match and ⇧Return to the previous one.
- **Hardware keyboard:**
  - ⌘↩ sends;
  - ⌘K opens Search;
  - ⌘N opens New session;
  - ⌘F opens Find;
  - Esc closes the top-most sheet or drawer.

  These cost little and serve the Mac later.
- **Terminal close:** always confirms while a process runs, never otherwise (unchanged, documented).
- **The rail's touch strip** is live only while the rail is visible. While it is visible, the panel edge pan
  yields to it.
- **An agent with no turns** shows a quiet `EmptyState` ("No messages yet"), not the new-session greeting.
- **The composer cursor** becomes ink (§0.1).
- **Side-by-side diff** is unreachable on a portrait iPhone. Remove the option and its code paths now;
  the Mac round can bring it back.
- **Tap targets:** every control listed in audit C §6 gets a 44 pt hit area (`contentShape` +
  frame), with the visuals unchanged.

### RF. Launch and state coverage (batch J plus polish)

- **Launch:**
  - `AppModel.init` creates the session and returns. The connect starts in `.task` on the root,
    so the first frame is the shell skeleton (sidebar canvas plus an empty chat), not a blank view.
  - The panel's work starts on the first open (it does after P5-D; verify).
  - Fonts register on a background queue before the first frame (`CTFontManagerRegisterFontsForURL`
    is thread-safe).
- **State coverage matrix** (filled from **audit C §3**): every screen has loading, empty, error and
  offline states built from `LoadingState` / `EmptyState` / `InlineBanner`. Fill the missing ones.
- **Feedback pass:**
  - every tappable thing has a pressed state (`PressableRowStyle` / the system button styles);
  - every destructive action has a confirmation or an undo toast (archive already has undo);
  - every async action shows progress on the control itself (a spinner replaces the label);
  - no double haptics (audit C §4).
- **Copy pass:** sentence case everywhere (the Claude app style), upstream wording kept, developer
  jargon removed from user-facing text (list from audit C §5). Changes stay in the copy that is ours,
  never in upstream strings.
- **Accessibility pass:** labels on icon-only buttons, 44 pt targets, Dynamic Type for every font
  (through `Typography` roles), Reduce Motion through `Motion.resolve` (audit C §6).

### RG. Core support (PaseoCore, Linux-testable; can start first)

- `TimelineState` counters for RC3, with tests.
- `HostSession` aggregate counters (`runningAgentCount`, `pendingPermissionCount`, `attentionCount`)
  and a cheap `agentsVersion`, so views observe a number rather than the array.
- **Event fan-out (audit B N6):**
  - one shared `JSONDecoder` per handler type;
  - route by message `type` through a dictionary of handlers instead of offering every event to
    ~7 handlers and every conversation twice;
  - agent upserts insert in sorted position with a pre-parsed `activityDate` on the snapshot. No
    full re-sort, and no `agents` assignment when nothing changed (`HostSession.swift:431-476`).
- **`RootView` (N5):** the attention-delivery observer moves into a tiny modifier view, so the root
  and the shell don't re-render on attention changes.
- **Polling:** the schedules list's 5 s poll pauses when the app is inactive and when the page is
  not visible. Prefer the daemon's push if one exists; check `Schedules.swift`.
- **`ClaudeLoader` (N11):** capped to 30 Hz, and paused with the status line when the surface is
  obscured.
- `Turn` stays `Equatable`. Add `Turn.contentVersion` if P5-A's row versions don't already give a
  cheap equality (check `IncrementalTurnBuilder`).
- **`OSSignposter` intervals** (PaseoCore and PaseoUI) at: stream commit, turn rebuild, markdown
  parse, diff model build, drawer settle. The user can then profile a device run in Instruments
  without code changes. The signposts cost nothing when not recording.

---

## 3. Order, owners, parallelism

Ordered so that tickets touching many files run alone and screen work runs in parallel on
disjoint folders. Each row is one ticket in `docs/tickets/R*.md`.

| Wave | Ticket | Scope | Runs | Worker |
|---|---|---|---|---|
| 1 | **R1 Moves** (RA3 + RA4) | folder/naming `git mv`, dead code deletion; no logic | alone | DeepSeek |
| 2 | **R2 Tokens** (RA1 + RA5) | `DesignSystem/` tokens, typography environment, delete `.id(rebuildKey)`, mechanical font/color/radius/motion replacement in every file, style-lint, the inline-code renderer fix | alone (touches every file) | DeepSeek |
| 2 | **R3 Core** (RG) | PaseoCore counters, row index, event routing, sorted upserts, signposts; tests | parallel with R2 (PaseoCore only) | DeepSeek or LongCat |
| 3 | **R4 Components** (RA2) | `DesignSystem/Components/`; adopted only in small files the screen tickets don't own (sheets, pickers, settings rows) | alone | DeepSeek |
| 4 | **R5 Shell** (RB + RI 1, 2, 4, 16, 17) | `Shell/`, the drawer container, one banner, panel workspace from the draft | parallel | DeepSeek (Apple-API-heavy) |
| 4 | **R6 Conversation** (RC1–RC7, RC10, RI 21, 22, Find/⌘ keys, the rail strip, empty agent) | `Conversation/` minus `Prose/`, `Draft/` | parallel | DeepSeek |
| 4 | **R7 Workspace** (RD + RI 4 (Files stack), 11 (file editor, commit, PR), tap targets) | `Workspace/` | parallel | DeepSeek |
| 4 | **R8 Settings and sheets** (RE + RI 3, 9, 10, 11 (schedules, project), 18, 19, 20) | `Settings/`, `Schedules/`, `History/`, `Sidebar/CommandCenter*`, `Pairing/` | parallel | DeepSeek |
| 5 | **R9 Prose and rich** (RC8, RC9) | `Conversation/Prose/`, `Rich/`, highlighter | parallel | DeepSeek |
| 5 | **R10 Sidebar** (RH swipe/menu grammar, RI 5, 6, 8 (toasts), 12, 13, 24, 25, pull-to-refresh) | `Sidebar/` minus CommandCenter | parallel | DeepSeek |
| 6 | **R11 Sweep** (RF + RH audit) | launch, state matrix, copy, a11y, haptics, lint to 0 | alone, last | DeepSeek, then the lead's full review |

- **Waves 1–3 are short and mechanical,** but they decide whether the rest is coherent: screen tickets
  adopt the components instead of inventing new ones.
- **Waves 4–5 run up to four workers at once** on disjoint folders. Shared files (`Shell/ShellView` for
  routing callbacks) are owned by R5; any other ticket that needs a shell hook names it in its final
  message instead of editing.
- **Every R-ticket in waves 4–6 also brings its folder to zero style-lint findings.**
- **Peak hours:** today is a weekday, so new DeepSeek runs avoid 01–04 and 06–10 UTC. LongCat
  (`pi/opencode-go/longcat-2.5-free`) is the fallback for R1, R3 and R11's copy list (mechanical or
  Linux-testable), with a DeepSeek review pass.
- **Review cadence:** the lead reviews every diff against §1. Then the Mac gate, PaseoCore tests and the
  merge. One IPA per wave once the user is home.

**Per-ticket gate:**
1. the Mac gate `build` is green;
2. PaseoCore `swift build --build-tests && swift test` is green;
3. the style-lint count does not rise;
4. the lead reviews the diff against R-1…R-6;
5. merge.

---

## 4. Acceptance (device checklist the user runs at home)

The lead cannot run the app. These checks need the user's device; each ticket lists which ones it owns.

**Smoothness**
1. Drag the sidebar open slowly, then flick: the card stays under the finger with no lag, and the
   flick carries its speed into the settle (no slow-down, no overshoot).
2. Start a flick and catch the card mid-settle: it stops under the finger.
3. Vertical scrolling in the transcript never moves a drawer. A horizontal swipe on a code block
   scrolls the code, not the drawer.
4. While an answer streams, scroll up a few lines: the text you're reading does not move. Scroll back
   to the bottom: following resumes. No jitter while following.
5. The panel opens from the right edge and closes by swiping anywhere on Files/Agents, but a swipe
   on a diff scrolls the diff.

**Responsiveness**
6. Type fast in a long conversation while an answer streams: no dropped or late characters.
7. Opening a conversation with 500+ turns shows the bottom immediately. Jumping through the rail stays smooth.
8. Open a 3,000-line diff: the first rows show at once and scrolling is smooth.
9. Cold launch: the shell shows in under a second, before the connection finishes.

**Coherence**
10. Every sheet has the same header (title leading, close trailing) and dismisses the same way.
11. Settings: swipe back works on every page; nothing has a refresh button it doesn't need.
12. Disconnect the Mac: exactly one banner appears.
13. Changing the content text size applies live and keeps the open conversation and scroll position.
14. Pure black switch: applies live, with no reset.

**Instruments (optional, with the user):** the signposts (§RG) show stream commit at least 4 ms
apart, and no main-thread markdown parse over 8 ms on the M-size test chat.

---

## 5. Decisions for the user

The lead's recommendation comes first. Everything else in this plan is the lead's call.

1. **Sidebar opens on a full-width right swipe** (Claude iOS), not only from the 24 pt edge.
   Recommend: yes.
2. **OCU branch:** fold the approved OCU groups into RA1 (values) once you've tried `ocu-ui`, so the
   token consolidation and the value change land together. Recommend: decide per group at home; RA1
   proceeds value-neutral meanwhile.
3. **Settings as a native inset-grouped list** (Claude iOS settings look) instead of the custom
   card pages. Recommend: yes.
4. **Rich SVG as a snapshot, live on tap.** Recommend: yes; the memory win is large.
5. **Sheet close button position.** UX-SPEC §0.3 says "title leading, close trailing". The code's
   `SheetHeader` (26 files) does the opposite: a centered title with the xmark leading, which is
   Apple's iOS 26 convention (system sheets put the glass xmark leading and confirm trailing).
   Recommend: **follow iOS 26** (leading xmark through `Button(role: .close)`, centered inline title,
   trailing confirm) and amend UX-SPEC §0.3. Native toolbars place the buttons themselves, so
   fighting them costs custom headers everywhere.
6. **User bubble size.** The bubble is 14 pt (DSH web metrics) while V5 set the chat body at 17 pt
   (Claude iOS). Recommend: **17 pt**, matching the composer and the prose, as the Claude app does.
   It's one constant in R2.
7. **Hosts in one place** (RI 3): Settings → Hosts lists, switches, adds and removes; the separate
   Connections page goes. Recommend: yes.

## 6. What this plan deliberately does not do

- No new features and no parity work. PARITY gaps wait for the next round.
- No palette or shape value changes beyond decisions 2 and 6. The `ocu-ui` branch stays the place
  to try values.
- No Mac layout. Only the keyboard shortcuts, which iPhone hardware keyboards use too.
- No backend changes. Everything uses the existing daemon protocol.
