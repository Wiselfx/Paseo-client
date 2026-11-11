# H2: the send runway, back-to-end with the keyboard, and a header that gets out of the way

Branch `h2-transcript`, from `foundation`. Read `_H-common.md` first. This is the most
feel-critical ticket of the round: the transcript is where the user lives.

**Owns:**
- `Conversation/Transcript/ChatTranscript.swift` (runway, follow, back-to-end, scroll tracking)
- `Conversation/Screen/ChatScreen.swift` (top/bottom chrome wiring only)
- `Conversation/Screen/ChatHeader.swift`
- `Conversation/Screen/ChatController.swift` (scroll/chrome state only)
- `DesignSystem/Components/ShellHeader.swift` **only** if the header's look changes there; H4
  touches `LaunchSkeleton`/`HomeHeroLayout`, not `ShellHeader` — coordinate through your report.
- `DesignSystem/Metrics.swift` / `Motion.swift`: new tokens for this ticket only.
- Pure logic (runway arithmetic, header reveal state machine) may move to PaseoCore with tests.

## 1. After sending, a big empty space stays at the bottom (user bug 2)

User: *"If you send a message, it scrolls up to show the assistant message but then it leaves a
lot of space at the bottom that you can scroll to, but it shouldn't be like that."*

**What's there (lead's reading; confirm or correct it):**
- The send runway (`SendRunway`, `ChatTranscript.swift:771`) is a `Color.clear` of
  `runway.height` inside the end marker (`:143`). It opens at a full viewport
  (`openRunwayIfPossible`, `:459`), then follows `visibleHeight − tailTurnHeight − slack`
  (`runwayHeight`, `:493`).
- It **never closes** when the answer is short: after the turn ends, the runway stays for the life
  of the screen. Scroll up and back down and you land on a screen of nothing.
- `resizeRunway` (`:487`) **grows** it again whenever `visibleHeight` grows — dismissing the
  keyboard after a send adds ~300 pt more empty room.
- If the tail turn's first height report lands before `beginRunway` sets `runway.turnId`
  (`:301`/`:473` guard), `measured` stays false and the runway sits at a full viewport until the
  turn's height next changes.

**Behaviour to build (Claude iOS / ChatGPT, done right):**
- On send, your message glides to the top under the header and the answer streams below it. The
  room under the answer exists **only to make that position reachable**.
- **The runway only ever shrinks after it opens, and it shrinks invisibly.** Whenever the scroll
  is idle (and when the turn finishes), trim it to what is currently on screen:
  `runway = max(0, runway − max(0, distanceFromBottom))`, i.e. remove the part that's below the
  viewport. Removing off-screen space changes nothing the user sees. Never let it grow back
  (keyboard dismissal, rotation): a viewport change may only trim.
- Result: while you sit at the anchor you see your message at top and the answer below (correct);
  as soon as you scroll up and let go, the empty space below is gone; scrolling back down ends at
  the last line of the answer, resting on the composer. When the next message is sent, a new
  runway opens.
- When the turn finishes while you're still at the anchor, leave the visible space (don't yank the
  content down); it disappears the first time you scroll.
- Fix the measure/turnId ordering so the runway is correct from the first frame.
- One write per idle/turn-end event, never per scroll frame.

## 2. "Back to the end" shows while the keyboard is open (user bug 10)

User: *"The scroll to bottom button appears in a chat when you have your keyboard open."*

**What's there:** `updateBackToEnd` (`:434`) shows the button when not following and
`distanceFromBottom > visibleHeight`. With the keyboard up, `visibleHeight` shrinks to ~40 % and
`contentInsets.bottom` grows by the keyboard; any transient where the offset hasn't caught up
(keyboard animation, the focus-triggered `requestEndScroll` glide in `ChatScreen.swift`
`UserActivityWiring`, the runway) crosses that threshold. Find the actual sequence(s) — there may
be more than one — and fix the cause, not just the threshold.

**Behaviour to build:**
- Focusing the composer at the end of the conversation keeps the last line resting on the
  composer as the keyboard rises (iMessage). No button, no flash, not even for one frame.
- The threshold is in terms of the **keyboard-independent** viewport (there is already
  `stableViewportHeight`): "more than one screen from the end" means a real screen, not the sliver
  above the keyboard.
- Never flip the button's visibility during a programmatic scroll (`.animating` phase) or the
  keyboard's animation; decide on idle/interacting only.
- Decide, and justify in one line, whether focusing the composer while reading history should
  still jump to the end (`requestEndScroll` on focus). Recommendation: yes only if you were
  within a screen of the end; otherwise keep the reading position and let the button offer the
  way back (that's what iMessage does).

## 3. The header is ugly — make it get out of the way (user bug 9)

User: *"The header is ugly, we need to do something about it. Maybe make it appear only when
scrolling up a lot?"* See the user's screenshot description: a 20 pt serif title, truncated, with
a workspace line under it, floating over the transcript with only the `.soft` scroll-edge effect —
a user bubble showed clearly through the subtitle.

**Behaviour to build (lead's decision):**
- **Auto-hide on reading, reveal on intent.** The header (both glass buttons and the title)
  slides up and fades out when the user drags the transcript toward newer content past a small
  threshold; it comes back when the user scrolls toward older content by a deliberate distance
  (token, start at ~⅓ of the stable viewport — "a lot", per the user), or reaches the top of the
  loaded transcript, or the transcript can't scroll at all, or find is open, or a header sheet
  /menu/rename is active, or VoiceOver is running (never hide chrome from VoiceOver), or the
  conversation just opened. Programmatic scrolls (send glide, back-to-end, jumps) never change it,
  except a jump *to an older turn* may reveal it.
- **No layout shift, ever.** Hiding the header must not move the transcript. Today the header is a
  `safeAreaBar`, so its height is part of the safe area; if you hide it by removing it, every row
  jumps. Choose a structure where the top inset is constant (e.g. the bar keeps its height and
  only its content translates/fades, or the header becomes an overlay with a fixed content margin).
  Justify the choice and check: the runway's `.top` landing position, the find bar, the rail, the
  history-prepend anchor and the turn jump lead all still line up.
- **State changes only at the edge.** Accumulate signed scroll distance in the existing
  non-observed `TranscriptScrollTrack`; publish one `Bool` (`controller.headerHidden` or a narrow
  `@Observable` child) when it flips. The header reads only that Bool. No per-frame body.
- **Motion:** a `Motion` token, interruptible (a reversal mid-animation retargets smoothly);
  Reduce Motion → opacity only.
- **Look when visible:** the title becomes the Claude-iOS header: a single-line **sans** title
  (`.paseo(.headline)`, not the serif `.title`), the workspace line kept as a small secondary line
  only if it fits on one line (otherwise drop it from the bar; it's in the title menu). Give the
  visible bar a backdrop that stops text showing through (`.scrollEdgeEffectStyle(.hard, for:
  .top)` or equivalent token-driven material) — judge it in light and dark. When hidden, the
  status-bar area keeps a soft edge so text doesn't collide with the clock.
- The sidebar stays reachable while the header is hidden (edge swipe already exists — verify it
  works over the transcript) and the panel by its edge swipe; mention this in your report.

## Acceptance

- Root cause per item with `file:line`; for item 2 the exact event sequence(s).
- Walk these sequences call by call in your final message and state what the user sees:
  1. send a short message, answer is 3 lines; wait; scroll up a little; let go; scroll down.
  2. same, but dismiss the keyboard after sending.
  3. send a message whose answer is 2 screens long.
  4. at the end, tap the composer; type; dismiss.
  5. scrolled 5 screens up, tap the composer.
  6. open a long conversation; flick down; flick up a little; scroll up a lot; reach the top.
  7. open find; jump to message; rename via the title menu.
- Hot-path statement: what runs per scroll frame now (must stay O(1), no state writes except
  edges).
- Tests in PaseoCore for any runway/header state machine you extract.
