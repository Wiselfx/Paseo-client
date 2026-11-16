# J3 — Pasted-image giant circle, back-to-end button dead and shown at the end

Read `_J-common.md` first. Branch: `j3-composer`. Commit messages start with `J3:`.

## 1. Pasting an image fills the composer with a huge grey circle

**Symptom (screenshot):** after pasting a screenshot, the attachment tray grows to ~350 pt tall and
a grey disc larger than the tray covers the thumbnails, with a small white ring at one tile.
When the upload finishes, the tray goes back to normal.

**Root cause (lead):** `ComposerAttachments.swift:323–329`. While `.uploading`, the ZStack draws
`Circle().fill(Color.black.opacity(0.35))` with **no frame**. A shape is flexible, so it takes the
whole proposed size, which grows the ZStack, the tile, the tray and the composer card.

**Build:** the dimmer is the tile's own shape and size: a `RoundedRectangle(cornerRadius:
Radius.md)` (or the thumbnail's clip) filled with the same dim, framed to the tile size; the ring
keeps its 40 pt frame. Better still, put both overlays in `.overlay { … }` on the framed, clipped
thumbnail so nothing in them can size the tile. Check the other phases' overlays in this file for
the same unframed-shape bug (the `.failed` overlay is framed; check `decodingTile`, the file pill and
any other `Circle()`/`Rectangle()`/`Color` inside a ZStack without a frame) and fix the same way.
Add the dim value to `Metrics`/`Palette` if it is not already a token.

## 2. "Back to the end" does nothing when tapped

**Symptom:** the round ↓ button shows above the composer but tapping it does nothing (no scroll,
the button stays).

**Root cause (lead, strongest hypothesis):** the button lives in
`ChatScreen.swift:100–104`, `.overlay(alignment: .top)` on `bottomChrome`, pushed **above** the
bar with `.alignmentGuide(.top) { $0[.bottom] + Space.sm }`. `bottomChrome` is hosted by
`.safeAreaBar(edge: .bottom)` (`ChatScreen.swift:49`), whose host does not hit-test outside the
bar's own frame, so a touch on the button lands on the transcript underneath (which only dismisses
the keyboard). `STATUS.md` listed this as "hit-testing outside that frame is unverified on device".

**Build:** move the button out of the bar and onto the transcript, **before** the safe-area bars:

```swift
TranscriptView(store: store, controller: controller)
    .overlay(alignment: .bottom) {
        TranscriptBackToEndButton(controller: controller)
            .padding(.bottom, Space.sm)
    }
    .safeAreaBar(edge: .top) { topChrome }
    .safeAreaBar(edge: .bottom) { bottomChrome }
```

An overlay respects its view's safe area, and `safeAreaBar(edge: .bottom)` (plus the keyboard)
contributes to that safe area, so the button sits `Space.sm` above the bar (including the subagent
pill), moves with the keyboard and the composer's growth, and is inside a hit-testable frame. No
inset arithmetic (that was the old double-count, see the doc comment at
`ChatTranscript.swift:904–911`; update that comment). Confirm by reading that the overlay is not
`ignoresSafeArea` anywhere up the chain. Remove the old overlay from `bottomChrome`.

Also confirm the scroll actually happens: `jumpToEndRequest` → `scrollPosition.scrollTo(edge:
.bottom)` (`ChatTranscript.swift:193–197`). Check that `scrollPosition` is the binding the
`ScrollView` uses (`.scrollPosition($scrollPosition)`) and that nothing in the same pass resets it.
Report what you found.

## 3. The button shows while the end is on screen with the keyboard up

**Symptom (screenshot):** composer focused, keyboard up, the last message's action row visible just
above the composer — and the ↓ button is shown.

**Find the root cause first**, then fix it. Lead's reading of `ChatTranscript.swift:390–475`:
- `decideBackToEnd()` compares `scrollTrack.distanceFromBottom` against one stable screen. When the
  keyboard and a tall composer (attachments) raise the bottom inset, the content offset does not
  change but `distanceFromBottom` may include the new inset. The decision is skipped on inset-only
  frames (`backToEndMayFlip` + the offset/height check at ~401), so whatever value was set before
  sticks; a later content change (a streaming reply) re-runs it with the inflated distance.
- Or the value was set `true` earlier (reader scrolled up), then focusing the composer glided to the
  end (`endScrollRequested`), and the settle after a programmatic `.animating` phase never re-ran
  `decideBackToEnd` (check whether `onScrollPhaseChange` delivers `.idle` after a programmatic
  glide; if not, decide when the glide's end is reached).

Read `TranscriptScrollTrack` and `ScrollFollowMetrics` (find them with grep) to see exactly what
`distanceFromBottom` measures. Write down which it is, with `file:line`.

**Intended behaviour:** the button shows only when the reader is more than one stable screen above
the **end of the content** (the last turn's bottom), measured independently of the keyboard and the
composer's height. When the end of the content is visible, it never shows. Keep the rule "decided on
user motion and at rest, never per keyboard frame" and keep it O(1) per frame. If the decision logic
can move into PaseoCore as a pure function (`TranscriptChromeState` already lives there — check),
put it there with tests.

## Final message

As in `_H-common.md`.
