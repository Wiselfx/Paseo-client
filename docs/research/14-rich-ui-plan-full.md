# 14 (full) — Rich native UI: cards, media, widgets, Live Activities

Uncapped version of `14-rich-ui-plan.md` (same decisions; nothing trimmed for length).

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
- **Needs protocol**: a daemon or protocol change, so out of our control (the daemon is never
  changed by us; this means waiting on upstream).

| # | Card / surface | Status today |
|---|---|---|
| C1 | Image | exists, needs the pipeline |
| C2 | Image gallery | new |
| C3 | Video | E3 basics, needs a poster and download |
| C4 | Audio | E3 basics, needs a waveform row |
| C5 | YouTube | E3 inline play, add a title |
| C6 | Link | exists (LPLinkView), redo |
| C7 | GitHub link | new |
| C8 | Web artifact + artifact page | E3 sizing, page is new |
| C9 | Mermaid diagram | missing (upstream has it) |
| C10 | File (Quick Look) | path chip only today |
| C11 | Turn changes | new |
| C12 | Terminal output + test chip | plain text today |
| C13 | PR & checks | PR pane only today |
| C14 | Map | exists (M17), keep |
| C15 | Conversation media sheet | new |
| C16 | Context and cost charts | meters exist, charts new |

### C1. Image

- **Purpose.** Screenshots (Playwright, simulator, browser), generated assets, plots.
- **Trigger.** Detector `.bareImageURL`, `.localImage`, authored `![alt](url)`
  (`PaseoStore/Rich/RichContentDetector.swift`).
- **Anatomy.** Media card with no metadata strip. The image is the card. A 0.5 pt border, so
  white screenshots don't bleed into the light background.
  - Height follows §1.3. This replaces today's fixed `height: 320` (`ClaudeRichBlocks.swift:408`).
  - Animated GIF/APNG show their first frame in the transcript, with a small "GIF" badge in the
    accessory corner, and animate only in the viewer.
- **Interactions.**
  - Tap → full-screen viewer (§4.6).
  - Long-press: Share, Copy image, Save to Photos, Show in Files (local only), Open in Safari
    (remote only).
- **Data.**
  - Have: URLs are in prose; local paths are read through the daemon (`FileExplorerRequest`,
    `acceptBinary`, returns base64 `image`).
- **SwiftUI or UIKit.** SwiftUI view over a pipeline-provided `UIImage`. `AsyncImage` is retired:
  it can't downsample, can't report size early and can't share a cache.

### C2. Image gallery

- **Purpose.** Agents often post several screenshots in a row (before/after, three breakpoints).
  Today they stack into a tall column.
- **Trigger.** Two or more image blocks that are adjacent in document order, separated only by
  blank lines. The grouping is a pure Core pass over detector output: a new
  `RichContentBlock.imageGroup([…])`, or a post-pass in `ClaudeRichSplice`, tested on Linux.
- **Anatomy.** Media card with grid layouts:
  - 2 images: side by side, each 1:1;
  - 3 images: one large 2:3 on the left, two stacked on the right;
  - 4 images: 2×2;
  - 5 or more: 2×2, with the last tile reading "+N" on a dim scrim.
  - 2 pt gutters, with the card radius on the outer corners only.
  - Tiles crop with `scaledToFill` (the viewer shows the full frame).
- **Interactions.**
  - Tap a tile → the viewer opens at that index, with a zoom transition from that tile.
  - Long-press a tile → that image's menu.
- **Data.** Have (the same as C1).
- **SwiftUI or UIKit.** SwiftUI `Grid`, with fixed geometry computed from the count (no
  measuring).

### C3. Video

- **Purpose.** Screen recordings from simulators, browser tests (Playwright `video.webm` is
  common; `.mp4` from `xcrun simctl io recordVideo`), and generated clips.
- **Trigger.** A new detector case, `.localMedia(path, kind: .video)` for
  `.mp4 .mov .m4v`, plus remote URLs with those extensions. `.webm` isn't playable by AVFoundation,
  so it stays a file card (C10) that opens in Quick Look, which also can't play it, so the file
  card offers Share.
- **Anatomy.**
  - Media card. The poster frame is at the track's natural ratio, or 16:9 until known.
  - A centered 44 pt play glyph sits on a glass circle (`.glassEffect`, consistent with
    `GlassIconButton`), with a duration badge bottom-right.
  - Metadata strip: file name · size.
- **Interactions.**
  - Tap → the poster crossfades (`Motion.fade`) into an inline `AVPlayerViewController` in the
    same frame, with native controls, PiP and full screen.
  - Long-press: Share, Save to Photos, Show in Files.
- **Data.**
  - Remote: Have. AVPlayer streams it.
  - Local: Partial.
    - The socket file read caps at 64 MB (`WorkspaceShare.swift`), so local videos download whole
      into `Caches/daemon-media` before they play.
    - The daemon's HTTP route `/api/files/download` has no `Range` support
      (`paseo-reference/packages/server/src/server/bootstrap.ts:869-920`, it streams the whole
      file), so AVPlayer can't stream from the daemon.
    - Files over 64 MB need a protocol change (chunked socket reads or `Range`): **needs
      protocol**.
  - Over 20 MB, the card shows the size and waits for a tap before downloading. The copy needs the
    user's approval.
- **SwiftUI or UIKit.** UIKit (`AVPlayerViewController` in a representable). Native transport
  controls, PiP and AirPlay come only from AVKit.

### C4. Audio

- **Purpose.** TTS output, sound assets in game or app work, voice notes the agent produced.
- **Trigger.** `.localMedia(path, kind: .audio)` for `.mp3 .m4a .wav .aac .caf .aiff`, plus
  remote URLs with those extensions.
- **Anatomy.** Row card, 56 pt:
  - a 44 pt play/pause button;
  - a 48-bar waveform, computed once off main from downsampled PCM;
  - elapsed / duration in monospaced digits;
  - the file name above in `.caption`.
  - Played bars use `Palette.ink`; unplayed bars use `Palette.tertiaryInk`.
- **Interactions.**
  - Tap play.
  - Drag on the waveform scrubs (UIKit pan, R-3), with `Haptics.selection()` at the start and end
    only.
  - Long-press: Share, Show in Files.
- **Data.** Same as C3. Audio files are small, so the 64 MB cap rarely matters.
- **SwiftUI or UIKit.** SwiftUI row, an `AVAudioPlayer` owned by `MediaPlaybackCoordinator`, and
  `Canvas` for the waveform (one draw, no per-bar views).

### C5. YouTube

- E3 delivers the 16:9 thumbnail, in-place playback and "Open in YouTube".
- **This plan adds a metadata strip:** the title (2 lines) · the channel.
  - Source: YouTube's public oEmbed
    (`https://www.youtube.com/oembed?url=<watch>&format=json`), fetched once and cached with the
    link metadata.
  - Until it arrives (or if it fails), the strip shows `youtube.com · <id>` (doc 05's existing
    fallback).
- **Data.** Have (the URL). oEmbed is a third-party call, the same class as the thumbnail fetch.
- **SwiftUI or UIKit.** As in E3.

### C6. Link

- **Purpose.** Docs, issues and references the agent cites.
- **Trigger.** Detector `.linkCard` (standalone bare URL), unchanged.
- **Anatomy.**
  - Drop `LPLinkView` as the renderer. Today it is `LinkPreviewView`, capped at 160 pt
    (`ClaudeRichBlocks.swift:285-297`). LPLinkView has its own look, can't take our tokens,
    resizes after load (a layout jump), and draws a different card per site.
  - Keep `LPMetadataProvider` for metadata only, and render our own card:
    - With a metadata image (og:image): a media card with the image slot fixed at 1.91:1 (the OG
      standard, so no jump), then the title (2 lines) and `domain` + display URL (doc 05 §1.1
      trimming rules).
    - Without one: a row card with a 32 pt favicon (radius `Radius.sm`), title, and domain.
- **Interactions.**
  - Tap → `SFSafariViewController` sheet. That already exists for the file preview in E3; reuse
    it.
  - Long-press: Open in Safari, Copy link, Share, Add to chat (pastes the URL into the composer).
- **Data.** Have (the URL). The metadata fetch is client-side.
- **SwiftUI or UIKit.** SwiftUI card. The Safari sheet is UIKit.

### C7. GitHub link

- **Purpose.** The most common links a coding agent prints: PRs, issues, commits, repos, CI runs.
- **Trigger.** A pure Core parser over the `.linkCard` URL: `github.com/<o>/<r>/pull/<n>`,
  `/issues/<n>`, `/commit/<sha>`, `/actions/runs/<id>`, or the repo root. Unit-tested.
- **Anatomy.** Row card:
  - glyph by kind (`arrow.triangle.pull`, `smallcircle.filled.circle`, `point.3.connected…` for a
    commit);
  - title;
  - meta: `owner/repo #123`;
  - a `StatePill` for state: Open, Draft, Merged or Closed (upstream labels).
  - Same-repo PRs that match the workspace's PR become C13 instead.
- **Data.**
  - Same repo as the current workspace: **Have** via forge search (`ForgeSearch.swift`: title,
    state, labels, number).
  - Other repos: Partial. Fall back to the C6 metadata path (GitHub's OG image is a good card).
  - A "get PR by URL" request for arbitrary repos: **needs protocol**. Not worth asking for.
- **SwiftUI or UIKit.** SwiftUI.

### C8. Web artifact (visualize, raw SVG, HTML) and the artifact page

- **Purpose.** Claude-style artifacts: interactive visualizations and diagrams the agent drew.
- **Trigger.**
  - Today: ```` ```visualize ```` and raw `<svg>` (detector).
  - New: a "Preview" button in the header of ```` ```html ```` and ```` ```svg ```` code blocks.
    Code fences are never auto-rendered (§6).
- **Anatomy (inline).** E3's sizing, inside the media card. The header keeps "Visualization" /
  "SVG" and "View source" (existing copy). A new trailing "Open" (approved in E3) appears whenever
  the content is clipped, and in the menu otherwise.
- **Anatomy (artifact page).** A full-screen page (`fullScreenCover` with a zoom transition from
  the card):
  - **Top bar:** close (glass circle, left); title from `<title>`, then the first `<h1>`, then the
    kind label; a menu (right) with View source, Copy source, Share as .html, Reload.
  - **Body:** the same document, uncapped and scrollable, edge to edge with the safe area. It
    follows the app's color scheme (fixing doc 05 §6.7's always-dark export).
  - **Source view:** the code view with the existing highlighter, toggled in place with
    `Motion.fade`.
  - **Bridges:** visualize bridges (`sendPrompt`, `saveState`/`loadState`, doc 05 §2) work on the
    page too. `sendPrompt` closes the page and steers the conversation, as upstream does.
  - **Export:** `ShareLink` of a self-contained `<slug>.html` file.
- **Data.** Have. Everything is in the prose.
- **SwiftUI or UIKit.**
  - The page is SwiftUI. The web view is the existing `SandboxedHTMLView` (UIKit), leased from
    the pool.
  - The page gets its own slot, which outranks transcript slots; transcript cards fall back to
    snapshots while the page is open.

### C9. Mermaid diagram

- **Purpose.** Agents explain architecture and flows with Mermaid all the time.
  - Upstream renders it natively: `packages/app/src/components/markdown/fence/mermaid/host.native.tsx`,
    capped at 480 px, with a full-screen viewer.
  - Our detector explicitly drops it (`RichContentDetectorTests.swift:704-706`).
  - It isn't tracked in `docs/PARITY.md`. **Parity gap.**
- **Trigger.** A ```` ```mermaid ```` fence (a new detector case; unclosed fences stay code while
  streaming).
- **Anatomy.**
  - Media card. While the fence streams, it shows the code block. On close, the code is replaced
    by the diagram.
  - The diagram is rendered once in a pooled `WKWebView` running a bundled offline Mermaid
    runtime. Port the build idea of upstream's `runtime/html.gen.ts`; it's 3.5 MB, so it ships as
    a resource and loads with `loadFileURL`, not as a Swift string.
  - Mermaid is snapshotted to a `UIImage` at 2× slot width and cached by
    `hash(source + scheme)`. The transcript shows only the image, so zero live web views per
    diagram.
  - Height: the diagram's natural ratio, capped at 480 pt (upstream's value). Above the cap the
    diagram scales to fit and shows "Open".
  - Render error: the slot shows the source as code, plus the upstream error string.
- **Interactions.**
  - Tap → full-screen viewer: the live SVG in the artifact page, so the text stays sharp at zoom,
    with pinch-zoom.
  - Long-press: View source, Copy source, Share image.
- **Data.** Have.
- **SwiftUI or UIKit.** A SwiftUI card showing an image. The renderer is an off-screen UIKit web
  view.

### C10. File (with Quick Look)

- **Purpose.** Agents produce PDFs, CSVs, zips, `.usdz`, `.docx` reports, and paths to
  everything.
- **Trigger.** Detector `.localFileLink` (today it renders as `RichPathChip`, `ClaudeRichBlocks.swift:596`).
  The chip stays for paths inside sentences. A standalone path line becomes a file card.
- **Anatomy.** Row card:
  - the UTType icon (SF Symbol by type family);
  - the file name;
  - meta: the parent directory (middle-truncated) · size;
  - a trailing chevron;
  - PDFs get a 44 pt first-page thumbnail (PDFKit, off main) in place of the glyph.
- **Interactions.**
  - Tap: text, code and image files open in the workspace file viewer (exists:
    `Workspace/WorkspaceFileViewer.swift`).
  - Everything else downloads (socket read, 64 MB cap) into the cache and opens in
    `QLPreviewController`. That covers PDF, CSV, Office, Keynote, USDZ (with AR) and audio/video
    fallbacks.
  - Long-press: Share, Add to chat (exists from M7c/M17), Copy path.
- **Data.**
  - Have: the path and the read.
  - Partial: the size needs a directory listing of the parent, lazily on appear, cached. If it's
    absent, the meta shows only the directory.
- **SwiftUI or UIKit.** SwiftUI card; Quick Look is UIKit.

### C11. Turn changes

- **Purpose.** The single most useful fact about a coding turn: what files changed. Today it's
  buried in the collapsed work group.
- **Trigger.** A completed assistant turn with one or more `edit`/`write` tool calls
  (`ToolCallDetail.edit/.write`, `PaseoProtocol/Timeline.swift:156-157`). It shows at the end of
  the turn, after the final prose.
- **Anatomy.** Row card:
  - a `doc.badge.ellipsis`-style glyph;
  - the title: an "N files changed" style label (the upstream string if one exists, else needs
    copy approval);
  - meta: the first 2 file names + "and N more";
  - trailing: `DiffStat` (+120 −33, the existing component);
  - expands on tap (`Motion.disclosure`) to a per-file list. Each row has the path, its
    `DiffStat`, and a tap that opens that file's diff.
- **Data.**
  - Have. A pure `TurnChangeSummary` in PaseoStore, built incrementally with the turn (P4 tail
    rebuild). Counts come from `unifiedDiff` when present, else from line counts of
    `oldString`/`newString`. `write` counts as all added. Linux-tested.
  - Opening a diff uses the existing Changes diff view when the file is still dirty, else the
    tool call's own diff (`ClaudeDiffView`).
- **SwiftUI or UIKit.** SwiftUI.

### C12. Terminal output and the test chip

- **Purpose.** Shell output is where builds and tests speak. Today it's plain text, often full of
  raw `ESC[31m` escapes.
- **Trigger.** `ToolCallDetail.shell` output (`Timeline.swift:154`) inside the work group's tool
  detail (`Conversation/Turn/ClaudeToolDetail.swift:28`).
- **Anatomy.**
  - A terminal surface (`Palette.codeSurface`, `.codeSmall`), with ANSI SGR colors mapped to a
    16-color palette (stored in `Palette` as `ansi…`), bold and dim. Cursor movement and other
    codes are dropped.
  - It shows the last 12 lines, with "Show all" (existing expand pattern) opening a sheet.
  - Exit code as a `StatePill`: 0 = quiet success ink; non-zero = failure ink.
  - **Test chip:** when the output parses as a known runner summary, a compact chip shows
    "✓ 128 ✗ 2 ◌ 4" next to the exit pill. Runners: swift test / XCTest, Jest/Vitest, pytest,
    cargo test, go test.
- **Data.** Have. `AnsiText` (SGR → attributed runs) and `TestSummaryParser` are pure PaseoStore
  types, Linux-tested against captured outputs.
- **SwiftUI or UIKit.** SwiftUI `Text` from `AttributedString` runs. Not SwiftTerm: a terminal
  emulator per tool call is far too heavy.

### C13. PR & checks

- **Purpose.** "I opened PR #42" should show whether CI is green without opening the panel.
- **Trigger.** A GitHub PR URL (C7 parser) whose number matches the workspace's
  `CheckoutPrStatus` (`PaseoProtocol/Checkout.swift:87-124`).
- **Anatomy.** Row card:
  - PR glyph, title, `#42 · head → base`;
  - a state pill;
  - checks summary: a small ring (Swift Charts `SectorMark`, or three `StatusDot`s with counts)
    for passed/failed/pending, plus the review decision.
  - It updates live from the existing checkout subscription, with no polling.
- **Interactions.**
  - Tap → the PR pane (exists: `Workspace/WorkspacePRPane.swift`).
  - Long-press: Open on GitHub, Copy link, Add failing check to chat (exists as "PR check Add to
    chat" from V3).
- **Data.** Have (`checks`, `checksStatus`, `reviewDecision`, `isDraft`).
- **SwiftUI or UIKit.** SwiftUI.

### C14. Map

- **Status.** It exists (M17): strict detector, `MKMapSnapshotter` card, opens Apple Maps.
- **Change.** Move it onto `PaseoCard`.
- **No expansion** (§6).

### C15. Conversation media sheet

- **Purpose.** "Where was that screenshot?" iMessage's Details → Photos/Links, and Claude's
  artifact list.
- **Trigger.** A conversation menu item (header menu) → a sheet.
- **Anatomy.** `SheetScaffold` with a segmented control over three tabs:
  - **Media:** a 3-column square grid of images, video posters, Mermaid and artifact snapshots;
  - **Links:** C6 rows;
  - **Files:** C10 rows.
  - Newest first. Tapping jumps to the item in the transcript (the existing turn jump from U5),
    or opens the viewer.
- **Data.** Partial. It covers loaded turns. Older history needs a timeline window fetch (the
  existing `before` paging) on demand. A `ConversationMediaIndex` in the store, appended per turn.
- **SwiftUI or UIKit.** SwiftUI `LazyVGrid`.

### C16. Context and cost charts

- **Purpose.** Answer "how full is the context, what did this cost" at a glance.
- **Trigger.** The existing context sheet (`Conversation/Sheets/ClaudeContextSheet.swift`) and the
  existing usage meters.
- **Anatomy.**
  - A context gauge (`Gauge` with `.accessoryCircularCapacity` style, used/max tokens).
  - A per-turn bar chart of output tokens and cost (Swift Charts `BarMark`, 1 bar per turn, the
    last 30).
  - Cost by model as a horizontal bar list.
  - Charts follow the dataviz rules: neutral ink, one accent, no legend when there's one series.
- **Data.**
  - Have: `AgentUsage` on `turn_completed`/`usage_updated` (`AgentTimeline.swift:108-109`).
  - Partial: only turns observed live carry usage; the projected history doesn't. The chart says
    so by starting where data starts. Full history: **needs protocol**.
- **SwiftUI or UIKit.** SwiftUI Charts (already linked: `Sidebar/ClaudeUsageReportsSheet.swift:2`).

---

## 3. System surfaces

### 3.0 The hard constraint, stated once

There is no push server. The daemon's only push path is Expo push
(`paseo-reference/packages/server/src/server/push/push-service.ts`). It POSTs
`{to, title, body, data, sound}` to `exp.host` for tokens registered with `register_push_token`.
It has:
- no APNs `liveactivity` push type;
- no widget push type (`content-changed`, WWDC25 "What's new in widgets");
- no `content-available` or `mutable-content`.

So:
- **Live Activity updates while the app is suspended: impossible** without a daemon change.
- **Widget push reloads: impossible** without a daemon change.
- **Plain alert pushes when the app is closed: possible without a daemon change** (§3.7), at the
  cost of a paid Apple Developer account and an Expo project.

Everything else below works on local updates only: the app writes state while it runs, and
extensions read it.

**Plumbing for all extensions.**
- One App Group (`group.com.wiselfx.paseoclient`).
- A `GlanceSnapshot` value type in PaseoStore (Codable, Linux-tested). Per host it holds:
  - agents: id, title, project, provider, status, `requiresAttention`, `attentionReason`,
    `activeTurn.startedAt`, pending permission count, `updatedAt`;
  - `capturedAt`.
- The app writes it (throttled to 1 write per 10 s, plus on every attention change and on
  `scenePhase == .background`), then calls `WidgetCenter.reloadTimelines`. Reloads while the app
  is in the foreground don't count against the widget budget.
- **Privacy.** Agent titles are the user's prompts. In Lock Screen families every title is
  `.privacySensitive()`. A setting in the existing Settings → Notifications section ("show agent
  names on the Lock Screen", copy needs approval) defaults off.

**Signing reality (user decision).**
- Every extension is a new App ID with the App Group capability.
- On a free personal team, App Groups appear to work, but profiles expire every 7 days and App IDs
  are limited. Push and iCloud are not available at all.
- A widget + share extension doubles the App IDs per install.
- Confirm how the user signs the IPAs (`/Users/Shared/Paseo-ipas/` are unsigned) before ticketing
  §3.1–3.6.

### 3.1 Widgets: "Agents" (accept)

Home Screen sizes, from the HIG specs for a 393×852 device: small 158×158, medium 338×158; skip
large. The Lock Screen gets the accessory families.

- **Small.** A big numeral for agents needing you, in serif `Typography.hero`, a nod to the
  transcript. Under it: the label and the top agent's title (1 line). When nobody needs you, the
  numeral shows running agents instead, with the label changing to match.
  - Labels need copy approval. Prefer upstream's attention wording.
  - Tap → `paseo://agent/<id>` (the M20 routes exist).
- **Medium.** Up to 3 rows, each with a `StatusDot`, title, project, and a relative time
  (`Text(date, style: .relative)`, which the system refreshes for free). Attention rows sort
  first.
  - Each row is a `Link` to its agent.
  - Footer: the host name · "Updated" + relative `capturedAt`. The system ticks this label, so
    staleness is honest.
- **Accessory rectangular.** "2 need you · 3 running" plus the top title (redacted when locked).
- **Accessory circular.** The count of agents needing you, in a ring.
- **Accessory inline.** The same text as rectangular, one line.
- **Rendering.** Support `widgetRenderingMode == .accented` (iOS 26 glass/tinted Home Screens):
  status dots become shapes, not just colors (HIG: "convey meaning without relying on specific
  colors"). Margins are 16 pt (11 pt for groupings), with `ContainerRelativeShape` for inner
  corners.
- **Freshness.**
  - The timeline is a single entry from the App Group snapshot.
  - There's no polling. A widget that shows "Updated 2 h ago" is honest. A widget that guesses
    isn't.
  - Optional later spike (G22): the timeline provider opens a short PaseoKit connection itself
    (shared Keychain), fetches agents, and closes, within the daily reload budget. Widget
    extensions have a tight memory ceiling, and relay hosts need the Noise handshake in-process.
    Measure before promising.
- **Interactivity.** None in v1. HIG: "offer simple, relevant functionality and reserve complexity
  for your app". Approve/deny is rejected (§6).
- **SwiftUI.** WidgetKit (SwiftUI only).

### 3.2 Live Activity: "Agents at work" (accept, gated on G17)

- **What it is.** One activity for the whole app, not one per agent. The HIG says to "prefer a
  single Live Activity that uses a dynamic layout and rotates through events". It tracks the
  agents you are waiting on.
- **When it starts.**
  - ActivityKit only starts activities from the foreground, so start it when you send a prompt.
    Your own activity is hidden in the Dynamic Island while the app is foreground, so this is
    invisible until you leave.
  - Behind a setting, default on.
  - "Watched" = agents you prompted from this device whose turn is still running.
- **Presentations** (HIG sizes for the 393 pt width: compact 52×37, expanded/Lock Screen 371×84–160):
  - **Compact leading:** the crab glyph in `Palette.orange`, without a container (HIG: logo mark
    without a container), tinted by state.
  - **Compact trailing:** `Text(timerInterval: startedAt...distantFuture)` for one agent, or a
    count for several.
    - The timer ticks without updates.
    - In limited width (landscape, `isDynamicIslandLimitedInWidth`): leading only, a 28 pt circle.
  - **Minimal:** the glyph, with a dot when someone needs you.
  - **Expanded / Lock Screen:**
    - row 1: agent title (redacted when locked) + elapsed timer;
    - row 2: the current activity, a factual summary of the last tool call ("Running `swift
      test`", "Editing `Foo.swift`") from a pure `ActivityLine` in PaseoStore, never a quip;
    - row 3 (only when the agent emitted a todo list): `ProgressView(value: done, total:)` with
      "3 of 7".
    - With several agents: the one needing attention first, then "and 2 more" (copy approval).
    - Lock Screen margins are 14 pt. Use the default background; the custom tint is the crab
      orange key line only.
- **States.**
  - Running.
  - Needs you: the glyph swaps, the title says why, using the upstream attention reason. The
    update goes out with `alertConfiguration` once. That's the only alert; no duplicate local
    notification for the same event (HIG: don't use notifications alongside Live Activities for
    the same update).
  - Finished: end with `dismissalPolicy: .after(.now + 15 min)` (HIG: 15–30 minutes), showing a
    summary. The duration is formatted like the existing "Completed in" line.
- **Interactivity.** Tapping opens the agent through the deep link. There are no buttons
  (§6, and CarPlay disables them anyway).
- **Updates.** Only on meaningful change (phase, attention, todo count, tool kind), debounced to
  ≥ 5 s. Never per token.
- **The honesty problem, and the gate.**
  - Once iOS suspends the app (seconds after leaving), the activity can't learn that the turn
    finished. The timer would keep counting a turn that ended 20 minutes ago.
  - Set `staleDate = lastUpdate + 3 min`. The stale view greys the timer and shows "Updated" +
    relative time.
  - That's truthful but weak. Hence G17, a spike on `BGContinuedProcessingTask` (iOS 26). It's a
    user-initiated task that may continue in the background, with system progress UI, as long as
    it reports progress. "Keep watching this turn" would hold the socket and report todo progress
    (or indeterminate).
  - Apple warns that tasks with little progress are terminated first. On-device measurement
    decides:
    - if a running turn can be followed for ≥ 15 min in typical use, ship G18;
    - if not, defer the Live Activity until push exists. A Live Activity that lies is worse than
      none.
- **Free extras.** StandBy, the Mac menu bar (macOS Tahoe mirrors iPhone Live Activities) and the
  Watch Smart Stack all come from the same views. Adopt `.supplementalActivityFamilies([.small])`
  only if it costs < half a day. No custom Watch or CarPlay layouts.

### 3.3 Controls: Control Center, Lock Screen, Action button (accept)

- **"New agent".** `ControlWidgetButton` + `OpenIntent` → the draft screen (U2 `DraftChatView`),
  composer focused.
- **"Voice mode".** Opens the conversation in voice mode (M15), if the user uses it. Ask the user
  first.
- Glyphs are SF Symbols. Labels need copy approval or reuse existing ones ("New agent" appears in
  upstream).
- There are no toggles: Paseo has no binary state worth a toggle.
- Raycast iOS ships exactly this pattern (Control and Lock Screen widgets that start a chat).

### 3.4 App Intents, Shortcuts, Spotlight (accept, small)

- **`AgentEntity`.** Id, title, project, status. Its `EntityQuery` reads the App Group snapshot, so
  it works from any process without a socket. Adopt `IndexedEntity`, so agents appear in
  Spotlight with their project as subtitle. Tapping opens the agent.
- **`OpenAgentIntent`** (`OpenIntent`, parameter `AgentEntity`). It powers Spotlight, Shortcuts
  and Siri: "Open \<agent> in Paseo".
- **`NewAgentIntent(prompt: String?, project: ProjectEntity?)`** with `openAppWhenRun`. It opens
  the draft prefilled and doesn't send (user decision; sending from Siri without seeing the draft
  is a footgun).
- **`AgentsNeedingAttentionIntent`.** Returns `[AgentEntity]` for Shortcuts automations. Read-only.
- **App Shortcuts:** "New agent", "Agents needing attention".
- **Interactive snippets** (`SnippetIntent`, iOS 26): not now. Only consider them if Siri use
  appears.

### 3.5 Notification actions for permissions (user decision)

- **Today.** The app posts local attention notifications while alive (`App/Sources/NotificationCoordinator.swift`,
  doc 10).
- **Proposal.**
  - Add a `permission` category with **Allow** and **Deny** actions, both with the
    `.authenticationRequired` option (the device must be unlocked).
  - Map them only to the request's `AgentPermissionAction`s whose behavior is plain allow-once or
    deny (`Permissions.swift:78-98`).
  - Requests with suggestions, edits or questions (Pi `ask_user`, plan approvals) get no actions,
    only Open.
  - The notification body shows the tool name and the first line of the command, subject to the
    system's preview setting.
  - On action, iOS launches the app in the background. The app reconnects (LAN, Tailscale or
    relay) and sends `RespondToAgentPermissionRequest` within the background grace. On failure it
    posts "Couldn't reach host" (copy approval) with Open.
- **Security.** Approving a shell command you can only half see is the main risk. Mitigations:
  - unlock required;
  - only simple allow/deny;
  - never "allow always";
  - full detail one tap away;
  - off by default.
- **Why a notification and not a widget or Live Activity button.** Notifications have a native
  unlock gate, a native expanded view (the long-press shows the full body), and a single target
  per action.

### 3.6 Share extension (user decision, new feature)

- **Use.** Share a Safari URL, a Photos screenshot, or a file to Paseo, and pick a project or
  agent. For example, send a bug screenshot to the agent working on that app.
- **UI.** A compact SwiftUI sheet:
  - the host (if several);
  - the target (New agent in a project, or an existing agent, listed from the App Group snapshot);
  - a message field;
  - Send.
- **Sending.** Directly from the extension through PaseoKit (plain Swift, shared Keychain), using
  the existing upload (`FileTransfer.swift`, `T14`). If the host is unreachable, the payload goes
  to an App Group inbox, and the app shows it as a draft attachment on next launch.
- **Size.** L. It's the largest system-surface ticket, and the most "new feature" (R-6), so it
  needs the user's go-ahead.

### 3.7 Push without a server (user decision)

- **The path that needs no daemon change.**
  1. The paid Apple Developer Program, for the APNs entitlement.
  2. A free Expo account + EAS project, with our APNs key uploaded.
  3. The app registers for remote notifications. It sends the APNs device token to Expo's
     `exp.host/--/api/v2/push/getExpoPushToken` with
     `{type:"apns", deviceId, development, appId, deviceToken, projectId}`. That's the request
     `expo-notifications` itself makes; it's undocumented.
  4. The app sends the resulting `ExponentPushToken[…]` to every daemon via `register_push_token`.
  5. The daemon's existing attention pushes then reach a closed app.
- **Costs.** $99/year, an undocumented endpoint, and notification text (agent titles) transiting
  Expo.
- **What it doesn't unlock.** Live Activity or widget pushes.

### 3.8 Rejected or deferred system surfaces

See §6.
- Background Siri "send prompt": deferred.
- Watch app, CarPlay layouts: rejected.
- Focus filters: rejected.
- `BGAppRefreshTask` polling: rejected. It's opportunistic (about 30 s, at system whim) and gives a
  false sense of freshness; the widget's honest "Updated" label is better.

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
    autoplay off, sound on tap). It keeps the same frame, so there's no layout change.
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

**How to read it.**
- Ticket ids are proposed as **G1…** (rename freely).
- Size: S ≈ half a day, M ≈ 1–2 days, L ≈ 3–4 days for one worker.
- Every ticket follows `AGENTS.md`:
  - Core logic is in PaseoStore with Linux tests;
  - UI is checked on the Mac build gate;
  - no new dependencies.
- **[D]** = needs the user's decision before ticketing.

### Phase 0: Foundations (after E3 merges)

**G1. Card family.** Size M.
- **Scope:**
  - `PaseoCard` (media/row layouts, header, accessory, press style, context-menu helper);
  - `RichActions` environment object;
  - migrate the link, map, YouTube and web cards and `RichPathChip` hosts to it;
  - delete the private `RichCard`.
- **Files:** `DesignSystem/Components/PaseoCard.swift` (new), `Conversation/Prose/Rich/ClaudeRichBlocks.swift`,
  `ClaudeRichSplice.swift`, `ClaudeMarkdownView.swift` (environment injection).
- **Acceptance:**
  - every rich block uses `PaseoCard`;
  - style-lint is clean;
  - no closure parameters on cards;
  - visuals unchanged except for unified radius and border (screenshots in light, dark and pure
    black).

**G2. Media pipeline.** Size M.
- **Scope:**
  - `MediaPipeline` actor (§4.1): incremental size probe, downsampled decode, caches;
  - `MediaMetadataCache`;
  - replace `AsyncImage` and the fixed 320 pt height in `RichRemoteImage`/`RichLocalImage`.
- **Files:** `Conversation/Prose/Rich/ProseMarkdownImage.swift`, `ClaudeRichBlocks.swift`
  (images), new `Conversation/Prose/Media/MediaPipeline.swift`, `MediaMetadataCache.swift`.
- **Acceptance:**
  - a transcript with 20 screenshots scrolls without hitches on device;
  - the scroll position doesn't jump when images load;
  - a second visit renders with no fade;
  - memory stays under 150 MB with 20 images (Instruments note in the final message);
  - no decode on main (Time Profiler shot).

**G3. Full-screen viewer.** Size L.
- **Scope:** §4.6 (UIKit pager, zoom transition, drag-to-dismiss, chrome, Live Text, Save to
  Photos, Add to chat), used by chat images and the Files panel's image viewer.
- **Files:** new `Conversation/Prose/Media/MediaViewer*.swift` (UIKit + representable),
  `ClaudeMediaView.swift` (retire or adapt `ClaudeMediaViewer`), `RichImageViewer` removal,
  `Workspace/WorkspaceFileViewer.swift` (open in the viewer), `App/project.yml`
  (`NSPhotoLibraryAddUsageDescription`, copy approval).
- **Acceptance:**
  - the zoom-in/out transition matches the thumbnail;
  - dismiss follows the finger at 120 Hz and settles with no overshoot;
  - Reduce Motion gives a crossfade;
  - Live Text selects text from a screenshot;
  - VoiceOver announces "Image n of m".

### Phase 1: The artifacts coding agents actually make (highest value)

**G4. Mermaid diagrams.** Size L.
- **Scope:**
  - a detector case for ```` ```mermaid ```` (update the test at `RichContentDetectorTests.swift:704`
    by adding a new test file asserting detection; the old test asserts emptiness, so this ticket
    must **list it for the lead**: it is a contract change);
  - a bundled offline runtime resource;
  - `WebViewSlotPool` (extract it from `RichWebCard`);
  - an off-screen renderer → snapshot cache;
  - the card (§2 C9) and full-screen live view;
  - PARITY row.
- **Files:** PaseoStore `Rich/RichContentDetector.swift`, new `Conversation/Prose/Rich/Mermaid*.swift`,
  `Rich/RichWebContent.swift`, `Resources/mermaid-runtime.html`, `docs/PARITY.md`.
- **Acceptance:**
  - flowchart, sequence, class and gantt samples render in light and dark;
  - 10 diagrams in a transcript create at most 2 web views (log counter);
  - a streaming fence stays code until closed;
  - a syntax error shows the source and the error.
- **[D]** Bundle size: about 3.5 MB added to the app. Recommend yes.

**G5. Artifact page.** Size M.
- **Scope:** §2 C8 page:
  - title extraction;
  - source toggle;
  - Share as .html (scheme-aware);
  - Reload;
  - bridges on the page;
  - "Preview" on html/svg code blocks;
  - the "Open" entry from inline cards;
  - Files panel "Open full screen" for `.html`.
- **Files:** new `Conversation/Prose/Rich/ArtifactPage.swift`, `ClaudeRichBlocks.swift`, the
  Markdown code block view (in `ClaudeMarkdownView.swift`), `Workspace/WorkspaceFileViewer.swift`.
- **Acceptance:**
  - an inline card → page with the zoom transition;
  - `sendPrompt` from the page steers the conversation and closes the page;
  - the exported file opens correctly in Safari in both schemes;
  - code fences never auto-render.

**G6. Turn changes card.** Size M.
- **Scope:** `TurnChangeSummary` in PaseoStore (incremental with P4's tail rebuild, plus tests);
  the C11 card at turn end; tap to diff.
- **Files:** PaseoStore `Turn.swift`/`IncrementalTurnBuilder.swift` (additive field), new
  `TurnChangeSummary.swift` + tests, `Conversation/Transcript/ChatTurns.swift` (append card),
  new `Conversation/Turn/TurnChangesCard.swift`.
- **Acceptance:**
  - counts match `git diff --stat` on a fixture turn;
  - streaming edits update only the tail turn's card;
  - the row is `Equatable` and skipped when unchanged.
- **[D]** The title string: is there an upstream equivalent? If not, the user approves the copy.

**G7. Image galleries.** Size M.
- **Scope:** the adjacent-image grouping pass in PaseoStore (tests) and the C2 grid card wired to
  the G3 viewer.
- **Files:** PaseoStore `Rich/` (new `RichImageGrouping.swift` + tests), `ClaudeRichSplice.swift`,
  new `Conversation/Prose/Rich/RichGalleryCard.swift`.
- **Acceptance:**
  - layouts for 2, 3, 4 and 7 images;
  - tap opens the viewer at the right index with the zoom from that tile;
  - single images unaffected.

**G8. Terminal output and the test chip.** Size M.
- **Scope:** `AnsiText` (SGR parser) and `TestSummaryParser` in PaseoStore, with tests from
  captured runner outputs; the shell tool detail renders colored, tail-truncated output, the exit
  pill and the test chip; `Palette` ANSI colors.
- **Files:** new PaseoStore `Rich/AnsiText.swift`, `Rich/TestSummaryParser.swift` + tests,
  `Conversation/Turn/ClaudeToolDetail.swift`, `DesignSystem/Palette.swift`.
- **Acceptance:**
  - no raw escape characters ever reach the screen;
  - the colors read in light, dark and pure black;
  - all 6 runner summaries parse;
  - parsing a 1 MB output takes under 50 ms on Linux CI.

**G9. Link cards v2 + GitHub cards + PR & checks card.** Size M.
- **Scope:**
  - C6 own-rendered link card from `LPMetadataProvider` (drop `LinkPreviewView`);
  - the C5 YouTube title strip (oEmbed);
  - a Core `GitHubURL` parser (tests);
  - C7 via forge search for same-repo items;
  - C13 bound to the checkout PR status.
- **Files:** `ClaudeRichBlocks.swift` (link section), new `Conversation/Prose/Rich/RichGitHubCard.swift`,
  PaseoStore new `Rich/GitHubURL.swift` + tests; `CheckoutStore` reads only.
- **Acceptance:**
  - no link card changes height after first layout (OG slot reserved 1.91:1);
  - a PR card for the workspace PR turns green live when checks pass;
  - links for other repos degrade to the metadata card.

**G10. File cards + Quick Look.** Size M.
- **Scope:**
  - C10 for standalone path lines;
  - lazy size from the parent listing;
  - the PDF thumbnail;
  - download to cache + `QLPreviewController` for non-text kinds;
  - the 64 MB cap message.
- **Files:** `ClaudeRichBlocks.swift` (`RichPathChip` sibling), new `Conversation/Prose/Rich/RichFileCard.swift`,
  `QuickLookPresenter.swift`; a PaseoStore detector tweak (standalone vs inline path) + tests.
- **Acceptance:**
  - a PDF, CSV, zip and docx each open in Quick Look;
  - text and code files still open in the workspace viewer;
  - nothing downloads until tapped (except the PDF thumbnail under 5 MB).

**G11. Video and audio.** Size L.
- **Scope:**
  - detector `.localMedia` + remote media URLs (tests);
  - the C3 poster card → inline AVKit;
  - the C4 audio row with waveform;
  - `MediaPlaybackCoordinator`;
  - the download policy (20 MB tap, 64 MB cap);
  - the audio session off main.
- **Files:** PaseoStore `Rich/RichContentDetector.swift` + new tests, new `Conversation/Prose/Media/VideoCard.swift`,
  `AudioRow.swift`, `MediaPlaybackCoordinator.swift`, `MediaState.swift` (kinds).
- **Acceptance:**
  - a simulator `.mp4` recording plays inline and in PiP;
  - two players never play at once;
  - scrolling away pauses;
  - no `AVAudioSession` call on main (Thread Checker clean).

**G12. Conversation media sheet.** Size M.
- **Scope:** `ConversationMediaIndex` (store, incremental, tests), the C15 sheet, the jump to the
  source turn.
- **Files:** PaseoStore new `ConversationMediaIndex.swift` + tests, new `Conversation/Sheets/ChatMediaSheet.swift`,
  the header menu entry (`Conversation/Screen/…` menu file).
- **Acceptance:**
  - opening the sheet on a 5k-row chat takes under 100 ms;
  - tapping an item lands on its turn;
  - the empty state uses `EmptyState` with existing or approved copy.
- **[D]** The menu label copy.

**G13. Context and cost charts.** Size S.
- **Scope:** a per-turn usage series in the store (live turns only, tests) and the C16 charts in
  the context sheet.
- **Files:** PaseoStore `ConversationContext.swift` (additive) + tests, `Conversation/Sheets/ClaudeContextSheet.swift`.
- **Acceptance:**
  - the charts honor the dataviz rules;
  - the chart starts where data starts, with no fake zeros;
  - VoiceOver reads the bar values (`accessibilityChartDescriptor`).

### Phase 2: System surfaces without push

**G14. App Group + Glance snapshot.** Size M. **[D] signing**
- **Scope:**
  - `GlanceSnapshot` (PaseoStore, Codable, tests);
  - the app-side writer (throttled, on background);
  - the App Group entitlement;
  - an empty `PaseoWidgets` extension target in `App/project.yml`;
  - the shared deep-link builder.
- **Files:** PaseoStore new `GlanceSnapshot.swift` + tests, `App/Sources/AppModel.swift`,
  `App/project.yml`, new `App/Widgets/`.
- **Acceptance:**
  - the snapshot round-trips;
  - writes stay at or under 1 per 10 s under streaming;
  - the extension builds on the Mac gate.

**G15. Agents widgets.** Size M.
- **Scope:** §3.1 small, medium and the three accessory families, accented mode, privacy
  redaction setting, deep links.
- **Files:** `App/Widgets/AgentsWidget*.swift`, Settings → Notifications (one toggle).
- **Acceptance:**
  - each family matches the HIG sizes;
  - tinted/clear Home Screens stay legible;
  - Lock Screen titles are redacted by default;
  - taps land on the agent;
  - "Updated" ticks without reloads.

**G16. Controls, App Shortcuts, Spotlight.** Size M.
- **Scope:** §3.3 + §3.4 (`AgentEntity` + `IndexedEntity`, `OpenAgentIntent`, `NewAgentIntent`
  without autosend, the attention query, two controls).
- **Files:** new `App/Intents/*.swift`, `App/Widgets/Controls.swift`, `App/Sources/PaseoClientApp.swift`
  (routing).
- **Acceptance:**
  - Spotlight finds an agent by title;
  - the Action button opens New agent with the composer focused;
  - Shortcuts lists the actions with approved names.

**G17. Spike: can we keep watching in the background?** Size S, go/no-go.
- **Scope:**
  - A throwaway branch. `BGContinuedProcessingTaskRequest` submitted when the user leaves the app
    during a running turn.
  - Hold the socket, report progress (todos or indeterminate steps), and log survival time on
    device: LAN, Tailscale, relay, locked and unlocked.
  - Also measure `beginBackgroundTask` alone.
- **Acceptance:** a table of survival times and system UI screenshots, plus a go/no-go
  recommendation for G18.

**G18. Live Activity "Agents at work".** Size L. **[D] gated on G17 (or G21)**
- **Scope:**
  - §3.2: attributes/content state, all presentations, limited width, stale view, attention alert;
  - end with 15 min dismissal;
  - the setting;
  - a pure `ActivityLine` (PaseoStore, tests).
- **Files:** `App/Widgets/AgentsLiveActivity.swift`, PaseoStore new `ActivityLine.swift` + tests,
  `App/Sources/AppModel.swift` (lifecycle), Settings toggle.
- **Acceptance:**
  - no update storm (≤ 1 per 5 s, logged);
  - a stale state appears when updates stop;
  - attention alerts once;
  - the activity ends on finish;
  - the Mac menu bar shows it (manual check).

**G19. Permission notification actions.** Size M. **[D]**
- **Scope:** §3.5.
- **Files:** `App/Sources/NotificationCoordinator.swift`, PaseoStore `AttentionCenter.swift` (an
  action mapping, tests).
- **Acceptance:**
  - Allow/Deny only on simple requests;
  - unlock required;
  - a background reconnect sends the response;
  - failures post an Open notification.

**G20. Share extension.** Size L. **[D] new feature**
- **Scope:** §3.6.
- **Files:** new `App/Share/`, `App/project.yml`, the PaseoKit connection reuse.
- **Acceptance:**
  - a Safari URL and a Photos screenshot reach a chosen agent;
  - an offline host falls back to the inbox;
  - memory stays under the extension limit.

### Phase 3: Needs money, upstream or more evidence

**G21. Push via Expo.** Size M. **[D] paid account + Expo project.** §3.7. It unblocks closed-app
attention notifications only.

**G22. Widget self-refresh.** Size M spike. A PaseoKit fetch inside the timeline provider; measure
memory and relay viability.

**G23. Daemon-side asks**, as an upstream issue list, not tickets:
- `Range` support on `/api/files/download`;
- chunked socket reads over 64 MB;
- per-turn usage in the projected timeline;
- APNs `liveactivity` and `widgets` push types in `PushService`.

**Order by value per effort:** G1 → G2 → G4 → G3 → G6 → G5 → G8 → G9 → G7 → G10 → G14 → G15 →
G16 → G17 → G11 → G12 → G13 → (decisions) G18–G21.

G4 (Mermaid) goes ahead of G3 because it is a visible parity gap and depends only on G1. G3 is
the biggest feel upgrade, but it's larger.

**Decisions to collect in one message to the user:**
1. How do you sign the IPA (free or paid team)? This gates G14–G21.
2. Bundle the Mermaid runtime (about 3.5 MB)? Recommend yes.
3. Live Activity only if G17 proves it can stay truthful? Recommend yes.
4. Allow/Deny from notifications? Recommend yes, off by default.
5. Share extension? Recommend later, after widgets.
6. Pay for the Apple Developer Program and use Expo for closed-app notifications?
7. New copy strings, listed per ticket: turn changes title, widget labels, Live Activity "and N
   more", "Updated", download size prompt, media sheet name, Save to Photos permission text.

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

---

# Addendum (2026-11-11, appended by the lead)

The research pass couldn't write these sections, so the lead wrote them from this plan, the repo
and the upstream reference. Nothing above was changed. Section numbers continue from §7.

## 8. What competent apps do

These are the patterns that well-built chat, assistant and developer apps converge on for rich
answers. No single app is the model; each pattern is here because it solves a real problem. Apple's
HIG is cited where it states the same rule.

### 8.1 In the transcript

- **Text stays the spine; rich blocks are punctuation.**
  - Good apps never turn an answer into a dashboard. A card appears only where the content *is* the
    object: an image, a diagram, a file, a link the user will open.
  - Everything else stays prose. A card that only restates the prose is noise.
- **One card grammar.**
  - Every rich block shares the same container, corner, border, header anatomy and long-press menu.
  - Users learn the grammar once. A new kind feels familiar on first sight.
  - Apps that give every block its own chrome look assembled, not designed.
- **Reserve space before content arrives.**
  - Size comes from metadata (dimensions, `viewBox`, aspect ratio, a fixed 16:9) before any bytes
    load. Only the inside fades in; the frame never moves.
  - A transcript that jumps while you read is the most visible sign of an unpolished chat app.
- **Progressive fidelity.**
  - Placeholder → low-resolution → full, each a crossfade in the same frame.
  - Heavy renderers (web views, players, diagram runtimes) start only when the block is on screen,
    and are torn down or pooled when it's far away.
- **Tap opens, long-press offers.**
  - A tap does the one obvious thing: full screen for media, open for a link, play for audio.
  - Secondary actions (copy, save, share, open externally, view source) live in a context menu
    with a preview (HIG: Context menus). There are no visible button rows on every card.
- **Full screen is a place, not a popup.**
  - Images, diagrams and artifacts open in a viewer that zooms from the card's frame and drags down
    to dismiss back into it. Zoom and pan are native, Live Text works, and share is one tap.
  - The return transition lands exactly where the user left the transcript.
- **Inline media plays inline.**
  - Video and audio play in place with system controls. Leaving the app to play a clip is treated
    as a failure.
  - Only one thing plays at a time. Scrolling far away pauses it.
  - Audio respects the silent switch unless the user started it.
- **Artifacts get a home.**
  - Generated documents, diagrams and pages open as full-screen pages, with source, copy, share and
    reload.
  - The transcript keeps a compact card that points to it. Big content never lives in a scrolling
    box inside a scrolling box.
- **Code and diffs read like code.**
  - Monospace, horizontal scroll instead of wrapping (wrap as an option), visible line counts, a
    copy button on the block, and syntax colour that respects light and dark.
  - Diffs show counts first and expand on demand.
- **Status is quiet and truthful.**
  - Running work shows elapsed time and the current step. It doesn't use fake progress bars.
  - Finished work collapses to a one-line summary that can be reopened.
  - Errors say what failed and offer the one retry that makes sense.
- **Tables respect the screen.**
  - Wide tables scroll horizontally inside their block, with the first column pinned where that
    helps. They never shrink text to fit, and the page never scrolls sideways.

### 8.2 Outside the app

- **Glances, not mini-apps.**
  - Widgets show the one or two facts a person checks most (here: which agents need me, which
    are running) and deep-link straight to them (HIG: Widgets).
  - They say how fresh they are, and never pretend to be live when they aren't.
- **Live Activities are for a bounded task the user is waiting on** (HIG: Live Activities).
  - They have a clear start and end, a compact state, and they end promptly when the task ends.
  - An activity that keeps counting after the work stopped teaches the user to ignore it.
- **The Lock Screen is a privacy boundary.**
  - Content that could be private (prompts, file names, message text) is redacted when locked by
    default.
  - Consequential actions (approve, delete, send) require unlocking (HIG: Privacy).
- **Notifications carry enough to decide, and act only when it's safe.**
  - The title says who needs you; the body says what for. A thumbnail is attached when an image is
    the point.
  - Actions that change things require authentication.
- **Shortcuts, Spotlight and Controls are entry points, not features.**
  - They open the right screen fast: a new agent, the agent needing attention, a project.
  - They expose the app's nouns (agents, projects) as App Entities, so the system can find them.
- **Respect the network.**
  - Media doesn't auto-download in Low Data Mode or on expensive links. Large downloads ask
    first.
  - Thumbnails are small and cached. Failure is graceful and offline-aware.

### 8.3 What this means for Paseo

Every item above already maps onto §1–§5:
- §1.1 is the card grammar;
- §1.3 is reserving space;
- §1.6 is lazy renderers;
- §4.6 is the full-screen place;
- C8 and G5 give artifacts a home;
- §3 sets the glance and privacy rules.

Two gaps were not covered above, and §9 and §12 add them: wide tables (§9.1), and network
etiquette (§12).

## 9. Lower-priority card refinements

Do these after Phase 1. Each one is small, uses `PaseoCard` or the prose renderer, and needs no
protocol change unless stated.

### 9.1 Wide Markdown tables

- **Today.** The table renderer measures columns (`MarkdownTableMetrics.swift`). A table wider than
  the prose column has nowhere to go.
- **Build:**
  - A table wider than the column scrolls horizontally inside its own block (a `ScrollView(.horizontal)`
    with `.scrollBounceBehavior(.basedOnSize)`), with a trailing fade edge that shows more exists.
  - The first column is pinned when it is a label column: every cell in it is short text (≤ 24
    characters), and the table has 4 or more columns.
  - A tap on the table's header strip opens it full screen (both axes scroll, pinch to zoom
    text), reusing the §4.6 viewer shell.
  - Never shrink the font to fit. Never wrap a numeric cell.
- **Perf.** Column widths are computed once per table in the document model (already memoised),
  never in `body`.
- **Size:** S.

### 9.2 The todo / plan card

- **Data.** Have:
  - `TimelineItem.todo(TodoList)`: items with `text`, `completed`, `status`
    (`pending`/`in_progress`/`completed`) and `activeForm` (`Timeline.swift:83-93`);
  - the `plan(text:)` tool detail (`Timeline.swift:162`).
- **Build:**
  - One row card per todo list:
    - the header reads "N of M done", with a thin progress bar in `Palette.secondaryInk`;
    - the in-progress item shows its `activeForm` text with the shimmer the status line already
      uses;
    - completed items are struck through in `tertiaryInk`.
  - It collapses to the header once every item is done.
  - Successive todo updates in one turn replace the card in place. One card per turn, never a
    stack of snapshots.
- **Plan text** (`plan` tool, or a `plan` permission's `metadata.planText`) renders as prose in a
  quiet quote-wash block with a "Plan" header. It shares the permission card's preview (§9.3).
- **Size:** S.

### 9.3 Previews in the permission card

- **Data.** Have, on `AgentPermissionRequest` (`Permissions.swift:12-38`):
  - `kind`, `name`, `title`, `description`;
  - `input` (raw provider JSON);
  - `detail` (a normalised `ToolCallDetail` when the daemon could build one);
  - `suggestions`, `actions`;
  - `metadata` (`planText`).
- **Build** a preview slot above the permission card's buttons, chosen from `detail` first:
  - **Edit / write:** a mini diff (the first 8 changed lines, the counts, "Show all" opens the
    full diff sheet).
  - **Shell:** the command in a mono block, the cwd as meta.
  - **Plan:** the plan text (§9.2), collapsed to 6 lines with "Show more".
  - **Fetch / web:** the URL as a link row, the domain as meta.
  - **Question:** the question form as today.
  - **Anything else:** the `input` JSON, pretty-printed and collapsed to 6 lines.
- **Rule.** `suggestions` widen authority: show them as a separate, explicit choice, never
  pre-selected (this is already in the doc comment; the card must honour it).
- **Size:** M.

### 9.4 Subagent cards

- **Data.**
  - Have: `ProviderSubagent` (`Subagents.swift:10-24`) with `title`, `description`, `status`,
    `toolCallId`, `subtitle`, `parentSubagentId` (when nesting is supported), and the timeline
    via `agent.provider_subagents.timeline.get`.
  - E3 §1 fixes the loading.
- **Build:**
  - The tool call that spawned a subagent (matched by `toolCallId`) renders as a row card:
    - the subagent's title;
    - a status dot;
    - the provider-owned `subtitle` (never parsed);
    - elapsed time while running;
    - a chevron.
  - A tap opens the subagent's timeline as a pushed page with the transcript's own renderer
    (read-only, no composer).
  - Nested subagents show as an indented list in that page's header, not as nested cards.
- **Size:** M (after E3).

### 9.5 Images in user bubbles

- **Data.**
  - **Partial.** The wire `user_message` item carries only `text`, `messageId` and
    `clientMessageId` (upstream `protocol/src/agent-types.ts:403`). Attachments are not echoed
    back.
  - So images are known only for messages this client sent in this session (the local tray at
    send time, keyed by `clientMessageId`).
  - History from another client or an earlier launch: **needs protocol** (attachments on
    `user_message`, or a lookup by message id).
- **Build:**
  - Messages sent from this device keep their images:
    - the composer tray's thumbnails move into a strip above the bubble text: up to 4 squares at
      64 pt, `Radius.sm`, "+N" on the last;
    - they stay keyed by `clientMessageId` in a small on-disk cache (the thumbnails only, LRU
      50 MB) so a relaunch keeps them.
  - A tap opens the §4.6 viewer.
  - Where nothing is known, the bubble shows nothing extra. Never a broken placeholder.
- **Size:** S (local), plus an upstream ask in G23.

## 10. Data needs

For each item: what it needs, and whether the protocol has it today.
- **Have:** works with today's messages.
- **Partial:** works for some cases; the limit is stated.
- **Needs:** requires a daemon or protocol change. It goes to the G23 upstream ask list, never a
  client hack.

| Item | Needs | Status | Source / field |
|---|---|---|---|
| C1 Image | the URL or workspace path; bytes | Have | prose URL; `FileExplorerRequest` + `acceptBinary` |
| C2 Gallery | the same as C1, ≥ 2 adjacent | Have | the document model |
| C3 Video, remote | the URL | Have | prose URL; AVPlayer streams |
| C3 Video, local ≤ 64 MB | the bytes | Partial | socket read capped at 64 MB; download-then-play |
| C3 Video, local > 64 MB or streaming | ranged reads | Needs | `/api/files/download` has no `Range` (`bootstrap.ts:869-925`) |
| C4 Audio | the same as C3 | Have / Partial | the same as C3 |
| C5 YouTube | the video id | Have | prose URL |
| C6 Link | the URL; OG metadata | Have | client-side fetch |
| C7 GitHub link, same repo | number, title, state, labels | Have | `ForgeSearch` |
| C7 GitHub link, other repo | the same | Partial | OG fallback; "get PR by URL": Needs (not worth it) |
| C8 Web artifact | the markup | Have | prose |
| C9 Mermaid | the fence source | Have | prose (detector change, G4) |
| C10 File | the path, read, size | Have / Partial | path + read: Have; size: parent listing on appear |
| C11 Turn changes | per-file counts | Have | tool-call `unifiedDiff` / `oldString` / `newString` |
| C12 Terminal output | the raw output | Have | tool-call output (ANSI kept) |
| C13 PR & checks | checks, state, review | Have | `checks`, `checksStatus`, `reviewDecision`, `isDraft` |
| C15 Media sheet | every media ref in the chat | Partial | loaded turns; older via `before` paging |
| C16 Context and cost charts | per-turn usage | Partial | `turn_completed` / `usage_updated` live only; history: Needs |
| §9.2 Todo / plan | items, status | Have | `TimelineItem.todo`, `plan` detail |
| §9.3 Permission preview | the normalised detail | Have | `AgentPermissionRequest.detail`, `input`, `metadata` |
| §9.4 Subagent card | list + timeline | Have | `agent.provider_subagents.list` / `.timeline.get` |
| §9.5 User bubble images, this device | the tray at send | Have (local) | `clientMessageId` |
| §9.5 User bubble images, history | attachments on the message | Needs | `user_message` has no attachments |
| §11 Notification thumbnail | the image bytes at alert time | Partial | local notifications only; push: Needs (Expo payload has no attachment) |
| 3.1 Widgets | the agent list snapshot | Have | `FetchAgentsRequest` → `GlanceSnapshot` |
| 3.2 Live Activity while suspended | server-driven updates | Needs | no APNs `liveactivity` push type |
| 3.4 App Intents / Spotlight | agents and projects | Have | the directory |
| 3.5 Permission notification actions | respond while backgrounded | Partial | needs a socket in the extension or app; see §13 |
| 3.7 Closed-app alerts | a push path | Partial | Expo `register_push_token`; paid account (decision) |

## 11. Notification image thumbnails

**When.** A local notification the app posts ("agent finished", "needs you") gets a thumbnail
only if the turn it describes produced an image the user would want to see:
- the last image block in the final assistant message;
- or a screenshot the agent attached.
- Never an avatar, never a decorative image, never a provider logo.

**How.**
- `UNNotificationAttachment` with a downscaled JPEG: longest side 600 px, quality 0.8, ≤ 300 KB.
  - It's written to a temp file in `Caches/notification-media` (the system copies it; delete it
    after `add` returns).
  - The image comes from the §4.1 pipeline's cache only. **Never download for a notification.**
    If the image isn't already decoded and cached, there's no thumbnail.
- Lock Screen privacy follows the §3 setting. When "show agent names on the Lock Screen" is off,
  no thumbnail either.
- Push (if G21 lands):
  - Expo's payload carries no attachment, so remote notifications get thumbnails only through a
    Notification Service Extension that fetches from the daemon.
  - That needs `mutable-content`, which the daemon doesn't send: **Needs**. Don't build it.

**Size:** S. Part of G19 or standalone after G2.

## 12. Network etiquette: no surprise downloads

**The rule.** Media downloads automatically only when the connection is cheap. Otherwise the card
shows what it would load and waits for a tap.

| Connection | Thumbnails ≤ 200 KB | Images ≤ 5 MB | Images > 5 MB, video, audio | YouTube, link previews |
|---|---|---|---|---|
| Wi-Fi / Ethernet, not constrained | auto | auto | tap (video: poster auto) | auto |
| Cellular, not constrained | auto | auto | tap, showing the size | auto |
| **Low Data Mode** (`isConstrained`) | auto | tap | tap | tap: a text-only link row |
| **Relay** connection | auto | auto ≤ 1 MB, else tap | tap | auto (it doesn't use the relay) |
| Offline | cache only | cache only | cache only | a text-only row |

**Rules:**
- **Detection.** One `NWPathMonitor` in PaseoKit publishes `isConstrained`, `isExpensive` and the
  interface type as a small `@Observable` value. The relay vs direct decision comes from the
  host session (it knows how it connected). Cards read one derived enum, `MediaFetchPolicy`, never
  the raw path (R-1).
- **Why the relay is special.** Relay traffic goes through a third-party server, end-to-end
  encrypted, and is slower. Large daemon-file reads through it are slow and cost the relay
  operator. Daemon files over 1 MB therefore wait for a tap on the relay, whatever the network.
- **The tap state.**
  - The reserved frame (§1.3) with a centred download glyph, the size if known ("2.4 MB"), and the
    file name.
  - One tap fetches it, with a progress ring in the same frame.
  - New copy, which needs approval (§15).
- **Never** prefetch off-screen media on a constrained or relay path. On unconstrained Wi-Fi,
  prefetch at most 1 screen ahead.
- **Settings.** No new setting in v1. The policy is fixed. If the user asks, a single "Download
  media automatically: Always / Wi-Fi only / Never" row can come later.
- **Size:** S. Part of G2.

## 13. Risk register and test strategy

### 13.1 Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Web views multiply and scrolling stutters | Medium | High | Hard cap of 2 live web views (§1.6); lazy creation on appear; snapshot when off screen; a perf gate in review |
| R2 | Layout jumps when media loads | Medium | High | Size reserved from metadata; fixed ratios for video and YouTube; frames never animate after first layout; a review check |
| R3 | Main-thread image decoding | Medium | High | §4.1 pipeline: `CGImageSource` thumbnails off main at display size; the cache keyed by URL + size |
| R4 | Mermaid runtime size and startup | High | Medium | Bundle once (decision); one shared offscreen web view renders → snapshot image; never a live view per diagram |
| R5 | Untrusted HTML artifacts reach the network or the app | Medium | High | Non-persistent data store; no message handlers except the height reporter; navigation intercepted; a CSP; no file URLs |
| R6 | The Live Activity lies (it keeps running after the turn ended) | High without push | High (trust) | Gated on the G17 spike; a stale-date on every update; it ends on background expiry |
| R7 | Lock Screen leaks prompts and file names | Medium | High | `.privacySensitive()` everywhere, the setting off by default, no thumbnails when off |
| R8 | Signing limits break extensions (7-day profiles, App ID caps) | High on a free team | Medium | Decision before G14; extensions behind a build flag so the main app ships without them |
| R9 | Video over 64 MB can't play | Certain | Low | A clear "Too large to preview" row with open/share; the upstream `Range` ask |
| R10 | Surprise data use on cellular, Low Data Mode or the relay | Medium | Medium | The §12 policy |
| R11 | Protocol drift: a new item kind breaks a card | Medium | Medium | Lenient decoding per item (E3 rule); unknown → an "unsupported item" row |
| R12 | Third-party embeds change (YouTube error 152/153, oEmbed limits) | Medium | Low | A thumbnail-first card always works; the player is an enhancement; "Open in YouTube" fallback |
| R13 | Accessibility regressions in custom cards | Medium | Medium | Card-level accessibility element with a combined label; actions as accessibility actions; a VoiceOver pass per ticket |
| R14 | Memory pressure with many images | Medium | Medium | Bounded caches (memory 64 MB, disk 300 MB LRU); purge on the memory warning |

### 13.2 Test strategy

**Unit (Linux, `swift test`, in PaseoStore / PaseoCore).** Every pure piece gets tests before its
UI ticket starts:
- `RichContentDetector`: Mermaid on (with the user's sign-off for the changed test), galleries,
  video and audio extensions, the own-paragraph rule;
- `TurnChangeSummary`: diff counts, write = all added, incremental append equals a full rebuild;
- `AnsiText` and `TestSummaryParser` against captured outputs (scrubbed);
- `GlanceSnapshot`: Codable round-trip, the throttle rules;
- `MediaFetchPolicy`: the full §12 table as a parameterised test;
- the size reservation: `viewBox` / width / height parsing, the aspect fallback;
- the todo-card reducer: replace in place, collapse when done.

**Snapshot-by-reasoning (no Xcode here).** Every UI ticket's final message includes the card at 3
widths (320, 393, 430 pt), in light, dark and pure black, at the default and the largest Dynamic
Type. That's the worker's described layout. The lead verifies it on the Mac gate (simulator
screenshots) before merge.

**Performance checks in review:**
- the number of live `WKWebView`s while scrolling a 20-card fixture: never more than 2;
- no decode on main: all decode calls go through the pipeline actor (grep-checked);
- no `body` reads of a whole store (R-1);
- for scrolling, a fixture conversation with mixed cards (`paseo-probe` can seed one on a
  `pi`/`beam-free` agent; **never on a Claude agent**). The user's device run is the final judge.

**Device checklist (the user, per IPA):**
- scroll a long mixed chat on 120 Hz, and look for hitches;
- open and close the viewer from every card kind;
- play YouTube inline, then scroll away (it pauses);
- Low Data Mode on (cards wait);
- the relay connection (large files wait);
- VoiceOver over each card;
- Lock Screen redaction.

## 14. More rejected ideas

These come on top of §6.
- **Reactions, likes or ratings on assistant turns.** There's no daemon concept to send them to,
  and the user is the only reader.
- **Animated "typing" effects or reveal animations on cards.** The prose reveal already exists;
  cards appearing with their own flourish is noise and costs frames.
- **Auto-playing video or GIF-like loops in the transcript.** They're distracting, cost battery,
  and break the §12 network rule. Video shows a poster until tapped.
- **A media-only tab in the main UI.** The conversation media sheet (C15) covers it without
  another navigation level.
- **Inline editing of artifacts** (editing HTML or Mermaid in the app). It's a new feature, and
  the agent is the editor.
- **Cross-device handoff of a playing video.** It's rare, and Handoff adds entitlements.
- **3D / USDZ Quick Look in the transcript.** Agents almost never produce it; a file card with
  Quick Look covers the rare case.
- **AI-generated card summaries or titles** (on device or remote). That's invented copy, and it's
  unpredictable.
- **Custom haptics per card kind.** Haptics stay the D5 vocabulary; cards use `light()` on copy
  and nothing else.
- **Background audio for agent output** (keep playing when locked). It needs the background audio
  mode for marginal value, and invites App Review questions.
- **A widget that shows the last message text.** It's private by nature, and stale by design.

## 15. New copy for the user's approval

None of these strings exist today. They need approval before their tickets merge. Where upstream
`en.ts` has an equivalent, the ticket uses upstream's text instead, and the string drops from this
list.

| Where | String |
|---|---|
| Card: download state | "Tap to download · {size}" |
| Card: too large | "Too large to preview" |
| Card: unsupported item | "This item can't be shown here" |
| Card: load failed | "Couldn't load" / action "Try again" (check upstream first) |
| Video / YouTube menu | "Open in YouTube" |
| Viewer | "Save to Photos", "Copy image", "Show text" (Live Text) |
| Artifact page | "View source", "Reload", "Open in Safari" |
| Mermaid | "Diagram" (card title fallback), "Couldn't render diagram" |
| Turn changes card | "{n} files changed" |
| Test chip | "{passed} passed · {failed} failed" |
| Todo card | "{done} of {total} done", "Plan" |
| Permission preview | "Show all", "Show more" |
| Subagent card | "Subagent" (title fallback) |
| Media sheet | "Media in this chat", "Files", "Links" |
| Charts | "Context", "Cost", "Data starts {date}" |
| Widget | "Agents", "Needs you", "Running", "Updated {time}", "Open Paseo to refresh" |
| Widget empty | "No agents running" |
| Live Activity | "Agents at work", "{n} running", "Waiting for you" |
| Control | "New agent" |
| Setting (§3) | "Show agent names on the Lock Screen" |
| Notification action (G19, if approved) | "Allow", "Deny" (upstream wording if present) |
| Share extension (G20, if approved) | "Send to Paseo", "Choose agent" |

---

# Appendix A: the research agent's own draft, rescued (verbatim)

The research agent wrote these sections, but a safety filter stopped them before they reached this
file. The user recovered them from the agent's shell commands on 2026-11-11, and they appear below
word for word. Both captures end mid-text; the cut-offs are marked. Where they overlap with the
lead's §8–§10 above, both versions are kept. §0 (the research synthesis) appears only here.

## 0. Research synthesis: what others do, and what it means here

This section was cut from the capped version. It records what the web research found and the
conclusion each finding drives. Sources are in §7.

### 0.1 Apple platform guidance

- **Live Activities (HIG, change log Oct 2026).**
  - Scope:
    - Live Activities are for tasks "that have a defined beginning and end" and "don't exceed
      eight hours".
    - They remain on the Lock Screen up to four hours after ending, and a custom dismissal of
      15–30 minutes is "adequate" in most cases.
    - "Prefer a single Live Activity that uses a dynamic layout and rotates through events."
    - Don't send push notifications "alongside Live Activities for the same updates".
  - Interaction:
    - Interactivity should be limited "to a single element".
    - CarPlay deactivates interactive elements.
  - Privacy: avoid sensitive information, or redact it.
  - Layout specs, from the 393 pt-wide iPhone:
    - compact 52.33×36.67, minimal 36.67–45×36.67;
    - expanded and Lock Screen 371×84–160;
    - limited width is a 28 pt circle;
    - Lock Screen margin is 14 pt.
  - Presentations:
    - The Mac menu bar (macOS Tahoe), the Watch Smart Stack and StandBy reuse the same
      presentations.
    - The logo mark sits "without a container".
  - Animations are at most 2 s.
  - **Consequence:** one rotating "agents" activity, no buttons, redacted titles, a factual
    status line, and an end with 15 min dismissal.
- **Widgets (HIG).**
  - Standard margin 16 pt (11 pt for groupings), and `ContainerRelativeShape` for inner
    corners.
  - Text ≥ 11 pt; don't rasterize text.
  - "Convey meaning without relying on specific colors" (acc

*[Capture ends here, mid-sentence.]*

## 8. What competent apps do (the agent's version)

These are the patterns that well-built chat, assistant and developer apps converge on for rich
answers and system surfaces. Each pattern comes with the reason it exists. Apple's HIG is cited
where it states the same rule.

### 8.1 Rich answers in a transcript

- **Prose first, cards second.**
  - The answer stays readable text. Rich blocks appear only where they carry information that
    text can't: an image, a diagram, a structured status.
  - Why: a transcript that turns into a dashboard is hard to scan, and every card costs vertical
    space on a phone.
- **One card language.**
  - Every embedded object shares the same chrome (radius, border, padding, header anatomy) and
    differs only in content.
  - Why: users learn "this is tappable and opens something" once. Mixed card styles read as
    bugs.
- **Explicit triggers, never guesses.**
  - Cards come from unambiguous signals: a dedicated fence, a bare URL on its own line, a known
    file extension. Prose is never parsed for "probably a place" or "probably a chart".
  - Why: a false positive (a sentence turned into a card) is worse than a missed card.
- **Space is reserved before content arrives.**
  - Media slots get their final size from metadata or a fixed ratio before any pixel loads.
  - Why: text that jumps while you read is the most visible sign of an unpolished app.
- **Progressive disclosure for big things.**
  - Inline previews are capped (about one screen). The full object opens on its own page with
    share, source and export.
  - Why: the transcript scrolls; artifacts need room. Mixing the two makes both worse.
- **Source stays one tap away.**
  - Anything rendered from code (diagrams, HTML, SVG) offers "view source" and "copy source".
  - Why: technical users need to verify what was rendered, and copy it elsewhere.
- **Citations are compact and inline.**
  - Small chips or a collapsed list of sources, expanded on demand.
  - Why: provenance matters, but should never push the answer below the fold.
- **Structured follow-ups replace typing where it's cheap.**
  - Choices, confirmations and approvals appear as native controls, while free text stays
    available.
  - Why: tapping is faster on a phone. In this app that pattern already exists as the
    permission and question cards; it isn't extended to generic "forms in answers" (§6).

### 8.2 Media

- **Downsample to display size; decode off the main thread.**
  - Why: full-resolution screenshots exhaust memory and cause scroll hitches.
- **Never crop what matters.**
  - The inline view letterboxes tall images. Only gallery tiles crop, and the viewer always
    shows the full frame.
  - Why: a cropped screenshot hides exactly the part that matters.
- **One full-screen viewer for everything visual**, with the zoom transition from the source,
  swipe to page, pinch and double-tap zoom, drag down to dismiss, and share/save/copy.
  - Why: users carry the system Photos gestures into every app. Deviating feels broken.
- **Players are lazy and exclusive.**
  - The poster shows first, and the player is created on tap. Only one source plays at a time,
    and scrolling far away pauses it.
  - Why: performance, battery, and not surprising the user with sound.
- **Text in images is selectable** (on-device text recognition in the viewer).
  - Why: error screenshots are the most common image in developer conversations.
- **Expensive downloads are explicit.**
  - Large files show their size and wait for a tap. Low Data Mode is respected.
  - Why: the user pays for data, and the HIG asks apps to honour Low Data Mode.

### 8.3 Developer-specific

- **Changes are summarised, not dumped.**
  - "N files changed, +A −B", with per-file diffs one tap away.
  - Why: on a phone, a reviewer wants the scope first and the details second.
- **Terminal output keeps its colors but is truncated to the tail.**
  - Why: the end of the output holds the verdict (exit code, test summary). The colors carry
    meaning (red failures).
- **CI and review state is live, not a snapshot.**
  - A PR card updates as checks finish.
  - Why: stale CI status leads to wrong decisions.
- **Approvals show the full command before acting.**
  - Truncated commands, and buttons placed where a mis-tap approves, are the most common
    complaints about mobile agent control.
  - Why: approval is a security decision.

### 8.4 System surfaces

- **Widgets show the one thing the user checks most, with an honest freshness label.**
  - HIG: "Prefer dynamic information"; "consider displaying text that describes when the data was
    last updated".
  - Why: a widget that looks current but isn't destroys trust.
- **Widgets deep-link to the exact item**, never to the app's home screen (HIG).
- **Live Activities track one bounded task.**
  - They use a single activity, and update only on meaningful change. The single alert goes out
    when the user must act. They end promptly, with a short summary (HIG).
  - Why: Live Activities are prominent and budgeted; noise gets them turned off system-wide.
- **Lock Screen content is redacted by default** when it may contain private text (HIG).
- **Controls and Action-button shortcuts start the most common action** (a new conversation).
  - Why: they're the fastest entry point the system offers.
- **Background chats show progress in a Live Activity only when the app can actually keep the
  work alive.**
  - Why: a timer that counts after the work stopped is a lie.
- **Destructive or privileged actions from outside the app require device authentication.**
  - Why: a locked phone in someone else's hand must not be able to approve anything.

---

## 9. Lower-priority card refinements (the agent's version)

These are not in the phased roadmap. Ticket them after Phase 1 if device use shows the need.

### 9.1 Wide Markdown tables

- **Today.**
  - `MarkdownTableMetrics` sizes columns: short tables fill the column, wide ones scroll
    horizontally (`Conversation/Prose/MarkdownTableMetrics.swift`, `ClaudeMarkdownView.swift:271-280`).
- **Refinement.**
  - When a table overflows, show a right-edge fade as the scroll hint, and pin the first column
    while scrolling.
  - Add an "Open" accessory in the table's top-right that opens a full-screen table page:
    - landscape allowed on that page only;
    - both axes scroll;
    - sticky header row;
    - Copy as Markdown and Copy as CSV.
  - Long-press a cell to copy its text.
- **Data.** Have (prose).
- **Size.** M.
- **Note.** The app is portrait-only (`UISupportedInterfaceOrientations`). Allowing landscape on
  one page needs a small UIKit orientation override. List it as a platform risk.

### 9.2 Todo / plan card

- **Today.** `ClaudeTodoCard` (`Conversation/Turn/ClaudeToolDetail.swift:220`) lists items. Plans
  render as text (`ToolCallDetail.plan`).
- **Refinement.**
  - A thin determinate progress bar in the card header ("3 of 7"), with the in-progress item
    highlighted.
  - Completed items collapse behind "N done" once there are more than five.
  - The same `done/total` value feeds the Live Activity row 3 (§3.2) and the
    `BGContinuedProcessingTask` progress (G17).
  - Plan text uses the card family's row header ("Plan"), with the Markdown body below.
- **Data.** Have (`TimelineItem.todo`, `ToolCallDetail.plan`).
- **Size.** S.

### 9.3 Previews in the permission card

- **Today.** `ClaudePermissionCard` renders actions, question forms, and a generic tool fallback.
- **Refinement.** Reuse the new cards inside the request, read-only:
  - Shell request: the full command in the terminal surface (C12 styling) with the working
    directory. Never truncated; long commands wrap, and "Show all" opens a sheet.
  - Edit or write request: the diff (`ClaudeDiffView`), capped at 12 lines with "Show all", plus
    a `DiffStat`.
  - Fetch request: the C6 link card for the URL (metadata only, no web view).
  - The action buttons sit at least 12 pt below the preview, and the destructive or allow
    buttons are never at the card's top edge, to avoid mis-taps while scrolling.
- **Data.** Have (`AgentPermissionRequest.detail: ToolCallDetail`, `input`, `actions`).
- **Size.** M.

### 9.4 Subagent cards

- **Today.** E3 fixes harness subagent loading and states. `ToolCallDetail.subAgent` carries the
  type and description.
- **Refinement.**
  - A row card in the work group for each subagent tool call:
    - the subagent type glyph;
    - its description (2 lines);
    - status (running, completed or failed, from the tool call status);
    - elapsed time;
    - a chevron.
  - Tap opens the existing subagent sheet (`Conversation/Sheets/ChatSubagents.swift`).
  - While running, the trailing accessory shows the subagent's latest step, the same
    `ActivityLine` logic used for the Live Activity.
- **Data.**
  - Have: `ToolCallDetail.subAgent(subAgentType, description, childSessionId)` and
    `ToolCall.status`.
  - Partial: the live step needs the subagent timeline, which comes from
    `agent.provider_subagents.timeline.get`. Fetch it only when the card is visible.
- **Size.** M (after E3).

### 9.5 Images in user bubbles

- **Today.** Attached images show as ClaudeUI thumbnails in the bubble.
- **Refinement.**
  - Thumbnails come from the same `MediaPipeline`, at their true ratio:
    - one image: up to 220 pt wide;
    - two or more: a 2-column mini grid of 1:1 tiles;
    - all sit above the bubble text.
  - Tap opens the shared viewer (G3) with all of that message's images.
  - Images that were sent but can't be loaded back show a placeholder tile with the file name.
- **Data.**
  - Partial: images attached in this session are local. History images depend on what the
    projected timeline returns for user messages. Today `UserMessage` carries text only
    (`PaseoProtocol/Timeline.swift:24-36`).
  - Showing images from history needs protocol support. Upstream's `images` and `attachments`
    fields on send requests (`messages.ts:1287-1302`) aren't echoed in timeline items.
- **Size.** S.

---

## 10. Data needs (the agent's version)

Status key:
- **Have**: present and decoded today.
- **Partial**: present in some cases, or only for live turns.
- **Change**: needs a protocol or daemon change upstream.

| Item | Data needed | Status | Field / message |
|---|---|---|---|
| C1 Image (remote) | URL | Have | Assistant prose → `RichContentBlock.bareImageURL` |
| C1 Image (local) | file bytes | Have | `FileExplorerRequest` (`mode: file`, `acceptBinary`, `maxBytes`) → `FileExplorerFile.content` base64 |
| C1 cache freshness | file revision | Partial | `FileExplorerFile.revision` (optional) |
| C2 Gallery | adjacent image blocks | Have | Detector output |
| C3 Video (remote) | URL | Have | Prose |
| C3 Video (local ≤ 64 MB) | bytes | Have | `FileExplorerRequest` binary read |
| C3 Video (local, streaming or > 64 MB) | ranged reads | Change | `/api/files/download` lacks `Range`; no chunked socket read |
| C4 Audio | bytes | Have | As C3 |
| C5 YouTube title | title, channel | Have (client) | Third-party oEmbed; nothing from the daemon |
| C6 Link metadata | title, icon, image | Have (client) | `LPMetadataProvider` |
| C7 GitHub (same repo) | title, state, labels | Have | Forge search (`ForgeSearch.swift`: `title`, `state`, `labels`, `number`) |

*[Capture ends here, inside the C7 rows. The rest of the agent's table is in the lead's §10 above.]*
