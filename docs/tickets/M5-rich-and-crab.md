# M5: rich content and the crab

Shared rules: as in `docs/tickets/M3-workspace-panel.md` (top section). The user decided the
mascot is the DSH crab (Clawd); personal app, assets may be copied.

## M5a: the crab (branch `m5a-crab`)

Spec: `docs/research/08-dsh-live-observation.md` §7 (measured) and doc 06's mascot section; logic:
`Packages/PaseoCore/Sources/PaseoStore/Rich/MascotState.swift` (T13's pure state machine, tested,
don't change it; if it lacks a needed input, say so).
1. Copy the sheets from `/home/paseo/dev/dsh-claude-style-reference/packages/assets/src/mascot/crab/`
   (colour + ink mask per animation) into `Packages/PaseoUI/Sources/PaseoUI/Resources/Crab/`.
   Port the crop boxes, frame counts/columns, `still` frames and 80 ms pace from
   `features/mascot/sheets.ts` into a Swift table (cite lines).
2. `Mascot/ClaudeCrabView.swift`: renders one animation from the sheet with nearest-neighbour
   scaling (`.interpolation(.none)`), 2 pt per cell, the ink mask tinted `ClaudePalette.tertiaryInk`,
   driven by `TimelineView(.animation)` at 80 ms per frame. Reduce Motion: the `still` frame.
3. Placement per §7.1: 104 × 72 pt, feet on the top edge of the composer card, right edge
   aligned with the card's right edge, above the card, not intercepting touches except a small
   body hit area (tap = poke animation if the sheets have it).
4. Feed `MascotState` from the open conversation (`ConversationStore`: active turn phase, newest
   row kind thinking vs tool call, completion/failure, permission pending, idle time) with
   timestamps, in the chat view; show the state machine's output animation. **A completed turn
   must never show `error`** (the state machine guarantees it; don't bypass it).
5. A Settings toggle "Show mascot" (`@AppStorage("paseo.mascot.enabled")`, default on); if the
   Settings screen from M4a isn't merged yet, read the key only and say so.

## M5b: rich content (branch `m5b-rich`)

Spec: `docs/research/05-rich-media-spec.md`; detection: `PaseoStore/Rich/RichContentDetector.swift`
(T13, tested, don't change it). In assistant prose (`ClaudeMarkdownView` / the chat's prose
segment), render the detector's blocks:
- Standalone bare URL → link card with `LPLinkView` / `LPMetadataProvider` (LinkPresentation,
  cache metadata in memory by URL, placeholder card while loading, tap opens in Safari view).
- YouTube → thumbnail card with play glyph (tap opens the video), per the spec's full/inline rules.
- Bare image URLs and local image paths → inline image (`AsyncImage` for URLs; local paths read
  through the workspace files store only if reachable, otherwise a path chip), tap → full-screen
  viewer (reuse `ClaudeMediaView`'s viewer if it fits).
- Raw SVG blocks and `visualize` fences → render in a `WKWebView` card sized to content,
  non-scrollable, with a "View source" toggle.
Cards: ClaudeUI card style (`ClaudeCard`), 12–16 pt radius, hairline border, both themes.
Rendering is lazy (only when on screen). No network beyond what a card needs.
