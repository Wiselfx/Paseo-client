# D2: composer, paste, voice meters, draft send crash

Branch `d2-composer`, from `foundation`. Read `_D-common.md` first.

**Owns:**
- `Conversation/Composer/` (all files, plus new files there)
- `Voice/DictationController.swift`
- `Voice/VoiceAudioEngine.swift` (the level path only)
- `Shell/ShellView.swift` (the `DraftChatView(onCreated:)` closure only)
- The draft-creation call path in `Draft/DraftChatView.swift`'s `composer` property only (D1 owns
  the rest of that file)

D1 places `ComposerView` in a bottom `safeAreaBar`. Don't change where it sits; change what it
draws.

## 1. The trailing control is one morphing button (Claude's composer)

**Today:** the row reads + · model chip · context ring · voice-mode button · mic · orange send
(dimmed when empty). That's five controls, and two of them look alike.

**Target**, left to right: `+` · model chip · *(spacer)* · mic · **primary**. The primary is one
44 pt hit area, a 36 pt circle, whose content follows state:

| State | Primary shows | Fill / glyph | Tap |
|---|---|---|---|
| Empty draft, idle, voice available | `waveform` | `Palette.ink` fill, `Palette.background` glyph | Start voice mode (today's `toggleVoiceMode`) |
| Empty draft, idle, voice unavailable | `arrow.up` | `Palette.chip` fill, `tertiaryInk` glyph, disabled | none |
| Has text or a ready attachment | `arrow.up` | `Palette.ink` fill, `background` glyph | Send (long-press queues, as today) |
| Empty draft, agent running | `stop.fill` | ink fill | Stop |
| Voice mode active | `waveform` (live, see §4) | `Palette.orange` fill | Toggle mute, as today |

- **The morph:**
  - the glyph changes with `.contentTransition(.symbolEffect(.replace.downUp))`;
  - the fill crossfades with `Motion.swap`;
  - the circle never changes size;
  - when Reduce Motion is on, it switches instantly.

  It must look like one button changing its mind, not two buttons swapping.
- **Pressed state:** every composer button scales to 0.92 on touch-down with `Motion.feedback`
  (one `ButtonStyle` in `Composer/`, `ComposerPressStyle`).
  - Today's send uses a raw gesture with no pressed state. Rebuild it as a `Button` with that style,
    plus a `simultaneousGesture(LongPressGesture(minimumDuration: 0.45))` for queue.
  - A long press must not also send.
- **The orange send is gone.** Orange is reserved for live voice. The send is ink, like Claude's
  white-on-dark circle.
- **Remove `voiceModeButton` from the row:** voice mode now lives in the primary.
- **The mic (dictation) stays** as a chip-coloured circle, left of the primary.
- **The context ring:** on device it is indistinguishable from a loading spinner.
  - Remove it from the row below 70 % used.
  - From 70 % up, show a 24 pt ring with the integer percent inside, in `.paseo(.caption2, weight: .semibold)`
    `.monospacedDigit()`. Below 90 % it is ink at 0.6; from 90 % it is ink.
  - It still opens the context sheet.
- **The model chip must never read "Bea… Me…":**
  - give it `layoutPriority(1)` and a `ViewThatFits` of `[model + thinking]`, then
    `[model only]`, then `[model truncated middle]`;
  - drop the thinking label before truncating anything;
  - the chip is 36 pt tall inside a 44 pt hit area.

## 2. Paste images straight into the field

**Today:** SwiftUI `TextField(axis: .vertical)` can't receive pasted images. The `+` menu's "Paste
image" reads only `UIPasteboard.general.image`, so only the first image arrives.

**Build** `ComposerTextView`: a `UIViewRepresentable` over a `UITextView` subclass that replaces
`composerTextField` in both modes.
- **Typing and layout:**
  - text binding;
  - focus binding (bridge the existing `@FocusState` through `becomeFirstResponder` /
    `resignFirstResponder` in `updateUIView`, and report back from the delegate);
  - the placeholder label (same string and colour as today);
  - `Typography`'s body face (`UIFont` from the same `Typography` source; add an internal UIKit
    accessor if one doesn't exist);
  - `Palette.ink` tint;
  - Dynamic Type (`adjustsFontForContentSizeCategory`).
- **Growth:** the view grows with its content to `composerFieldLineLimit` lines, then scrolls inside
  itself (`isScrollEnabled` flips at the cap). Height is reported through `sizeThatFits(_:uiView:context:)`.
  No layout jump on the first character.
- **Paste:**
  - override `canPerformAction(_:withSender:)` to allow `paste(_:)` when `UIPasteboard.general.hasImages`;
  - override `paste(_:)`: if the pasteboard has images, load **all** of them from `itemProviders`
    (`loadDataRepresentation(for: .image)` / `.png` / `.jpeg`, off main) and hand each to the existing
    `attachImage(data:fileName:)` path; paste text normally otherwise.
  - Mixed text plus images: attach the images **and** insert the text.
  - Set `pasteConfiguration` so drag-and-drop of images onto the field works too.
- **The `+` menu "Paste image"** attaches every image on the pasteboard (`UIPasteboard.general.itemProviders`,
  same loader), not just the first.
- **Keep:**
  - the mention query (`@`) and slash-command behaviour (the text binding drives them as before);
  - ⌘↩ sends;
  - `accessibilityIdentifier("composer.draft")`.
- `PhotosPicker`'s `maxSelectionCount: 10` stays.

## 3. Draft send crash (P0)

**Repro from the user:** in a new session, typing and sending crashes the app. The agent **was**
created and answered, as seen after relaunch.

**Likely cause:** `send()` in draft mode runs a `Task` that:
1. awaits creation;
2. writes `localTray` (`@State` of a composer that `onCreated` is about to destroy);
3. awaits `refreshAgents()`;
4. calls `onCreated`, which nils `draft` and swaps the main view.

At the same time `focused = false` and the draft's `pendingPrompt` animation are in flight. The
lead is fetching the device crash log. Until then, make the path structurally safe:
- **Creation is owned by the shell, not the view.** `DraftChatView` gets an
  `onSubmit(DraftSubmission)` instead of creating the agent in the composer's `Task`.
  - `ShellView` runs `create`, then `select(agentId)`, from a task it owns.
  - Only after the conversation store exists does it drop `draft`.
  - Don't `await session.refreshAgents()` before switching: the agent update arrives on the
    subscription. If `select` needs the snapshot, poll the session's agent map for up to 2 s.
- **No `@State` writes after an `await`** in a view whose identity may be gone. Clear the tray
  before the hop, keeping a copy to restore on failure.
- **On failure:** the draft stays, its error shows inline (today's `draft.error`), and the tray is
  restored.
- **The transition:** the pending bubble in the draft and the first user bubble in the new
  conversation should look like the same bubble. Crossfade with `Motion.fade`, with no slide.

## 4. Voice meters that move

**Today:** the dictation overlay's 5 bars and the voice bar's 5 bars barely move. The user "can't
tell if it's working".
- They scale uniformly by one smoothed level.
- `.measurement` mode turns off AGC, so speech RMS sits around 0.005–0.03.
- `(raw − 0.008) × 22` leaves the bars near the 0.15 floor.

**Build** one `LiveWaveform` component (`Composer/LiveWaveform.swift`):
- **Data:** a ring buffer of the last 28 levels, pushed at most at 30 Hz. It's drawn with
  `Canvas` as rounded 3 pt bars, 2 pt gap, centred vertically, height `max(3, level × 22)`, scrolling
  right-to-left (newest on the right), the way Voice Memos does.
- **Idle:** silence shows a calm row of 3 pt dots. That alone tells the user the mic is live.
- **Level mapping:** `dB = 20·log10(max(rms, 1e-5))`, clamp −55…−10 dB to 0…1, then attack 0.6 and
  release 0.15 smoothing. Apply it in `DictationController.updateLevel` **and** in the voice engine's
  level before it reaches `voice.handleCaptureVolume`.
- **Push from the audio tap at its native rate, render at ≤ 30 Hz:**
  - `TimelineView(.animation(minimumInterval: 1/30, paused: !isActive || reduceMotion))`;
  - the buffer lives in a reference type, not `@State`;
  - Reduce Motion shows a single bar whose height tracks the level, without scrolling.
- **Use it in** `DictationOverlay` (replacing `meter`), in `VoiceBar` (replacing the 5 capsules),
  and **inside the primary button** while voice mode is active: 5 tiny bars from the same buffer,
  replacing the static `waveform` glyph.
- **Voice mode "doesn't work at all":** trace why. Check that:
  1. `voice.isVoiceAvailable` is true for the user's host (Voice settings show "Dictation on ·
     Voic…");
  2. `startCapture` runs on `.listening`;
  3. `onVolumeLevel` is bound before capture starts (`bind()` runs in `.task`, which may be after
     the phase change);
  4. errors surface as a toast rather than vanishing.

  Report what you found. Don't start voice mode against the user's real agents in any test; reason
  from the code.

## Copy

No new strings, except the existing accessibility labels reused for the new primary states ("Send
message", "Stop response", "Enable Voice mode", …).

## Proof

- `swiftc -parse` on every touched file.
- Final message:
  - the primary's state table as built;
  - the voice-mode trace findings;
  - every UIKit/Apple API you were unsure of (`UITextView` paste overrides, `itemProviders` loading,
    `contentTransition(.symbolEffect(.replace.downUp))`, `Canvas` in `TimelineView`).
