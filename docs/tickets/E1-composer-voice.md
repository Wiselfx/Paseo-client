# E1: the composer keeps the keyboard; voice that actually listens

Branch `e1-composer-voice`, from `foundation`. Read `_E-common.md` first.

**Owns:**
- `Conversation/Composer/` (except `ComposerPrimaryButton.swift`, which E2 owns)
- `Conversation/Screen/ChatScreen.swift` (focus wiring only)
- `Draft/DraftChatView.swift` (focus wiring only)
- `Voice/`
- `DesignSystem/Metrics.swift` (composer metrics only, §4)
- the voice store in PaseoCore, if the voice-mode fix needs it (tests in new files)

## 1. P0: the keyboard closes after every keystroke

The user types one letter, or deletes one, and the keyboard drops. Every time.

**Root cause (found by the lead; confirm it):**
- D2 replaced the SwiftUI `TextField` with `ComposerTextView` (a `UITextView`). The
  `.focused($focused)` modifier went with it, so **no view is bound to the composer's
  `@FocusState` any more**.
- SwiftUI refuses to set a `FocusState` to `true` when no focusable view is bound to it.
  - `textViewDidBeginEditing` writes `true`, and SwiftUI keeps it `false`.
  - The next keystroke writes `text`, `updateUIView` runs with `isFocused == false`, and
    `bridgeFocus` (`ComposerTextView.swift:58`) calls `resignFirstResponder()`.

**Build:**
1. **Replace the `@FocusState` with a plain `Bool`.**
   - `ChatScreen` and `DraftChatView` hold `@State private var composerFocused = false`.
   - Pass it down as `Binding<Bool>`: through `ChatComposer`, `ChatInputWiring` and
     `UserActivityWiring`, replacing every `FocusState<Bool>.Binding` / `@FocusState.Binding` for
     the composer.
   - `ClaudeFindBar` and the other real `TextField`s keep their own `@FocusState`. Don't touch
     them.
2. **`ComposerTextView` takes `@Binding var isFocused: Bool`** (drop the two-parameter
   `isFocused` + `focus` pair).
3. **Make the bridge edge-triggered, not level-triggered.**
   - The coordinator stores `lastAppliedFocus: Bool`.
   - `updateUIView` calls `becomeFirstResponder()` / `resignFirstResponder()` **only when
     `isFocused != lastAppliedFocus`**, then records it.
   - The delegate's begin/end update both the binding (deferred one turn, as now) and
     `lastAppliedFocus`, immediately.
   - Result: a text change can never touch the responder chain, and a SwiftUI update that
     carries a stale value can't fight UIKit.
4. **`updateUIView` must do no work per keystroke** beyond the text compare.
   - `applyStyle` already short-circuits; keep it that way.
   - Don't set `uiView.text` when the change came from the view itself (it already compares).
   - Make sure `selectedRange` is never reset during typing, autocorrect or marked (CJK / dictation)
     text: skip the external-write branch while `uiView.markedTextRange != nil`.
5. **Keep every existing behaviour:**
   - tap outside dismisses (V5);
   - the find bar and sheets dismiss the keyboard;
   - mentions and dictation insert at the end;
   - `composerFocusRequested` focuses;
   - the model chip dismisses before opening its sheet;
   - send keeps today's behaviour.

**Verify by reasoning, and write it in your final message.** Walk the exact call sequence for each
of these:
- type "hello";
- backspace ×3;
- autocorrect replacing a word;
- paste text;
- paste an image;
- insert a mention from the menu;
- dictation inserting text;
- the pill → card growth in the draft (the field keeps one structural position; keep that);
- send;
- open the model sheet, then return.

In none of them may the field resign unless the sequence says so.

## 2. The waveform barely moves, even when yelling

**Root cause (found by the lead; confirm it):**
- `LiveWaveform.body` is `TimelineView(...) { _ in ... Canvas { ... buffer.recent(...) } }`.
- The closure ignores the timeline context, and `buffer` is a non-observable reference with an
  unchanged identity. SwiftUI sees equal inputs and does not re-run the `Canvas` renderer each
  tick. The bars update only when something else invalidates the composer.

**Build:**
1. Make the `Canvas` depend on the tick: pass `context.date` into the drawing (for example a
   `let tick = context.date` read inside the renderer, or `Canvas` placed so its renderer captures
   the date). Confirm in your message why SwiftUI now redraws on every frame, and that it still
   pauses at `isActive == false`.
2. Levels:
   - Dictation (`.measurement`, AGC off): keep −55…−10 dB.
   - Voice mode (`.voiceChat`, AGC on): measure what RMS range that mode really produces (reason
     from Apple's docs; log it with `os.Logger` category `voice.level` at debug level, once per
     second, so the user's next device run shows it). Then give voice mode its own band (start at
     −50…−15 dB).
   - Apply a perceptual curve (`pow(x, 0.7)`) after normalising, so normal speech fills 40–80 %
     of the height, and a shout reaches the top.
3. Size: the user calls it "tiny".
   - In the dictation overlay and in the voice bar, the waveform **fills the available width**:
     the bar count is derived from the width (`GeometryReader` once at layout, or
     `onGeometryChange`, never per frame). Keep the 3 pt bar and 2 pt gap.
   - `maxBarHeight` is 28 in the overlay and the voice bar.
   - The silent row stays a calm row of 3 pt dots.
4. Performance:
   - One `Canvas`, no per-bar views.
   - The audio tap never touches the main actor more than 30 times per second.
   - The level is never published into `@Observable` state that the composer body reads per
     frame. Check `DictationController.level` (`DictationController.swift:18`): if the composer body
     reads it, stop that.

## 3. Voice mode (back and forth) does not work at all

The user starts voice mode, and nothing works. We have no device log, so first find it by reading.

1. Trace the whole path end to end, and write the trace in your final message (one line per hop
   with `file:line`):
   - the button;
   - session start;
   - the `AVAudioSession` category, mode and activation;
   - engine start;
   - the tap;
   - format conversion (the hardware rate → the daemon's expected rate and format);
   - the frames sent (which message, which encoding);
   - the daemon's replies (transcripts, the agent's audio);
   - playback;
   - turn-taking;
   - stop.
2. Compare every hop with upstream:
   - `/home/paseo/dev/paseo-reference/packages/app/src` (search `voice`, `realtime`,
     `dictation`);
   - the server message schema `packages/server/src/shared/messages.ts`.
   - Message names, field names, audio format, sample rate, chunk size and the start/stop
     handshake must match exactly.
   - Every mismatch is a bug: fix it.
3. Check the classic iOS failures, and fix any you find:
   - `installTap` with a format that doesn't match `inputNode.outputFormat(forBus: 0)`;
   - the converter never primed;
   - the engine started before the session went active;
   - the session deactivated by dictation while voice mode runs;
   - playback through an `AVAudioPlayerNode` never attached or connected, or connected with the
     wrong format;
   - `.voiceChat` without `.defaultToSpeaker` (inaudible earpiece output);
   - route changes and interruptions not handled;
   - work on the main actor that blocks.
4. Add `os.Logger` (subsystem the app's bundle id, category `voice`) at each hop:
   - start;
   - session active;
   - the first frame sent;
   - every 50th frame;
   - the first reply;
   - each daemon voice event type;
   - playback start;
   - every error, with its domain and code.
   - Info level for milestones, error level for failures, nothing per frame.
   - The user's next run must show where it stops.
5. If the daemon needs a capability or a provider setting the host doesn't have, voice mode must
   say so in the composer (existing upstream copy from `en.ts`) instead of silently doing nothing.

## 4. The composer's shape and spacing match Claude's

The user: "See how nice their composer looks, its spacing. We should have the same."
- Screenshots, outside the repo (private, never commit them): `/home/paseo/dev/e-round-shots/`.
  - Claude's: `claude-composer-empty.jpg`, `claude-composer-typing.jpg`.
  - Ours: `ours-composer-dark.jpg`, `ours-chat-dark.jpg`.
  - All are 1284 px wide at 3×, so 1 pt = 3 px.
- Open them and measure them yourself. The lead's measurements, in pt, for you to confirm:

| Part | Claude |
|---|---|
| Card side margin to the screen | ≈ 8 |
| Card corner radius | ≈ 24 (continuous) |
| Card fill | `Palette.composer`, a hairline `composerBorder`, a very soft shadow in light (black ≈ 6 %, radius ≈ 12, y ≈ 2) |
| Text inset: leading, top | ≈ 13–14 from the card's edge; the first line's cap top ≈ 18 below the card top |
| Controls row inset: leading, trailing, bottom | ≈ 8 each: the circles sit close to the card's edge, concentric with its corner |
| Gap between the text and the controls row | ≈ 12 |
| `+` | a 36 pt circle, `Palette.chip` fill |
| Model chip | 36 pt tall capsule, `Palette.chip` fill, model in `ink`, effort in `secondaryInk`, ≈ 14 horizontal padding |
| Mic (dictate) | **a 36 pt circle with the `Palette.chip` fill** (ours is a bare glyph) |
| Voice/send | a 36 pt circle (E2 owns its colour) |
| Gaps between the controls | ≈ 8 |
| Total card height at rest | ≈ 97 |

**Build:**
- Make our composer match these values in **both** the draft and the conversation, in light and
  dark.
- Put every number in `Metrics`/`Space`/`Radius` tokens (a `ComposerMetrics` namespace in
  `DesignSystem/Metrics.swift` is fine: you may edit that file for this).
- The ring meter and the fast-mode chip, when present, use the same 36 pt chip language.
- Keep 44 pt hit areas around the 36 pt visuals.
- The rest pill in the draft (before focus) must grow into exactly this card with no field
  re-creation (§1) and no jump: one `Motion.disclosure` change of height and corner.
- Final message: a before/after table of every value.

## Proof

As in `_E-common.md`. Also:
- the §1 call-sequence walk;
- the §3 trace and the upstream diff table: hop | ours | upstream | fixed?
