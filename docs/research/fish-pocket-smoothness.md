# How Fish Pocket stays smooth, and how Paseo can match it

Method: seven Haiku researchers compared both repos. I re-opened the cited files in both repos and checked every medium or high impact claim. Nothing here was measured on a device. Where a claim rests on code reading only, the report says so. The composer/keyboard researcher returned no findings. I covered that area myself in a short pass (see Keyboard).

## 1. Executive summary: why Paseo jumps and Fish Pocket does not

1. **Scroll compensation is decided per whole turn cell, with two blanket exceptions.** `compensatesResize` (`TranscriptEngine.swift:489-511`) gets only the cell's old frame and a delta. It cannot tell whether the change happened above or below the reader. A tall reply that straddles the reader line gets the full delta added to `contentOffset` even when the change is a block settling far below the line. That moves the text being read. Two exceptions then do the opposite: any tap disables compensation for 0.6 s everywhere (`:161-164`, `:508`), and any running turn is never compensated (`:509`). Fish Pocket hands this to the system. `.defaultScrollAnchor(.bottom, for: .sizeChanges)` (`ConversationView.swift:733`) makes growth below the viewport inert by construction.
2. **Two animation clocks.** Paseo's rows are SwiftUI inside UIKit self-sizing cells. UIKit applies each new cell height at once (`TranscriptLayout.swift:133-155`). SwiftUI inside the cell animates for 0.25 s on its own clock. This happens with the automatic turn fold (`ClaudeTurnView.swift:179-184`) and with every late media or card resize (`.animation(Motion.disclosure, value: layout)` in the image, web, link, YouTube and GitHub cards). The rows around the content jump while the content inside fades or shrinks. Fish Pocket has one layout system, so every height change happens in one transaction. Its automatic fold has no animation at all (`ConversationView.swift:1530-1537`).
3. **A running shell command stretches its row and then deletes the stretch.** `WorkToolStep.swift:18-24` auto-opens a terminal box for the live shell step, and it disappears when the step finishes. The collapse is unanimated, so a viewport pinned to the end drops by the whole box height in one frame. Fish Pocket's tool row is a fixed 44 pt line for its whole life (`ToolCallView.swift:19-31, 91, 100`).
4. **Streamed growth is chased by a restarted 0.16 s glide, and the streaming turn re-evaluates more than it needs to.** Every reveal step can restart `UIView.animate(... contentOffset)` (`TranscriptEngine.swift:582-588`), so the offset is always mid-animation behind the painted text. Fish Pocket writes the offset once per growth with no animation (`ConversationView.swift:780-781`). Underneath, every prose segment of the running turn runs its own 30 Hz reveal loop, and no segment is Equatable-gated.
5. **Rich-media boxes are guessed and the memory is session-only.** Local-file images start at 4:3 with no cache seed. Remote and web boxes forget their size on every relaunch. Fish Pocket derives attachment boxes from the persisted record, so nothing resizes.

Fish Pocket's other big advantage is a non-lazy VStack, so no heights are ever guessed (`ConversationView.swift:1118-1120`). Paseo should not copy that. It pays for it with eager layout of up to 500 messages, and Paseo's cell pool, overscan and remembered heights are better for long chats.

## 2. Findings by category

IDs match section 6.

### Scroll anchoring

**scroll#1: compensation cannot locate the change (confirmed)**
- Fish Pocket: `.defaultScrollAnchor(.bottom, for: .sizeChanges)` at `ConversationView.swift:733`, plus `BottomFollow` (`:765-807`), which scrolls only when the reader is within 25 pt of the end.
- Paseo: `TranscriptLayout.swift:150` calls `engine.compensatesResize(of: frames[index], ...)`. In `TranscriptEngine.swift`, `:500` handles cells wholly above the reader, `:501` admits any cell that starts above the reader, and `:510 return true` applies the whole delta.
- Why it is worse: an image, diagram or web view settling below the line in a straddling turn moves the visible text by its height, with no touch. The row frames needed to fix this already exist (`TranscriptRowFrames.swift`, `.rowAnchor(row.seqEnd)` in `ClaudeSegmentView.swift:29`).
- Fix: compensate against the row under the reader, not the cell (chunk 1).

**scroll#2: tap window and running-turn exception (confirmed)**
```swift
// TranscriptEngine.swift:508-509
if Date.now < resizeAnimationUntil { return false }
if case .turn(let row) = entries[index], row.turn.phase == .running { return false }
```
- `transcriptTapped` arms the window for every tap, including taps that only dismiss the keyboard. It stops compensation for every straddling cell, so text moves down when media above the touch settles.
- The running-turn rule skips compensation for a tool step that changes above the reader inside the turn being written.
- Fix: scope the window to the tapped cell, and replace the running-turn rule with the row-level rule (chunk 1).

**scroll#3: guessed heights ignore work sections and rich blocks (confirmed, modest)**
- `guessHeight` (`TranscriptEngine.swift:439-461`) counts prose only. Work and todo segments add `0`. Images, code and tables have no term.
- Mitigated by `TurnHeightStore` remembered heights, so it matters on the first open of a chat and when flicking back through old turns.
- Fix: a type-aware guess (chunk 1). Pre-measuring in the prefetch callback is deferred.

**scroll#4: restarted 0.16 s stream glide (mechanism confirmed, effect unmeasured)**
- `pinIfNeeded(glides:)` (`TranscriptEngine.swift:572-604`) animates the pin whenever a turn is active and growth is at most 96 pt. Reveal steps arrive about every 33 ms.
- The new line is below the visible area until the glide catches up.
- Fix: a static flag that turns the glide off for stream growth, to A/B on device (chunk 1). Disclosure glides stay.

### Streaming and rendering cost

**tools#3 / stream#2: finished segments of the running turn re-evaluate per token (confirmed)**
- `ClaudeTurnView.swift:144-156` draws every segment through `ClaudeSegmentView`, which holds a closure (`onMarkdown`) and is not Equatable. The closure defeats SwiftUI's diff, so every segment body runs whenever the running turn's body runs. `TurnRow` is Equatable (`TurnRow.swift:32-37`) and skips unchanged turns, but not the segments inside the one running turn.
- Fish Pocket uses `BlockView: Equatable` with `.equatable()` (`ConversationView.swift:1595, 1615, 1779`).
- Fix: Equatable segment, closures excluded (chunk 2).

**stream#4: one 30 Hz reveal loop per prose segment (confirmed)**
- `ClaudeSegmentView.swift:27` passes `isStreaming: turnIsRunning` to every segment, not only the tail. `ClaudeRevealProse.swift:215` keys `.task(id: pacingActive)` on `isLive`, so K prose segments in a running turn run K wake-ups at 30 Hz. They only write when `paced` changes, so this is wake-up cost and not layout.
- The comment at `ClaudeRevealProse.swift:210-212` says one task paces the whole turn. That is not true today.
- Fix: `isStreaming: turnIsRunning && isTail`. The existing `onChange(of: isStreaming)` drain (`:196-209`) handles the hand-off when a segment stops being the tail (chunk 2).

**stream#3: code blocks lay out their whole text (confirmed)**
- `MarkdownCodeBlock.swift:62-64` puts all content in a horizontal scroll view with no line cap. Fish Pocket caps inline code at 24 lines (`MarkdownView.swift:371, 395`).
- Paseo already has an expand sheet for the rest.
- Fix: cap inline code to 24 lines with a "N more lines" affordance that opens that sheet (chunk 7).

**tools#4: terminal output (partly refuted)**
- The parse is already off main (`@concurrent parseParts`, cancelled by `.task(id:)`). The research said it ran on the main actor, and that is wrong.
- What does run on the main actor per output change is building two `AttributedString`s (the 12-line tail and the 2,000-line sheet, `ClaudeCodeBlock.swift:139-146`), plus an O(output) `hashValue` in `TerminalParseCache.key`.
- Fix: build the sheet string lazily, only when Show all is opened (chunk 8).

### Media loading

**media#3: local-file images flash spinner and resize on every scroll-back (confirmed)**
- `RichLocalImage.swift:16-17` keeps `image` and `aspectRatio` in `@State` with no seed. `RichRemoteImage.swift:56-68` seeds both in `init`.
- A revisit starts at 4:3, waits for a width, then waits for an actor hop before the cached bitmap appears.
- Fix: read `MediaPipeline.cached` and `MediaMetadataCache` in the first body pass (chunk 4).

**media#4: every late size change is animated as a 0.25 s slide (confirmed)**
- See root cause 2. Frame animations on `layout`, `stageHeight` and similar values sit in `RichRemoteImage:156`, `RichLocalImage:123`, `RichWebCard:183`, `RichLinkCard:96`, `YouTubeRichCard:96` and `RichGitHubCard:84`.
- Fix: the frame changes instantly and only the picture fades (chunks 4 and 5).

**media#1 / media#5: box guesses are session-only (confirmed)**
- The aspect memory is a plain `NSCache` (`MediaMetadataCache.swift:22`), so every relaunch repeats the 4:3 guess for images and the 240 pt guess for web cards.
- One change fixes remote, local, gallery, mermaid and web cards at once, because they all read and write through this cache (`MediaPipeline.swift:388, 420, 503, 542`, `RichWebCard.swift:106, 302, 334`).
- Fix: persist it (chunk 6).

### Disclosure and tool cards

**tools#1: running shell box grows, then collapses (confirmed, high impact)**
- `WorkToolStep.swift:18-24`: `opensLive` is true for a running shell step that is the live tail, and `isExpanded` follows it. When the call completes the box is removed with no animation.
- Fix: latch it open once it opened live, so completion changes no height. The turn's end fold then handles it in one step (chunk 3). If the team would rather copy Fish Pocket exactly, remove the auto-open and show output only behind a tap. That is a product call.

**tools#2: automatic fold animates inside an already resized cell (confirmed)**
- `ClaudeTurnView.swift:179-184` wraps the fold in `withAnimation(Motion.disclosure)`, while the cell's height is applied at once. `settlingTurn` compensation (`TranscriptEngine.swift:504-507`) keeps the answer in place, which is good. The fade-and-shrink inside the box is the detached part.
- Fix: make the fold a single unanimated change (chunk 2).

**tools#6: header height changes when a turn ends (confirmed, small)**
- `ClaudeLiveStatusLine.swift:52` has `minHeight: 24`. `TurnOutcomeLine.swift` has no minimum.
- Fix: add the minimum (chunk 2).

### Keyboard and composer (my own pass; no researcher findings)
- Fish Pocket dismisses the keyboard 0.12 s after a tap so a tapped link wins (`ConversationView.swift:208-210`) and uses `.scrollDismissesKeyboard(.immediately)`. Paseo's tap recognizer has `cancelsTouchesInView = false`, so link taps still reach the cells. I found nothing there that makes the chat jump. The user's requested behaviours stay as they are.
- The claim that Paseo's bottom inset is written from a different transaction than the composer height (scroll#5) has no evidence behind it. `ChatScreen.swift:71-73` records a deliberate reason for not using `safeAreaBar`. Not planned. Check it on device if jumps remain around the keyboard.

### Terminal and files

**term#2: no English-first input mode (confirmed)**
- Grep for `textInputMode`, `activeInputModes` and `primaryLanguage` in Paseo returns nothing. Fish Pocket overrides `textInputMode` (`TerminalView.swift:413-428`) so Pinyin users do not type into the candidate bar.
- Fix: mirror it in `PaseoTerminalSurface` (chunk 9).

**term#3: text files re-decode when the viewer resizes (confirmed)**
- `WorkspaceFileViewer.swift:109-118` puts `pixelBudget` in `renderKey`, so `.task(id:)` restarts a full decode and highlight on every stage-size step, even though only images use the budget.
- Fix: budget in the key for images and SVG only (chunk 10).

## 3. Prioritised fix list

| # | Chunk | Expected user-visible effect |
|---|---|---|
| 1 | Scroll engine: row-level compensation, tap scoped to the tapped cell, stream glide flag, type-aware guess | The largest "chat moves by itself" cases go away: media settling below the reader, and text shifting after a tap. Streaming follow becomes a direct write, with a flag to revert. |
| 2 | Turn view: Equatable segments, tail-only reveal loop, unanimated fold, constant header height | Cheaper streaming turns, a single-step fold with no detached fade, and no nudge at turn end. |
| 3 | Shell step stays open once opened live | No full-box drop when a command ends. |
| 4 | Local image seed, fade-only image arrival | No spinner flash or resize on scroll-back. |
| 5 | Remove frame animations in web, link, YouTube and GitHub cards | Cards that settle no longer slide the text. |
| 6 | Persist the aspect memory | Boxes are right on the first pass after a relaunch. |
| 7 | Cap inline code at 24 lines | Long file writes stop getting heavier per token. |
| 8 | Lazy terminal sheet string | Less main-thread work per output chunk. |
| 9 | English-first terminal input mode | Fixes Pinyin typing. |
| 10 | Text files do not restart on resize | Less CPU on rotation and iPad resize. |

Run the app with `-paseo-perf` (`PaseoPerf.body` counts) and record Instruments hitches before and after chunk 1 and chunk 2. I could not measure any of this.

## 4. Deferred, with reasons
- **Raising the 16 ms commit coalescer to 50-80 ms (stream#1 headline):** refuted as a fix. The daemon already sends about one message per 60 ms window (`TextReveal.swift:8-9`), so commits run near 16 per second. The coalescer is a ceiling, and the 30 Hz reveal steps are the real layout driver. A longer interval would add latency for little gain.
- **Per-reveal-step re-split of the whole message (stream#2 in state):** the mechanism is real (`RichPiecesCache.pieces` never stores transient splits, so `richPieces` reruns each step). Per-unit memos already exist, and the cost is unmeasured. Use the existing `rich.pieces` signpost first.
- **Ranged file reads and paste chunking (term#1, term#4):** both need daemon protocol work.
- **Observation restructuring (the `store.turns` and `timeline` observed-struct findings):** real but small per commit. It needs a store shape change that the evidence does not justify yet.
- **Persisted link metadata and a reserved YouTube title strip (media#2):** valid, but they need a serialization format and extra layout work. Take them after chunks 4 to 6.
- **Selection off in the streaming turn, the thought cache, work-step node count, holding frames during the send animation:** unmeasured or low impact.

## 5. Refuted, and where Paseo is already better
- **Refuted:** "commits up to 60 times a second" (see section 4). "Terminal parse runs on the main actor" (the parse is off main; only the attributed-string build and the hash are on main). "About 100 evaluations per second" (only commits and reveal steps change the cell's size, and the loader and sweep are leaf redraws; the figure is unmeasured).
- **Paseo is better at:**
  - remembered heights for reopened turns, the 400 pt overscan and the 64-slot cell pool;
  - the top-pinned cell layout;
  - the incremental turn builder and settled-unit markdown memos, which Fish Pocket lacks (it re-parses live text in full);
  - the ledger-based paced reveal;
  - downsampled media decode, flight dedupe, bounded caches, the live web-view cap and the persisted user-image manifest;
  - Metal terminal rendering, off-main output parsing, retained emulators and the Equatable `TerminalStage`.

## 6. Finding ledger
See the structured list returned with this report. Each finding there has an id, a verdict and a one-line note.
