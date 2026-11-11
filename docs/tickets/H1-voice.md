# H1: voice that actually works, end to end

Branch `h1-voice`, from `foundation`. Read `_H-common.md` first.

The user, on device, IPA `5584843`: **"The voice and waveform don't work."** This is the third
round on voice (M15, E1, E1b). Each round fixed a plausible cause and shipped without anyone
proving the whole chain works. This round's job is to **prove every link of the chain** and fix
the ones that are broken. Plausible-looking code is not the bar; a traced, evidenced chain is.

**Owns:**
- `Voice/` (`VoiceAudioEngine.swift`, `DictationController.swift`)
- `Conversation/Composer/LiveWaveform.swift`
- `Conversation/Composer/ComposerPrimaryButton.swift` (voice states only)
- In `Conversation/Composer/ChatComposer.swift`: **only** `voiceBar`, `dictateButton`,
  `dictationOverlay`, the `DictationOverlay` struct and the voice-mode controls/mute wiring
  (≈ lines 590–700 and 1240–1300, 1450–1700 today). H3 edits the control row's context meter and
  the expand button in the same file; don't touch those, and keep your edits in your regions so
  the merge is clean.
- `Settings/VoicePage.swift`, `Settings/SpeechProviderSheet.swift` (only if the fix needs it)
- PaseoCore: `VoiceModeSession.swift`, `VoiceSettingsStore.swift`, the voice wire types, and new
  test files. `paseo-probe` may get a new **read-only or own-agent-only** voice subcommand.

## The two features (both are "voice")

1. **Dictation** — the mic button in the composer. On-device `SFSpeechRecognizer` +
   `AVAudioEngine` (`DictationController`). Expected: tap mic → the overlay shows a live waveform
   that clearly follows your voice → words appear in the draft → accept/cancel/send work.
2. **Voice mode** — the waveform primary button when the draft is empty and the host supports
   realtime voice. `VoiceAudioEngine` captures 16 kHz PCM, streams it to the daemon
   (`VoiceModeSession`), the daemon transcribes, runs the agent, and streams TTS audio back, which
   we play. Expected: tap → bar appears with a waveform that follows your voice → the agent hears
   you, answers, and you hear the answer; mute/stop work; the thinking tone plays while waiting.

The user's report covers both. Treat **both as broken until proven working**.

## 1. Trace the chain and find what's broken

For each feature, walk every link and write down, with `file:line`, what happens and what
evidence you have that it works. Links to check, at minimum:

- **Permissions:** mic + speech authorization requested on the right actor, the result honoured,
  denial surfaced (not a silent no-op). Info.plist keys present (`App/project.yml`).
- **Audio session:** category/mode/options for each feature; activation ordering vs.
  `engine.start()`; the off-main activation (`activateSessionOffMain`) actually completing before
  the tap is installed; dictation and voice not tearing each other's session down
  (`MicrophoneSessionOwner`); what happens on the second start after a stop.
- **Engine graph:** `inputNode` format read *after* the session is active (a format read before
  activation is 0 Hz / 0 ch on device and `installTap` with it either throws or delivers
  nothing); voice-processing enabled before or after the graph is prepared (Apple requires it
  before `prepare`/`start` and it changes the input format); a tap installed on a node whose format
  then changes; the player node connected for playback.
- **Capture → level:** the tap fires; the RMS is computed on the right channel/format; the level
  mapping (`AudioLevel.Band`) produces values that actually span 0…1 for real speech (log the raw
  dB once a second — `VoiceLog` — and reason from real iPhone numbers: with voice processing on,
  speech RMS is often −40…−20 dBFS); the push reaches `LiveWaveformBuffer` on the main actor.
- **Level → pixels:** `LiveWaveform`'s `TimelineView` is not paused, really ticks, and the
  `Canvas` really redraws per tick. Check the hosting: a `TimelineView` inside a `Button` label,
  inside a view whose parent is `.equatable()` or whose identity changes, or with
  `isActive` false at first render. Prove it redraws (reason from SwiftUI semantics, and add a
  DEBUG-only frame counter log if needed, removed before commit).
- **Recognition (dictation):** the request gets buffers in the recognizer's expected format;
  `shouldReportPartialResults`; `requiresOnDeviceRecognition` vs availability; partial results
  reach `store.draft` (`controller.dictation.onDraft`); the silence timer doesn't end it early.
- **Wire (voice mode):** the daemon actually advertises realtime voice, the start request is
  accepted, audio chunks are sent in the format and framing the daemon expects (compare with
  upstream: `/home/paseo/dev/paseo-upstream-ref/packages/app/src` (clean read-only clone of getpaseo/paseo at `v0.16.0-beta.1`, the running daemon's version) — `audio/`,
  `components/realtime-voice-overlay.tsx`, and the server's voice handler under
  `packages/server`), the daemon's transcripts/agent output/TTS events are decoded (unknown type
  → silently dropped is a classic failure), playback chunks decode and play.

**Live proof for the wire (required):** the daemon runs locally on `:6767`. Prove the voice-mode
protocol end to end without a phone: a `paseo-probe` voice subcommand (or a PaseoCore test against
the live daemon, skipped when no daemon) that creates **its own** `pi` + `opencode-go/beam-free`
agent, starts voice mode for it, streams a short 16 kHz mono PCM16 file of spoken words (generate
one with any TTS available on this box, e.g. `espeak-ng`/`pico2wave` if installed, or ship a tiny
fixture), and prints the transcript and whether TTS audio came back. If the daemon has no speech
provider configured, report exactly what's missing (read-only config check) — that may be the
user's real problem, and the app must then **say so** instead of silently doing nothing. Archive
the agent afterwards. Never target any `claude`-provider agent.

## 2. Fix what's broken, properly

- Every failure path the user can hit must be **visible**: no permission, speech unavailable,
  daemon has no voice/speech provider, start rejected, engine failed to start, route change
  killed the tap. Use existing copy where it exists (upstream `en.ts` / our strings); if you need
  a new line, propose it in your final message and use a neutral placeholder the lead can replace.
- Starting and stopping 10 times in a row must work identically each time (no leaked taps,
  sessions, observers or tasks).
- Interruptions (a call, Siri), route changes (AirPods in/out), backgrounding: recover or stop
  cleanly, and the UI reflects it.
- The waveform must visibly follow speech in both features: silence = a calm row of dots; normal
  speech fills roughly 40–80 % of the height; a shout reaches the top. Tune the bands from the
  real numbers you reason about, and keep one mapping function (no per-call-site fudge).

## 3. Mission-critical constraints for this ticket

- No audio-session or engine call on the main actor that can block (`setCategory`, `setActive`,
  `engine.start`, `setVoiceProcessingEnabled` all can).
- Per audio buffer: O(buffer) DSP on the capture queue, at most one main-actor hop per 1/30 s,
  and **no SwiftUI state write per buffer** (the waveform reads the reference buffer from its own
  timeline).
- The composer must not re-render per level tick. The only per-tick work is the `Canvas`.

## Acceptance

- Written chain trace for both features in your final message, each link marked
  *verified (how)* / *fixed (root cause)* / *needs device (what log line proves it)*.
- Live wire proof output pasted (or the exact missing daemon configuration).
- PaseoCore tests for any logic you moved/added (level mapping, state machine, chunk framing).
- A short **device test script** for the user (≤ 10 steps) and the `os.Logger` lines to look for
  if it still fails, so the next report is diagnostic instead of "doesn't work".
