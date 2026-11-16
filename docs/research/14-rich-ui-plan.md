# 14 — Rich native UI: cards, media, widgets, Live Activities

Status: plan, 2026-11-11. Author: UX research pass (no code changed).
Reader: the lead, who turns §5 into tickets. Read `AGENTS.md` (R-1…R-6), `ARCHITECTURE.md`,
`docs/research/05-rich-media-spec.md` and `docs/tickets/E3-content.md` first.

**Scope boundary with E3.** E3 (`docs/tickets/E3-content.md` §3) makes today's blocks correct:
SVG at its intrinsic ratio, HTML card height that follows content up to 70 % of the screen, the Files
panel HTML preview with scripts, YouTube that plays in place, and a pass over image/video/audio
blocks. This plan assumes E3 has merged. It doesn't redo any of that. It builds the card family,
the media pipeline and viewer, the new card kinds, and the system surfaces on top.

**The verdict in one paragraph.** Paseo is a remote control for agents on your own machine. Its
two jobs are reading what an agent made and noticing when an agent needs you. So the rich UI
budget goes to five things, in this order:
1. one coherent card family with a real image pipeline and a full-screen viewer;
2. the artifact kinds coding agents actually emit: Mermaid, HTML/SVG artifacts, screenshots,
   diffs, terminal output, PRs;
3. a Home Screen / Lock Screen "agents" glance;
4. Controls, Shortcuts and Spotlight for getting in fast;
5. a Live Activity, but only if it can stay truthful without a push server (a spike decides).

Weather-style cards, generative forms, map expansion and approve buttons on the Lock Screen are
rejected (§6).

---

## 1. Principles

### 1.1 One card family

Every rich block in the transcript is a `PaseoCard`. It's a new DesignSystem component in
`DesignSystem/Components/PaseoCard.swift` (R-5) that replaces the private `RichCard` in
`Conversation/Prose/Rich/ClaudeRichBlocks.swift:11`. Cards differ in their slots, never in their
chrome.

```
┌──────────────────────────────────────────────┐  container: Palette.panel, 0.5 pt Palette.cardBorder,
│ [media slot — edge to edge, clipped to card] │  Radius.md (12) continuous, full prose column width
│                                              │
├──────────────────────────────────────────────┤
│ ◇ Title (1–2 lines)              accessory ⌄ │  header: 16 pt SF Symbol or favicon (Palette.secondaryInk),
│   meta · meta                                │  title Typography.callout sans .medium, meta .caption
└──────────────────────────────────────────────┘  secondaryInk; padding Space.md; gap Space.sm
```

- **Two layouts only.**
  - *Media card*: the media slot sits on top, edge to edge, and a metadata strip goes below
    (image, video, YouTube, link with a hero image, Mermaid, artifact).
  - *Row card*: no media slot, 56 pt min height, glyph + title + meta + trailing accessory (file,
    audio, PR, changes, link without an image).
  - Nothing else. No nested cards, no shadows, no gradients, no tinted backgrounds. Status color
    lives only in a `StatusDot` or `StatePill`.
- **Prose vs chrome type.** Prose stays serif; card chrome is sans (`Typography` `.callout`,
  `.footnote`, `.caption`); code and paths in cards are `.codeSmall`. This keeps the card quiet next
  to the serif transcript, the way Claude's app frames artifacts.
- **Spacing.** A card is its own paragraph. It gets the prose paragraph spacing above and below
  (no extra margins), and it never sits inside a list item. Doc 05's own-paragraph rule holds.
- **Accessory slot.** Either a duration/size badge (`.caption` monospaced digits), a chevron for
  "opens something", or nothing. The overflow menu is a long-press, not a visible button.
  Exception: the artifact card keeps its "View source" capsule, which exists today.

### 1.2 Interactions (identical for every card)

- **Tap.** Does the card's primary action: open the full-screen viewer, play, open the artifact
  page, open the diff, open the file.
  - Press feedback: `scaleEffect(0.98)` + `Motion.feedback`.
  - No haptic on tap (the haptics policy in `DesignSystem/Haptics.swift`: none on navigation).
- **Long-press.** `.contextMenu(menuItems:preview:)` with a live preview of the media.
  - `Haptics.selection()` fires when the menu appears.
  - Items, in this order, only when they apply:
    - Open;
    - Share;
    - Copy (link, image or text);
    - Save to Photos (images and video);
    - Open in Safari, or Open in YouTube;
    - View source (web kinds);
    - Show in Files (local paths → workspace file viewer).
- **Full screen.** Media opens with the iOS 18+ zoom transition
  (`matchedTransitionSource` + `.navigationTransition(.zoom)`) from the exact thumbnail. Under
  Reduce Motion that becomes a `Motion.fade` crossfade.
- **Actions reach the card from the environment.** A single `RichActions` object (open viewer,
  open file, open diff, share, add to chat) is injected once; cards take only values (R-2). No
  closures in card initializers.

### 1.3 Sizes and no layout jumps

- **Width** is the prose column width, read once per transcript with `onGeometryChange`, not a
  `GeometryReader` per card.
- **The media slot height** is decided before any pixel arrives:
  1. Known size: from detector or metadata (SVG `viewBox`, a cached image size, video track size,
     YouTube = 16:9, Mermaid's rendered size). Use it.
  2. Unknown remote image: reserve 4:3 at full width. When the header bytes arrive (ImageIO reads
     the size from the first few KB, see §4.1), animate once to the true ratio with
     `Motion.disclosure`.
  3. The size goes into `MediaMetadataCache` (keyed by URL or path) so the card never animates
     twice, even after scrolling away and back.
  4. Clamp the height to `[120 pt, 60 % of screen height]` and the ratio to `[0.5, 3.0]`. Outside
     that range, letterbox inside the slot on `Palette.codeSurface`.
- **Loading.** The reserved slot is filled with `Palette.codeSurface`, with the shared skeleton
  shimmer from `LoadingState`. A spinner only appears after 300 ms. There's never an empty
  zero-height card.
- **Error.** The slot keeps its reserved size, so nothing collapses. It shows a centered SF Symbol
  plus the alt text (doc 05 §1.3: alt text replaces the image) or the upstream error string, and
  "Try again" (upstream copy) when a retry makes sense.
- **Empty.** Never render a card for empty content. The detector doesn't emit blocks with empty
  bodies.

### 1.4 Motion

Every animation goes through `Motion.resolved(reduceMotion:)`:
- the content swap (thumbnail → player, placeholder → image) is `Motion.fade`;
- a one-time size settle is `Motion.disclosure`;
- the full-screen enter and exit are the system zoom transition, or `.settle` for the UIKit
  viewer's own spring.

Streaming text must never re-run a card's entrance. Cards get stable ids from
`(turnId, block range start, kind)`.

### 1.5 Accessibility

- Every card is one accessibility element: label = kind + title + meta (for example "Image,
  screenshot.png"). Menu items become `accessibilityCustomActions`.
- Images use the author's alt text, else the file name. Decorative glyphs are hidden.
- Each card has a 44 pt hit area, and text containers use `minHeight`. Card chrome text scales
  with Dynamic Type; media slots don't scale with type, they keep their ratio.
- Players expose play/pause as the default action and adjustable scrubbing (`accessibilityAdjustableAction`).

### 1.6 Performance rules (reviews check these)

1. **Web views are scarce.**
   - All web-backed kinds (artifact, SVG, Mermaid render, YouTube player) lease a
     view from one `WebViewSlotPool`, built from the existing `RichWebCard` slot logic
     (`ClaudeRichBlocks.swift:647`). The pool holds at most 2 live `WKWebView`s.
   - A card off screen shows its last snapshot.
   - A web view is never created for a card that hasn't appeared.
2. **Decode off main.** Image decode, video posters (`AVAssetImageGenerator`), audio waveforms,
   PDF thumbnails and ANSI parsing all run off the main actor. The UI receives a ready `UIImage`
   or value.
3. **Decode to display size.** Use ImageIO `kCGImageSourceThumbnailMaxPixelSize` = slot width ×
   screen scale. Never hold a 4000 px screenshot in memory for a 360 pt slot. The full-resolution
   decode happens only in the viewer.
4. **Caches.**
   - An `NSCache` for decoded images, with a cost of bytes and a 64 MB limit.
   - `URLCache` with 100 MB of disk for remote bytes.
   - Daemon-read files go in `Caches/daemon-media/<hash>`, LRU at 500 MB.
   - `MediaMetadataCache` keeps sizes and durations.
5. **Derived lists live in the store (R-1).** Gallery grouping, per-turn change summaries and the
   conversation media index are computed in PaseoStore, incrementally per turn (as P4 does for
   turns), and never computed in `body`.
6. **One player.** A `MediaPlaybackCoordinator` lets only one audio/video/YouTube source play at
   a time. Starting one pauses the others, and scrolling a player beyond one screen away pauses it
   (E3 already does this for YouTube; generalize it).
7. **The audio session is configured off main** (the known `setActive` hang-risk in STATUS).

---

## 2. Catalog

Data legend:
- **Have**: an existing protocol field or store value.
- **Partial**: available in some cases.
- **Needs protocol**: a daemon or protocol change, so out of our control (we never change the
  daemon; this means waiting on upstream).

The menus listed below are the long-press items beyond the common set in §1.2.

| # | Card / surface | Today |
|---|---|---|
| C1 | Image | exists; needs the pipeline |
| C2 | Image gallery | new |
| C3 | Video | E3 basics; needs a poster and download |
| C4 | Audio | E3 basics; needs a waveform row |
| C5 | YouTube | E3 inline play; add a title |
| C6 | Link | LPLinkView; redo |
| C7 | GitHub link | new |
| C8 | Web artifact + artifact page | E3 sizing; page is new |
| C9 | Mermaid diagram | missing (upstream has it) |
| C10 | File (Quick Look) | path chip only |
| C11 | Turn changes | new |
| C12 | Terminal output + test chip | plain text |
| C13 | PR & checks | PR pane only |
| C14 | Map | exists (M17); keep |
| C15 | Conversation media sheet | new |
| C16 | Context and cost charts | meters exist |

### C1. Image

- **Purpose.** Screenshots (Playwright, simulator), generated assets, plots.
- **Trigger.** Detector `.bareImageURL`, `.localImage`, and authored `![alt](url)`
  (`PaseoStore/Rich/RichContentDetector.swift`).
- **Anatomy.**
  - A media card whose only content is the image, with a 0.5 pt border so white screenshots
    don't bleed into the background.
  - The height follows §1.3. This replaces today's fixed `height: 320`
    (`ClaudeRichBlocks.swift:408`).
  - GIF/APNG show their first frame with a "GIF" badge and animate only in the viewer.
- **Interactions.** Tap opens the viewer (§4.6).
- **Data.**
  - Remote images: Have.
  - Local paths: Have, via the daemon read (`FileExplorerRequest`, `acceptBinary`).
- **SwiftUI or UIKit.** SwiftUI over a pipeline `UIImage`. `AsyncImage` is retired: it can't
  downsample, can't report the size early, and has no shared cache.

### C2. Image gallery

- **Purpose.** Agents often post several screenshots in a row, and today they stack into a tall
  column.
- **Trigger.** Two or more image blocks that are adjacent in document order. A pure Core grouping
  pass, tested on Linux.
- **Anatomy.**
  - Layout by count:
    - 2 images: side by side, 1:1 each;
    - 3 images: one 2:3 tile on the left and two stacked on the right;
    - 4 images: 2×2;
    - 5 or more: 2×2, with "+N" on the last tile.
  - 2 pt gutters, and the card radius on the outer corners only.
  - Tiles crop; the viewer never does.
- **Interactions.** Tapping a tile opens the viewer at that index, zooming from that tile.
- **Data.** Have.
- **SwiftUI or UIKit.** SwiftUI `Grid` with fixed geometry per count, so no measuring.

### C3. Video

- **Purpose.** Simulator and browser-test recordings (`simctl io recordVideo` writes `.mp4`).
- **Trigger.** A new detector case, `.localMedia(path, .video)`, for `.mp4`, `.mov` and `.m4v`
  paths, plus remote URLs with those extensions.
  - `.webm` can't play in AVFoundation, so it becomes a C10 file card with Share.
- **Anatomy.**
  - The poster at the track's ratio (16:9 until known).
  - A 44 pt play glyph on a glass circle (as in `GlassIconButton`) and a duration badge.
  - A strip below: name · size.
- **Interactions.** Tap crossfades (`Motion.fade`) into an inline `AVPlayerViewController` in the
  same frame. Menu: Save to Photos.
- **Data.**
  - Remote: Have.
  - Local: Partial.
    - The socket read caps at 64 MB (`WorkspaceShare.swift`).
    - The daemon's `/api/files/download` has no `Range` support
      (`paseo-reference/.../bootstrap.ts:869-920`), so AVPlayer can't stream from it. Local
      videos download whole into the cache first.
    - Files over 64 MB: **needs protocol**.
- **SwiftUI or UIKit.** UIKit (an AVKit representable). Native controls, PiP and AirPlay only come
  from AVKit.

### C4. Audio

- **Purpose.** TTS output and sound assets.
- **Trigger.** `.localMedia(path, .audio)` for `.mp3`, `.m4a`, `.wav`, `.aac`, `.caf` and
  `.aiff`, plus remote URLs with those extensions.
- **Anatomy.** A 56 pt row:
  - a 44 pt play/pause button;
  - a 48-bar waveform (`Canvas`, computed once off main);
  - elapsed/duration in monospaced digits;
  - the file name in `.caption`.
  - Played bars are `Palette.ink`; the rest are `Palette.tertiaryInk`.
- **Interactions.** Dragging on the waveform scrubs (a UIKit pan, R-3).
- **Data.** Same as C3.
- **SwiftUI or UIKit.** A SwiftUI row, with `AVAudioPlayer` owned by `MediaPlaybackCoordinator`.

### C5. YouTube

- **From E3.** The 16:9 thumbnail, in-place playback, and "Open in YouTube".
- **Added here.** A strip with the title (2 lines) · the channel, from YouTube oEmbed
  (`youtube.com/oembed?url=…&format=json`). It's cached, and falls back to doc 05's
  `youtube.com · <id>`.
- **Data.** Have (the URL).

### C6. Link

- **Trigger.** Detector `.linkCard`, unchanged.
- **Anatomy.**
  - Drop `LPLinkView` (`ClaudeRichBlocks.swift:285-297`): it ignores our tokens, resizes after
    load, and looks different per site.
  - Keep `LPMetadataProvider` for the metadata only, and render our own card:
    - with an og:image: a media card with a fixed 1.91:1 image slot (so there's no jump), the
      title (2 lines), and the domain · display URL (doc 05 §1.1 trimming);
    - without one: a row card with a 32 pt favicon, the title and the domain.
- **Interactions.** Tap opens an `SFSafariViewController` sheet (reuse E3's). Menu: Open in
  Safari, Add to chat.
- **Data.** Have.
- **SwiftUI or UIKit.** SwiftUI; the Safari sheet is UIKit.

### C7. GitHub link

- **Purpose.** PR, issue, commit, Actions run and repo links are what coding agents print most.
- **Trigger.** A pure Core `GitHubURL` parser runs on `.linkCard` URLs.
- **Anatomy.** A row card:
  - a glyph by kind;
  - the title;
  - `owner/repo #123`;
  - a `StatePill` for open, draft, merged or closed (upstream labels).
- **Data.**
  - Same repo: Have, via forge search (`ForgeSearch.swift`: title, state, labels).
  - Other repos: falls back to C6, since GitHub's OG image makes a good card.
- **SwiftUI or UIKit.** SwiftUI.

### C8. Web artifact and the artifact page

- **Trigger.**
  - Today: ```` ```visualize ```` fences and raw `<svg>`.
  - New: a "Preview" button in the header of ```` ```html ```` and ```` ```svg ```` code blocks.
    Fences never auto-render (§6).
- **Inline.** E3's sizing.
  - The header keeps "Visualization" or "SVG" and "View source" (existing copy).
  - "Open" (approved in E3) shows when the content is clipped; otherwise it's in the menu.
- **Artifact page.** A `fullScreenCover` with a zoom transition from the card.
  - **Top bar:** a close glass circle; the title from `<title>`, else the first `<h1>`, else the
    kind label; a menu with View source, Copy source, Share as .html and Reload.
  - **Body:** the same document, uncapped, in the app's color scheme. This fixes doc 05 §6.7's
    always-dark export.
  - **Source:** the existing highlighter, toggled in place.
  - **Bridges:** the visualize bridges keep working. `sendPrompt` closes the page and steers the
    conversation.
- **Data.** Have.
- **SwiftUI or UIKit.**
  - The page is SwiftUI around `SandboxedHTMLView`.
  - The page's slot outranks transcript slots.

### C9. Mermaid diagram

- **Why.** Agents explain flows in Mermaid constantly.
  - Upstream renders it natively: `packages/app/src/components/markdown/fence/mermaid/host.native.tsx`,
    with a 480 px cap and a full-screen viewer.
  - We drop it on purpose (`RichContentDetectorTests.swift:704-706`), and it isn't in
    `docs/PARITY.md`.
  - **This is a parity gap.**
- **Trigger.** A closed ```` ```mermaid ```` fence. While it streams, it stays code.
- **Anatomy.**
  - The diagram renders once, off screen, in a pooled web view running a bundled offline runtime.
    Port upstream's `runtime/html.gen.ts` idea; it's 3.5 MB, so it ships as a resource loaded via
    `loadFileURL`.
  - It's snapshotted at 2× and cached by `hash(source + scheme)`. **The transcript holds images,
    not web views.**
  - Natural ratio, capped at 480 pt, with "Open" above the cap.
  - A syntax error shows the source plus upstream's error string.
- **Interactions.** Tap opens the live SVG on the artifact page with pinch-zoom. Menu: View
  source, Share image.
- **Data.** Have.
- **SwiftUI or UIKit.** A SwiftUI card showing an image, rendered by an off-screen UIKit web view.

### C10. File (Quick Look)

- **Trigger.** `.localFileLink`.
  - On a standalone line it becomes a card.
  - Inside a sentence it stays a `RichPathChip` (`ClaudeRichBlocks.swift:596`).
- **Anatomy.** A row card:
  - a UTType symbol;
  - the name;
  - the parent directory (middle-truncated) · size;
  - a chevron.
  - PDFs show a 44 pt first-page thumbnail (PDFKit, off main).
- **Interactions.**
  - Text, code and image files open in the workspace file viewer
    (`Workspace/WorkspaceFileViewer.swift`).
  - Everything else downloads (64 MB cap) and opens in `QLPreviewController`: PDF, CSV, Office,
    USDZ with AR.
  - Menu: Add to chat, Copy path.
- **Data.**
  - Have: the path and the read.
  - Partial: the size comes from a lazy, cached listing of the parent directory.
- **SwiftUI or UIKit.** The card is SwiftUI; Quick Look is UIKit.

### C11. Turn changes

- **Why.** It answers the most useful question about a coding turn, which files changed. Today
  that's buried in the collapsed work group.
- **Trigger.** A completed turn with `edit` or `write` tool calls (`PaseoProtocol/Timeline.swift:156-157`).
  The card goes after the final prose.
- **Anatomy.** A row card:
  - the title "N files changed" (upstream string, or copy approval);
  - the first two names + "and N more";
  - a `DiffStat` (+120 −33);
  - a tap expands it (`Motion.disclosure`) into per-file rows. Each row opens the Changes diff if
    the file is still dirty, else the tool call's own diff (`ClaudeDiffView`).
- **Data.**
  - Have: a pure `TurnChangeSummary` in PaseoStore, built incrementally with P4's tail rebuild.
  - Counts come from `unifiedDiff`, else from `oldString`/`newString` line counts. A `write`
    counts as all added.
- **SwiftUI or UIKit.** SwiftUI.

### C12. Terminal output and the test chip

- **Trigger.** `ToolCallDetail.shell` output in the tool detail (`Conversation/Turn/ClaudeToolDetail.swift:28`).
  Today it can show raw `ESC[31m`.
- **Anatomy.**
  - `Palette.codeSurface` in `.codeSmall`.
  - ANSI SGR maps to 16 `Palette.ansi…` colors plus bold and dim. Other escapes are dropped.
  - The last 12 lines, with "Show all".
  - The exit code as a `StatePill`.
  - A test chip ("✓ 128 ✗ 2 ◌ 4") when the output parses for swift test/XCTest, Jest/Vitest,
    pytest, cargo or go.
- **Data.** Have. `AnsiText` and `TestSummaryParser` are pure PaseoStore types, Linux-tested
  against captured outputs.
- **SwiftUI or UIKit.** SwiftUI `Text(AttributedString)`. SwiftTerm per tool call is far too
  heavy.

### C13. PR & checks

- **Trigger.** A PR URL whose number matches the workspace's `CheckoutPrStatus` (`Checkout.swift:87-124`).
- **Anatomy.** A row card:
  - the title;
  - `#42 · head → base`;
  - a state pill;
  - a checks ring (Swift Charts `SectorMark`: passed/failed/pending);
  - the review decision.
  - It updates live from the existing checkout subscription.
- **Interactions.**
  - Tap opens the PR pane (`Workspace/WorkspacePRPane.swift`).
  - Menu: Open on GitHub, add a failing check to chat (V3).
- **Data.** Have.
- **SwiftUI or UIKit.** SwiftUI.

### C14. Map

- Exists (M17).
- Move it onto `PaseoCard`; no expansion (§6).

### C15. Conversation media sheet

- **Purpose.** "Where was that screenshot?" Modeled on iMessage Details and Claude's artifact
  list.
- **Trigger.** An entry in the header menu.
- **Anatomy.** A `SheetScaffold` with three segments, newest first:
  - Media: a 3-column grid of images, posters, and diagram/artifact snapshots;
  - Links: C6 rows;
  - Files: C10 rows.
  - Tapping an item jumps to its turn (U5 jump) or opens the viewer.
- **Data.** Partial: it covers loaded turns, and older ones load on demand with `before` paging.
  It's backed by a `ConversationMediaIndex` in the store, appended per turn.
- **SwiftUI or UIKit.** SwiftUI `LazyVGrid`.

### C16. Context and cost charts

- **Where.** The existing context sheet (`Conversation/Sheets/ClaudeContextSheet.swift`).
- **Anatomy.**
  - A context `Gauge` (used/max tokens).
  - Per-turn bars for output tokens and cost (Swift Charts, last 30 turns).
  - Cost by model as bars.
  - Neutral ink with one accent.
- **Data.**
  - Have: `AgentUsage` on `turn_completed`/`usage_updated` (`AgentTimeline.swift:108-109`).
  - Partial: only turns seen live carry usage, so the chart starts where the data starts.
  - Full history: **needs protocol**.
- **SwiftUI or UIKit.** Swift Charts (already used in `Sidebar/ClaudeUsageReportsSheet.swift`).

---

## 3. System surfaces

### 3.0 The constraint

There is no push server. The daemon's only push path is Expo push
(`paseo-reference/packages/server/src/server/push/push-service.ts`). It POSTs
`{to, title, body, data, sound}` for tokens registered with `register_push_token`.
- There is no APNs `liveactivity` or `widgets` push type, and no `content-available` or
  `mutable-content`.
- So Live Activity updates while the app is suspended, and widget push reloads, need a daemon
  change.
- Plain alert pushes to a closed app need only a paid account (§3.7).

Everything else works on local updates: the app writes state while it runs, and extensions read
it.

**Plumbing.**
- One App Group (`group.com.wiselfx.paseoclient`).
- A Codable `GlanceSnapshot` in PaseoStore (Linux-tested). Per host it holds:
  - for each agent: id, title, project, provider, status, `requiresAttention`, `attentionReason`,
    `activeTurn.startedAt`, the pending-permission count, and `updatedAt`
    (`PaseoProtocol/Agents.swift:29-64`);
  - `capturedAt`.
- The app writes it at most every 10 s, plus on every attention change and on `.background`, then
  calls `WidgetCenter.reloadTimelines`. Reloads from the foreground app don't count against the
  widget budget.
- **Privacy.** Agent titles are the user's prompts.
  - Lock Screen surfaces mark titles `.privacySensitive()`.
  - A toggle under Settings → Notifications (copy approval) defaults to hidden.

**Signing [D].**
- Each extension is a new App ID with App Groups.
- Free personal teams appear to allow App Groups, but not push, and profiles expire every 7 days.
- The IPAs in `/Users/Shared/Paseo-ipas/` are unsigned. Ask how the user signs them before
  ticketing G14–G20.

### 3.1 Widgets: "Agents" (accept)

Sizes are from the HIG for a 393 pt-wide iPhone.
- **Small (158×158).**
  - The big number is agents needing you, in serif `Typography.hero`. When nobody needs you, it
    falls back to running agents.
  - A label and the top agent's title go underneath.
  - Tap opens `paseo://agent/<id>` (M20 routes).
- **Medium (338×158).**
  - Up to 3 rows: `StatusDot`, title, project, and a `Text(date, style: .relative)` the system
    refreshes for free. Attention sorts first, and each row is a `Link`.
  - The footer shows the host · "Updated" + the relative `capturedAt`, so staleness is always
    visible.
- **Accessory families.**
  - Rectangular: "2 need you · 3 running" + the top title (redacted when locked).
  - Circular: a count ring.
  - Inline: one line.
- **Rendering.**
  - Honour `.accented` mode (iOS 26 tinted and clear Home Screens). Dots get distinct shapes, so
    meaning doesn't depend on color alone.
  - 16 pt margins (11 for groupings) and `ContainerRelativeShape`.
- **Freshness.**
  - A single timeline entry from the snapshot, and no polling. An honest "Updated 2 h ago" beats a
    guess.
  - G22 later tests a provider that fetches through PaseoKit itself, within the reload budget and
    the extension's memory ceiling.
- **Interactivity.** None. Approve/deny is rejected (§6).

### 3.2 Live Activity: "Agents at work" (accept, gated on G17)

- **One activity for the app, not one per agent.** The HIG says to "prefer a single Live Activity
  that uses a dynamic layout and rotates through events".
- **Start.** When you send a prompt (ActivityKit only starts from the foreground).
  - The app's own activity is hidden in the Dynamic Island while the app is in front, so it only
    appears when you leave.
  - It tracks "watched" agents: ones you prompted from this device whose turn is still running.
  - It's behind a setting, default on.
- **Compact (52×37).**
  - Leading: the crab glyph in `Palette.orange`, without a container.
  - Trailing: `Text(timerInterval:)` from `activeTurn.startedAt`, which ticks with no updates, or
    a count when several agents are watched.
  - In limited width (landscape, `isDynamicIslandLimitedInWidth`): leading only, a 28 pt circle.
- **Minimal.** The glyph, plus a dot when someone needs you.
- **Expanded and Lock Screen (371×84–160, 14 pt margins).**
  - Row 1: the title (redacted when locked) + the timer.
  - Row 2: a factual line from a pure PaseoStore `ActivityLine`, such as "Running `swift test`" or
    "Editing `Foo.swift`". Never a quip.
  - Row 3: only if a todo list exists, `ProgressView` "3 of 7".
  - With several agents: the one needing attention first, then "and 2 more" (copy approval).
- **States.**
  - Running.
  - Needs you: the upstream attention reason, with a single `alertConfiguration`, and no
    duplicate local notification.
  - Finished: `.after(.now + 15 min)` dismissal, with a summary in the "Completed in" format.
- **Updates.** Only on phase, attention, todo or tool-kind changes, at most one per 5 s. Tapping
  deep-links to the agent; there are no buttons.
- **The honesty problem.**
  - Seconds after you leave, iOS suspends the app, and the activity can't learn that the turn
    ended. The timer would keep counting.
  - `staleDate = lastUpdate + 3 min` turns the stale view into a greyed timer + "Updated" relative
    time. That's truthful but weak.
  - Hence G17: test `BGContinuedProcessingTask` (iOS 26), which lets a user-initiated task keep
    running in the background, with system progress UI, while it reports progress. Apple
    terminates low-progress tasks first.
  - If a turn can be followed for ≥ 15 min in typical use, ship G18. Otherwise defer it until
    push exists. **A Live Activity that lies is worse than none.**
- **Free reach.** StandBy, the macOS Tahoe menu bar and the Watch Smart Stack come from the same
  views. There are no custom Watch or CarPlay layouts.

### 3.3 Controls (accept)

- **"New agent".** A `ControlWidgetButton` + `OpenIntent` that opens the U2 draft with the composer
  focused. It works from Control Center, the Lock Screen, and the Action button.
- **Optional "Voice mode" control.** Ask the user first.
- No toggles: Paseo has no binary state worth one.
- Raycast iOS ships the same pattern (Control and Lock Screen widgets that start a chat).

### 3.4 App Intents, Shortcuts, Spotlight (accept)

- **`AgentEntity`** (id, title, project, status).
  - Its `EntityQuery` reads the snapshot, so it needs no socket in any process.
  - It conforms to `IndexedEntity`, so agents show in Spotlight.
- **`OpenAgentIntent`** (`OpenIntent`).
- **`NewAgentIntent(prompt:, project:)`** with `openAppWhenRun`. It prefills the draft and never
  sends.
- **`AgentsNeedingAttentionIntent`**, read-only, for automations.
- **Two App Shortcuts.**
- No `SnippetIntent` for now.

### 3.5 Permission actions in notifications [D]

- **Actions.** The existing local attention notifications (`App/Sources/NotificationCoordinator.swift`)
  get **Allow** and **Deny** actions with `.authenticationRequired`.
  - Map them only to `AgentPermissionAction`s that are plain allow-once or deny
    (`Permissions.swift:78-98`).
  - Questions, plans and suggestions get Open only.
  - The body shows the tool and the first command line, subject to the system's preview setting.
- **Handling.** iOS launches the app in the background. The app reconnects and sends
  `RespondToAgentPermissionRequest`. If that fails, it posts an Open notification.
- **Defaults.** Off by default, and never "always allow".
- **Why here and not in a widget.** Notifications have a native unlock gate and an expanded view,
  and they need no daemon credentials in an extension.

### 3.6 Share extension [D, new feature]

- **Flow.** Share a URL, a screenshot or a file from any app.
  - Pick the host, then a project (new agent) or an existing agent from the snapshot.
  - Add a message and send.
- **Sending.**
  - It sends directly through PaseoKit (shared Keychain) and the existing upload (T14).
  - If the host is unreachable, the payload goes to an App Group inbox, and the app shows it as a
    draft attachment on next launch.
- **Size.** It's the largest system ticket (L).

### 3.7 Push without our own server [D]

- **No daemon change needed.**
  1. Join the paid Apple Developer Program for the APNs entitlement.
  2. Create a free Expo project and upload our APNs key.
  3. The app registers for remote notifications and POSTs its device token to
     `exp.host/--/api/v2/push/getExpoPushToken` with
     `{type:"apns", deviceId, development, appId, deviceToken, projectId}`. That's
     `expo-notifications`' own request, and it's undocumented.
  4. The app sends the returned `ExponentPushToken[…]` to each daemon via `register_push_token`.
  5. The daemon's existing attention pushes then reach a closed app.
- **Costs.** $99/year, an undocumented endpoint, and agent titles transiting Expo.
- **What it doesn't unlock.** Live Activity or widget pushes.

### 3.8 Not doing

- `BGAppRefreshTask` polling: opportunistic, and it gives false freshness.
- Siri sending a prompt in the background.
- A Watch app, CarPlay layouts, and Focus filters.

See §6.

---

## 4. Rich media done properly

### 4.1 One pipeline

`MediaPipeline` is an actor in PaseoUI. It is the only way pixels enter the transcript.

1. **Source.**
   - Remote URL: `URLSession` with `URLCache`.
   - Daemon path: `FileExplorerRequest(mode: .file, acceptBinary: true, maxBytes: 64 MB)` into
     `Caches/daemon-media/<sha256(host+cwd+path+revision)>`. Use `revision` when the daemon sends
     it, so an edited screenshot refreshes.
2. **Probe.** `CGImageSourceCreateIncremental`: feed bytes as they stream; as soon as
   `kCGImageSourcePixelWidth/Height` appear, publish the size to `MediaMetadataCache`. The card
   settles to its true ratio before the image finishes downloading.
3. **Decode.** `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` =
   slot pixel width, `kCGImageSourceCreateThumbnailWithTransform` (EXIF orientation), off main.
   The result goes into the `NSCache`.
4. **Full resolution** happens only on viewer open, also off main, preloading neighbors ±1.
5. **SVG files** (Files panel and `.svg` URLs) go through E3's SVG renderer, never ImageIO.
6. **Hotlink/referrer.** Doc 05 §3 accepts this risk. If a remote image returns HTML or 403, show
   the error state with "Open in Safari".

### 4.2 Images

- **Single image.** Full column width. The ratio comes from the probe or cache, falling back to
  4:3 reserved. Height is clamped to `[120, 0.6 × screen]`.
  - Portrait screenshots (≈ 0.46) hit the 60 % cap. They show centered at their true ratio, with
    the remaining width on `Palette.codeSurface`. They never crop: a cropped screenshot hides the
    bug.
- **Gallery.** As C2. Tiles crop, the viewer never does.
- **Appearance.** Fade in over `Motion.fade` on first decode, and only then. Cache hits appear
  instantly, with no fade.
- **In user bubbles.** Attached images keep the existing ClaudeUI thumbnails and use the same
  viewer.

### 4.3 Video

- **In the transcript.**
  - The poster is generated off main from the first non-black frame at 1 s
    (`AVAssetImageGenerator`, `maximumSize` = slot pixels). It shows the duration badge and the
    play glyph.
  - Tap: the poster crossfades into `AVPlayerViewController` (inline, native controls, muted
    no autoplay). It keeps the same frame, so there's no layout change.
- **Full screen.** The AVKit button. It supports PiP (`allowsPictureInPicturePlayback`) and AirPlay.
- **Lifecycle.**
  - `MediaPlaybackCoordinator` pauses the player when another starts, or when the card is more
    than one screen away.
  - The player object is released when off screen, and its position is kept in
    `MediaMetadataCache` so it resumes where it left off.
- **Local files.**
  - Download progress shows as a thin determinate bar at the poster bottom.
  - Over 20 MB, the card waits for a tap (it shows the size first).
  - Over 64 MB, it shows "Open in Files" / Share only (needs protocol to do better).

### 4.4 Audio

As C4.
- Waveform from `AVAudioFile` read in chunks, RMS into 48 buckets, off main, cached.
- The session category is `.playback`, activated off main. It's deactivated when playback ends
  with `.notifyOthersOnDeactivation`.
- Now Playing info is set only while playing, so Lock Screen controls work for long audio.
- No background audio mode: playback stops when the app is suspended. That's acceptable, and it
  avoids an entitlement the app shouldn't claim.

### 4.5 YouTube

- E3's behavior (16:9 thumbnail, tap swaps to the `youtube-nocookie` embed in place,
  `playsinline`, autoplay on tap, one player at a time, the web view created on tap only, "Open in
  YouTube" in the menu) plus:
  - the C5 title strip;
  - `allowsPictureInPictureMediaPlayback = true`, so the system PiP works from the embed's full
    screen;
  - `?start=` preserved from `t=` (doc 05 §1.2 keeps the query).
- The player web view counts against the `WebViewSlotPool`.

### 4.6 The full-screen viewer (images, gallery, Mermaid snapshots, video posters)

- **Why UIKit.** It's a UIKit container (R-3: finger-tracked motion runs in UIKit), presented from
  SwiftUI.
- **Structure.** A `UIPageViewController` of `UIScrollView` zoom pages. Extend the existing
  `ZoomableImageView` (`WorkspaceFileViewer.swift:637`) into the shared page.
- **Enter.** The zoom transition from the source thumbnail (SwiftUI `matchedTransitionSource` on
  the card, and the viewer as the destination). The background goes black, and the status bar
  hides while the chrome is hidden.
- **Gestures.**
  - One finger swipe left/right: page.
  - Pinch: zoom up to native resolution (minimum 1×, maximum `max(4, pixel/points)`).
  - Double-tap: zoom 2.5× at the tap point, or back to fit.
  - Drag down at 1×: an interactive dismiss. The image follows the finger, the background alpha
    tracks the distance, and the release is velocity-matched to
    `UISpringTimingParameters(dampingRatio: 1)`. It returns to the thumbnail when the source is
    still on screen, else fades.
  - Single tap: toggle the chrome.
- **Chrome.**
  - Top: a close glass circle (left), then "2 of 5" (`.footnote`, monospaced digits).
  - Bottom glass bar: Share, Copy, Save to Photos (needs `NSPhotoLibraryAddUsageDescription`),
    Show in Files, and **Live Text**.
  - Live Text: VisionKit `ImageAnalysisInteraction` runs once per image off main. When text is
    found, a `text.viewfinder` button appears. Selecting text from an error screenshot and
    pasting it into the composer is the killer use for a coding client.
  - "Add to chat" puts the image in the composer as an attachment, through the existing attachment
    path (M6a).
- **Animated GIF/APNG** play here. **Video posters** open the AVKit player instead.
- **Accessibility.** VoiceOver page announcements ("Image 2 of 5, alt text"), escape gesture to
  close, and zoom via the adjustable action.

### 4.7 SVG

- E3 renders inline SVG at its intrinsic ratio, full width, capped at 60 %.
- On top of that:
  - tap → the artifact page (§2 C8), not the image viewer, so text stays vector at any zoom;
  - "Share image" rasterizes at 3× via the existing snapshot path.

### 4.8 HTML artifacts

- E3 sizes the inline card.
- The artifact page (§2 C8) is the "Open" destination for:
  - visualize fences;
  - the "Preview" button on html/svg code blocks;
  - the Files panel's "Open full screen" for `.html` files (it reuses E3's file preview
    configuration: scripts on, non-persistent data store, top-level navigation into
    `SFSafariViewController`).
- **Security posture, unchanged from E3 and doc 05:**
  - chat artifacts stay offline (CSP `connect-src 'none'`, navigation blocked);
  - file previews may load CDN subresources;
  - nothing gets cookies or persistent storage beyond the 64 KB viz state.

### 4.9 Size table (iPhone, 393 pt wide, prose column ≈ 361 pt)

| Kind | Width | Height rule | Radius |
|---|---|---|---|
| Image | column | true ratio, clamp 120…0.6×screen | 12 |
| Gallery | column | 2: 1:1 tiles; 3: 3:2 card; 4+: 1:1 card | 12 outer |
| Video | column | track ratio, else 16:9, same clamp | 12 |
| YouTube | column | 16:9 | 12 |
| Link (with image) | column | image 1.91:1 + strip | 12 |
| Mermaid | column | natural, cap 480 | 12 |
| Visualize / HTML | column | content, cap 70 % (E3) | 12 |
| SVG | column | intrinsic, cap 60 % (E3) | 12 |
| Row cards | column | min 56 (audio 56, file 56, PR 64) | 12 |
| Map | column | 150 (M17) | 12 |

---

## 5. Roadmap

**Conventions.**
- Proposed ids are **G1…**.
- Sizes: S ≈ half a day, M ≈ 1–2 days, L ≈ 3–4 days for one worker.
- Every ticket follows `AGENTS.md`:
  - Core logic goes in PaseoStore with Linux tests;
  - UI goes through the Mac build gate;
  - no new dependencies.
- **[D]** means the user must decide before the ticket is written.
- Paths are relative to `Packages/PaseoUI/Sources/PaseoUI/` unless they start with `App/` or
  PaseoStore.

### Phase 0: Foundations (after E3 merges)

| Id | Title | Scope and likely files | Acceptance | Size |
|---|---|---|---|---|
| G1 | Card family | `PaseoCard` (media/row layouts, header, accessory, press, menu helper) in `DesignSystem/Components/PaseoCard.swift`; `RichActions` environment; migrate link/map/YouTube/web cards in `Conversation/Prose/Rich/ClaudeRichBlocks.swift`, `ClaudeRichSplice.swift`; delete `RichCard` | Every rich block uses it; style-lint clean; no closure params; screenshots light/dark/pure black | M |
| G2 | Media pipeline | `MediaPipeline` actor + `MediaMetadataCache` (§4.1) in new `Conversation/Prose/Media/`; replace `AsyncImage` and the fixed 320 pt in `RichRemoteImage`/`RichLocalImage`, `ProseMarkdownImage.swift` | 20-screenshot chat scrolls without hitches on device; no position jump on load; no fade on revisit; < 150 MB; no decode on main (profiler shot) | M |
| G3 | Full-screen viewer | §4.6 UIKit pager, zoom transition, drag-to-dismiss, chrome, Live Text, Save to Photos, Add to chat; new `Conversation/Prose/Media/MediaViewer*.swift`; retire `RichImageViewer`, adapt `ClaudeMediaView.swift`; Files panel images use it (`Workspace/WorkspaceFileViewer.swift`); `App/project.yml` Photos-add usage string | Zoom matches the thumbnail both ways; dismiss tracks the finger and settles without overshoot; Reduce Motion crossfades; Live Text selects screenshot text; VoiceOver "Image n of m" | L |

### Phase 1: Artifacts coding agents actually make

| Id | Title | Scope and likely files | Acceptance | Size |
|---|---|---|---|---|
| G4 | Mermaid | Detector case + new test file in PaseoStore `Rich/`; bundled runtime resource; `WebViewSlotPool` extracted from `RichWebCard` (`Rich/RichWebContent.swift`); off-screen render → snapshot cache; C9 card + live full-screen; `docs/PARITY.md` row. **The lead must approve changing the contract test at `RichContentDetectorTests.swift:704`.** | Flowchart/sequence/class/gantt in both schemes; 10 diagrams → ≤ 2 web views (logged); streaming fence stays code; syntax errors show source + error | L |
| G5 | Artifact page | C8 page, title extraction, source toggle, scheme-aware .html share, Reload, bridges, "Preview" on html/svg code blocks (`ClaudeMarkdownView.swift`), "Open" from inline cards, Files `.html` full screen; new `Conversation/Prose/Rich/ArtifactPage.swift` | Zoom from card; `sendPrompt` steers and closes; export opens in Safari in both schemes; fences never auto-render | M |
| G6 | Turn changes card | `TurnChangeSummary` (PaseoStore, incremental with `IncrementalTurnBuilder.swift`, tests); C11 card appended in `Conversation/Transcript/ChatTurns.swift`; new `Conversation/Turn/TurnChangesCard.swift` | Counts equal `git diff --stat` on a fixture; streaming touches only the tail card; row `Equatable`. **[D] title copy** | M |
| G7 | Galleries | Grouping pass (PaseoStore `Rich/RichImageGrouping.swift` + tests); C2 grid `Rich/RichGalleryCard.swift` → G3 viewer | 2/3/4/7-image layouts; opens at the tapped index with zoom; single images unchanged | M |
| G8 | Terminal output | `AnsiText`, `TestSummaryParser` (PaseoStore + captured-output tests); colored tail, exit pill, test chip in `Conversation/Turn/ClaudeToolDetail.swift`; ANSI colors in `DesignSystem/Palette.swift` | No raw escapes ever shown; legible in all three themes; 6 runners parse; 1 MB parses < 50 ms on Linux | M |
| G9 | Links v2, GitHub, PR & checks | C6 own card from `LPMetadataProvider` (drop `LinkPreviewView`); C5 oEmbed strip; `GitHubURL` parser (PaseoStore + tests); C7 via forge search; C13 bound to checkout PR status; new `Rich/RichGitHubCard.swift` | No link card changes height after layout; workspace PR card turns green live; other repos degrade to the metadata card | M |
| G10 | File cards + Quick Look | C10 for standalone paths (detector tweak + tests); lazy size; PDF thumbnail; download → `QLPreviewController`; new `Rich/RichFileCard.swift`, `QuickLookPresenter.swift` | PDF/CSV/zip/docx open in Quick Look; text/code still use the workspace viewer; nothing downloads before a tap (except PDF thumbnails < 5 MB) | M |
| G11 | Video + audio | `.localMedia` detector + remote media URLs (tests); C3 poster → inline AVKit; C4 waveform row; `MediaPlaybackCoordinator`; 20 MB tap / 64 MB cap; audio session off main; new `Conversation/Prose/Media/VideoCard.swift`, `AudioRow.swift`; `MediaState.swift` kinds | A simulator `.mp4` plays inline and in PiP; never two players at once; scrolling away pauses; Thread Checker clean | L |
| G12 | Media sheet | `ConversationMediaIndex` (store, incremental, tests); C15 sheet `Conversation/Sheets/ChatMediaSheet.swift`; header menu entry | Opens < 100 ms on a 5k-row chat; tap lands on the turn; `EmptyState` with approved copy. **[D] label** | M |
| G13 | Context & cost charts | Per-turn usage series (PaseoStore `ConversationContext.swift` + tests); C16 in `Conversation/Sheets/ClaudeContextSheet.swift` | Starts where the data starts (no fake zeros); `accessibilityChartDescriptor` | S |

### Phase 2: System surfaces without push

| Id | Title | Scope and likely files | Acceptance | Size |
|---|---|---|---|---|
| G14 | App Group + snapshot **[D] signing** | `GlanceSnapshot` (PaseoStore + tests); throttled writer in `App/Sources/AppModel.swift`; App Group; empty `PaseoWidgets` target in `App/project.yml`; deep-link builder | Round-trips; ≤ 1 write / 10 s while streaming; the extension builds on the gate | M |
| G15 | Agents widgets | §3.1 small, medium, three accessory families, accented mode, redaction toggle (Settings → Notifications), deep links; `App/Widgets/AgentsWidget*.swift` | HIG sizes; legible when tinted or clear; Lock Screen redacted by default; taps land on the agent; "Updated" ticks without reloads | M |
| G16 | Controls, Shortcuts, Spotlight | §3.3–3.4: `AgentEntity` + `IndexedEntity`, `OpenAgentIntent`, `NewAgentIntent` (no autosend), the attention query, two controls; `App/Intents/`, `App/Widgets/Controls.swift`, routing in `App/Sources/PaseoClientApp.swift` | Spotlight finds an agent by title; Action button opens New agent with focus; Shortcuts shows approved names | M |
| G17 | Spike: background watching | Throwaway branch: `BGContinuedProcessingTaskRequest` on leaving during a turn; hold the socket, report progress, log survival on device (LAN, Tailscale, relay; locked and unlocked); compare to `beginBackgroundTask` alone | A survival-time table, system UI screenshots, go/no-go for G18 | S |
| G18 | Live Activity **[D] gated on G17 or G21** | §3.2 all presentations, limited width, stale view, single attention alert, 15 min dismissal, setting; pure `ActivityLine` (PaseoStore + tests); `App/Widgets/AgentsLiveActivity.swift` | ≤ 1 update / 5 s (logged); goes stale when updates stop; alerts once; ends on finish; shows in the Mac menu bar | L |
| G19 | Permission notification actions **[D]** | §3.5 in `App/Sources/NotificationCoordinator.swift` + action mapping in PaseoStore `AttentionCenter.swift` (tests) | Actions only on simple requests; unlock required; background reconnect responds; failure posts Open | M |
| G20 | Share extension **[D] new feature** | §3.6; `App/Share/`, `App/project.yml` | Safari URL and Photos screenshot reach a chosen agent; inbox fallback offline; within the extension memory limit | L |

### Phase 3: Needs money, upstream or evidence

- **G21. Push via Expo** (M). **[D]** Needs a paid account and an Expo project. See §3.7.
- **G22. Widget self-refresh spike** (M). Measures memory and relay viability.
- **G23. Upstream asks, not tickets:**
  - `Range` on `/api/files/download`;
  - socket reads over 64 MB;
  - per-turn usage in the projected timeline;
  - APNs `liveactivity` and `widgets` push types.

**Order by value per effort:** G1 → G2 → G4 → G3 → G6 → G5 → G8 → G9 → G7 → G10 → G14 → G15 →
G16 → G17 → G11 → G12 → G13 → decisions for G18–G21.
- Mermaid goes before the viewer because it's a visible parity gap that only needs G1.

**One decision message to the user:**
1. How are IPAs signed: free or paid team? This gates G14–G21.
2. Bundle the Mermaid runtime (3.5 MB)? Recommend yes.
3. Ship the Live Activity only if G17 proves it can stay truthful? Recommend yes.
4. Allow/Deny from notifications? Recommend yes, off by default.
5. A share extension? Later, after widgets.
6. Pay for push via Expo?
7. Approve the new copy:
   - the turn changes title;
   - widget labels;
   - "and N more";
   - "Updated";
   - the download-size prompt;
   - the media sheet name;
   - the Photos usage string.

---

## 6. Rejected ideas

- **MapKit expansion (live maps, address detection, place cards).** M17 already renders
  coordinates and map links with a snapshot. Coding agents almost never output places, and
  fuzzy address detection would turn prose into cards. Keep M17 as is.
- **Weather, sports, recipe and shopping cards.** These are what ChatGPT's and Claude's consumer
  apps do. They depend on first-party data services; the daemon has none, and agents don't emit
  structured versions. Claude's own mobile app renders weather as text.
- **Generative UI (forms, buttons, choice chips inside answers),** as in ChatGPT's Intelligent UI
  and Claude's interactive inputs. There's no agent-side protocol for it. The visualize bridge
  (`sendPrompt`) already covers "the artifact talks back", and permission/question cards cover
  structured input.
- **`LPLinkView` as the link renderer.** It can't take our tokens, resizes after load, and looks
  different per site. We keep its metadata and draw our own card.
- **Auto-rendering ```` ```html ```` / ```` ```svg ```` code fences.** For a coding agent, a fence
  is code to read, review and copy. Rendering it by default hides the code and runs untrusted
  scripts. We offer "Preview" instead.
- **Approve/deny buttons in widgets or the Live Activity.**
  - The Lock Screen shows a fraction of the request.
  - Taps are easy to make by accident (the HIG warns about this).
  - CarPlay disables buttons anyway.
  - A widget's intent runs in an extension that would need daemon credentials.
  - Notification actions (§3.5) have a native unlock gate and an expanded view, so that's the
    only place this lives.
- **One Live Activity per agent.** The Dynamic Island shows at most a few, and the HIG says to
  prefer one rotating activity.
- **Live Activity and widget push updates.** These need APNs `liveactivity`/`widgets` push types
  from the daemon (§3.0). They're blocked until upstream adds them, which is listed for G23.
- **`BGAppRefreshTask` polling for widgets.** It runs on the system's schedule, not ours, and is
  too rare and too short to matter. It also makes the "Updated" label lie less often but not
  never.
- **A YouTube iOS Helper (`YTPlayerView`) or any player SDK.** No new dependencies, and the
  `WKWebView` embed already works (E3).
- **A custom chart fence or auto-charting Markdown tables.** No agent emits a chart fence. When an
  agent wants a chart it writes a visualize fence, which we host. Turning tables into charts
  guesses intent.
- **A terminal emulator per tool call (SwiftTerm in the transcript).** It's far too heavy. ANSI to
  attributed text covers 99 % of tool output. The real terminal stays in the panel.
- **An Apple Watch app, custom CarPlay layouts, iPad layouts, StandBy custom layouts.** These go
  against the platform priority (iPhone first, Mac second). The Live Activity reaches the Watch,
  the Mac menu bar and StandBy for free.
- **Siri or a Shortcut that sends a prompt in the background.** That needs a socket in the intent
  process, and sending unseen text to an agent with shell access is a footgun. `NewAgentIntent`
  opens a prefilled draft instead.
- **Focus filters** (hide hosts or projects per Focus). The value is low for a single-user app.
- **Foundation Models summaries for the Live Activity or widgets.** That would be invented copy and
  extra latency. The factual `ActivityLine` is clearer.
- **Math (LaTeX) rendering.** It's out of scope here: rare in coding output, and a separate
  renderer decision. Revisit only if the user asks.

---

## 7. Sources

Apple, design and docs:
- HIG, Live Activities (presentations, 8-hour guidance, 4-hour Lock Screen retention, 15–30 min
  dismissal, single rotating activity, interactivity, iOS/Watch/CarPlay specs; change log Oct 2026):
  https://developer.apple.com/design/human-interface-guidelines/live-activities
- HIG, Widgets (margins 16/11 pt, sizes, accented/vibrant modes, interactivity, privacy, relative
  dates): https://developer.apple.com/design/human-interface-guidelines/widgets
- WWDC25 "What's new in widgets" (accented/glass rendering, CarPlay and Mac Live Activities,
  `supplementalActivityFamilies`, `WidgetPushHandler` and the APNs `widgets` push type, relevance
  widgets): https://developer.apple.com/videos/play/wwdc2025/278/
- WWDC26 "Live Activities essentials" (landscape Dynamic Island, `isDynamicIslandLimitedInWidth`,
  StandBy, small family, `LiveActivityIntent`, local vs push updates):
  https://developer.apple.com/videos/play/wwdc2026/223/
- `BGContinuedProcessingTask` (iOS 26; system Live Activity progress UI; low-progress tasks
  terminated first): https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
- `IntentAuthenticationPolicy`: https://developer.apple.com/documentation/appintents/intentauthenticationpolicy
- `SnippetIntent` (iOS 26 interactive snippets): https://developer.apple.com/documentation/appintents/snippetintent
- WWDC25 session 275 on interactive snippets: https://developer.apple.com/videos/play/wwdc2025/275/
- App Intents in iOS 27 (`LongRunningIntent`, `IntentExecutionTargets`, `IndexedEntityQuery`),
  third-party summary: https://www.blakecrosley.com/blog/app-intents-ios-27-background-execution
- Forum threads on Live Activity background updates (only reliable via push or foreground):
  https://developer.apple.com/forums/thread/776031 , https://developer.apple.com/forums/thread/717544

Other apps:
- GitHub Mobile, Live Activities for coding-agent sessions (in progress/completed/failed/cancelled,
  tap to PR, opt-out): https://github.blog/changelog/2026-02-26-github-mobile-track-coding-agent-progress-in-real-time-with-live-notifications
- Codex in the ChatGPT mobile app (mirrors a host machine; diff viewer with line comments, goal
  timer, approval gates): https://codex.danielvaughan.com/2026/06/12/codex-mobile-chatgpt-ios-branch-worktree-goal-inline-review-cli-companion/
- Claude Code Remote Control mobile permission-prompt issues (truncated commands, mis-taps, missing
  prompts): https://claudeissues.com/issue/37235-feature-remote-control-allow-expanding-permission-prompts-on-ios-to-see-the-full ,
  https://claudeissues.com/issue/28569-ios-remote-control-permission-prompt-buttons-prone-to-mis-taps-no-correction-mec
- Claude, visual and interactive content (weather and recipes; on mobile, weather is text; custom
  visuals are web/desktop only): https://support.claude.com/en/articles/13641943-visual-and-interactive-content
- Claude Artifacts on mobile: https://www.anthropic.com/news/artifacts
- ChatGPT Intelligent UI / visual answers (Oct 2026): https://macrumors.com/2026/10/07/chatgpt-intelligent-ui
- Perplexity answer UI (source chips, Answer/Links/Images tabs), design teardowns:
  https://aiuxplayground.com/teardowns/perplexity/citations , https://www.925studios.co/blog/perplexity-design-breakdown
- Raycast iOS (background AI chats with Live Activities, Control and Lock Screen widgets to start
  a chat): https://raycast.com/changelog/ios , https://www.raycast.com/blog/raycast-for-ios

Push and signing:
- Expo push token request shape (`exp.host/--/api/v2/push/getExpoPushToken`, fields `type`,
  `deviceId`, `development`, `appId`, `deviceToken`, `projectId`), from `expo-notifications`
  source: https://app.unpkg.com/expo-notifications@0.31.3/files/src/getExpoPushTokenAsync.ts
- Expo push FAQ: https://docs.expo.dev/push-notifications/faq/
- Free vs paid developer accounts (App Groups available, push not, 7-day profiles):
  https://expo.dev/blog/apple-developer-program-explained-free-vs-paid

Repo (facts this plan relies on):
- Rich detector cases: `Packages/PaseoCore/Sources/PaseoStore/Rich/RichContentDetector.swift:15-51`.
  Mermaid deliberately undetected: `Packages/PaseoCore/Tests/PaseoStoreTests/Rich/RichContentDetectorTests.swift:704-706`.
- Card chrome, fixed 320 pt images, LPLinkView 160 pt cap, the web slot logic:
  `Packages/PaseoUI/Sources/PaseoUI/Conversation/Prose/Rich/ClaudeRichBlocks.swift`.
- Agent snapshot fields (`activeTurn.startedAt`, `requiresAttention`, `pendingPermissions`,
  `lastUsage`): `Packages/PaseoCore/Sources/PaseoProtocol/Agents.swift:29-64`.
- Tool call kinds: `Packages/PaseoCore/Sources/PaseoProtocol/Timeline.swift:154-165`.
  PR checks: `Checkout.swift:87-124`.
- Daemon push is Expo-only: `paseo-reference/packages/server/src/server/push/push-service.ts`.
  Token message: `paseo-reference/packages/protocol/src/messages.ts:3127`.
- Download route without `Range`: `paseo-reference/packages/server/src/server/bootstrap.ts:869-925`.
- Upstream Mermaid host and runtime: `paseo-reference/packages/app/src/components/markdown/fence/mermaid/`.
- Local-only notification limits: `docs/research/10-notifications.md`.
