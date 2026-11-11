# H3: the context meter is always there; the expand button sits in the corner

Branch `h3-composer`, from `foundation`. Read `_H-common.md` first.

**Owns:**
- In `Conversation/Composer/ChatComposer.swift`: `composerControlRow`, `contextMeter`,
  `contextPercent`, `expandComposerButton`, the card overlays, `fieldRow`'s trailing inset, and
  `ComposerCardChrome`. **H1 edits the voice/dictation regions of the same file** (`voiceBar`,
  `dictateButton`, `dictationOverlay`, `DictationOverlay`, voice controls) — don't touch them.
- New file `Conversation/Composer/ComposerContextMeter.swift` (extract the meter there).
- `Conversation/Composer/ComposerTextView.swift` (text container insets only).
- `Conversation/Sheets/ClaudeContextSheet.swift` (the empty/unknown state only).
- `DesignSystem/Metrics.swift` (`ComposerMetrics` additions), `DesignSystem/UsageMeters.swift`
  (`ClaudeMeterRing` look only, if needed).

## 1. The context window meter must always be there (user bug 3)

User: *"Context window needs to be there not only when it's 70 % but always."*

**What's there:** `contextPercent` (`ChatComposer.swift:586`) returns nil below 70 %, so the ring
doesn't exist, and the row animates when it appears (`:458`). The meter is also read in
`ChatComposer`'s own body, so every usage update re-evaluates the whole composer (R-1).

**Behaviour to build:**
- In a conversation, the ring **always occupies its slot** in the control row, left of the mic.
  The row never reflows when usage arrives or crosses a threshold (delete the `contextPercent ==
  nil` animation; nothing appears or disappears any more).
- With usage known: ring + the integer percent inside, as now, at every value (0–100). The
  "reads as a spinner" concern from D2 is answered by the number inside and by a calm, static ring
  — no animation on value change except a `Motion.feedback` trim change. Emphasis tiers: below
  70 % secondary ink, 70–89 % ink, ≥ 90 % ink at full weight (reuse the existing palette; no new
  colours).
- With usage not yet known (new conversation, provider hasn't reported, reconnecting): an empty
  track ring with no number, same size, secondary ink, still tappable; the context sheet then
  shows its empty state ("No usage reported yet" — check `ClaudeContextSheet` and upstream `en.ts`
  for existing copy first; if none, propose the line in your report).
- Provider that never reports a window (`maxTokens` nil for good): still the empty ring; the sheet
  explains. Never fake a number.
- Draft (new chat) screen: no agent, no ring — keep the slot empty so the draft's row doesn't
  change, or omit; choose what keeps the draft→conversation hand-off from moving anything, and
  say which.
- **Extract `ComposerContextMeter(store:)`** into its own file; it is the only view that reads
  `store.contextUsage`. `ChatComposer`'s body must not read it any more. Make it `Equatable` on
  the rounded percent (and known/unknown) so a usage update that doesn't change the integer does
  nothing.
- Accessibility: label "Context window, N percent used" / "Context window, no usage yet"; 44 pt
  hit area (already).

## 2. The expand button is misaligned (user bug 6)

User: *"The expand button in the composer is misaligned; it should be in the top right."*

**What's there:** `expandComposerButton` (`ChatComposer.swift:1040`) is a `.topTrailing` overlay
pushed left by a literal `.padding(.trailing, 104)` ("left of the crab's spot") with literal
`28`/`44` sizes — an R-4 violation and a guess that depends on the crab's width and the card's
padding.

**Behaviour to build:**
- When the draft is tall, the expand control sits **in the card's top-trailing corner**, inside the
  card, concentric with the card's corner radius (the same rule the 36 pt controls use at the
  bottom: `controlOverhang`, E1 §4). 44 pt hit area, the visual circle per `ComposerMetrics`.
- The text never runs under it: while it's shown, the text view's trailing text-container inset
  reserves its width **for the first line region only if possible, otherwise the whole field**;
  pick the approach that doesn't reflow text on each keystroke. It appears/disappears with
  `isTall`, which must not toggle back and forth around the threshold (add hysteresis if it does).
- The crab (mascot) stands on the card's top edge; make sure the two don't overlap at any width
  (crab on/off, Dynamic Type sizes, the draft and the conversation). If they would, the crab
  moves, not the button — say what you chose.
- All numbers become `ComposerMetrics` tokens.

## Acceptance

- Root cause per item (`file:line`).
- `ChatComposer` body no longer reads `contextUsage` (grep proof).
- Walk: new conversation (no usage) → first answer (usage arrives) → 69 % → 70 % → 91 %; the row
  never moves.
- Walk: type 1 line → paste 12 lines (expand appears in the corner) → delete back to 2 lines
  (expand disappears) — the text never jumps sideways and the caret stays put.
