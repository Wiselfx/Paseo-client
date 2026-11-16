# M15: realtime voice mode

Branch `m15-voice-mode`. Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/tickets/PHASE3-BACKEND.md`,
`docs/research/09-owned-subscriptions.md` (any push must be owned/subscribed correctly), shared UI
rules at the top of `docs/tickets/M3-workspace-panel.md`. Builds on your M13 (Voice settings).
Cite path:line for wire claims (upstream protocol `messages.ts`, app voice components/hooks, i18n).

1. **Wire + store** (testable here): advertise the `voice` hello capability only when this build
   supports it (behind a single switch like `OwnedSubscriptions.isEnabled`), daemon readiness from
   `server_info.capabilities.voice/dictation`, `set_voice_mode` (agentId, accepted,
   `missingModelIds` → point the user to Settings → Voice to download them), streaming mic PCM
   chunks in the exact format upstream sends, `audio_output` decode + `audio_played` acks,
   `voice_input_state` (listening / speaking / thinking), transcripts into the conversation as
   upstream does, interrupt/mute. A `VoiceModeSession` store driven entirely by FakeDaemonClient
   tests (chunking, acks, ordering, interrupt, teardown on disconnect/reconnect).
2. **iOS audio** (small, Apple-only, list every spot): `AVAudioEngine` input tap converted to the
   wire's sample rate/format, playback queue for output chunks, `.playAndRecord` +
   `.voiceChat` mode with proper interruption/route-change handling, mic permission reuse from
   M8d dictation, keep the screen awake while live (`isIdleTimerDisabled`), stop cleanly on
   background.
3. **UI**: the composer's voice-mode button (mic disc, upstream wording), a calm live state in the
   composer area (volume meter, mute, stop/interrupt, a quiet thinking tone only if upstream has
   one), gated on readiness, Reduce Motion respected. Settings → Diagnostics: "Test audio" if
   upstream's diagnostic is a simple record/playback check.

Live checks: read-only (`server_info` capabilities). Do NOT start voice mode against any real
agent; the sandbox agent may be used only if voice mode needs no model download (otherwise rely on
tests). Done = PaseoCore clean build + full tests green, `swiftc -parse` on every touched UI/App
file, `Tools/api-audit` no new real findings. No background tasks or subagents; don't end your
turn while waiting. Commit "M15: voice mode", don't push. Final message: wire summary, what
changed, test totals, every Apple-only/unsure-compile spot.
