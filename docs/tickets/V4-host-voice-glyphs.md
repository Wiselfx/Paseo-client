# V4: host cards, dictation, provider glyphs

Worker: DeepSeek. Read `AGENTS.md`, `_U-common.md`, `docs/UX-SPEC.md` §0 first. Upstream checkout:
`/home/paseo/dev/paseo-reference/packages`. Sweep: `/tmp/reviews/parity-sweep-2026-11-09.md` B17, B19.
Copy verbatim from upstream, cite file:line in your final message.

**Compile gate (new):** you can compile the real app on the user's Mac. Push your branch (never `main`,
never `foundation`): `git push -q origin <your-branch>`, then
`ssh -i ~/.ssh/paseo_build_ed25519 -o BatchMode=yes claude@host.orb.internal build <your-branch>`.
It prints Swift errors/warnings and `** BUILD SUCCEEDED/FAILED **`. Loop until it succeeds with no new
warnings in your files. That is the only command it accepts; don't try others.

## 1. Host idle-cleanup and restart-recovery cards (B17)
Upstream `app/src/screens/settings/host-page.tsx:297-298`, `idle-runtime-cleanup-card.tsx`,
`restart-recovery-card.tsx`; wire `protocol/src/messages.ts:240-271` (`idleRuntimeCleanup`, `restartRecovery`,
both optional/COMPAT-gated). Port both cards into our host settings page (find where Paseo-tools / Browser-tools
toggles live in `Chat/PaseoSettingsView.swift`, same daemon-config patch path). Respect the COMPAT gates: hide a
card when the host doesn't report the field. Tests for decode + patch encoding with `FakeDaemonClient`.
**Never** send a config patch to the real daemon; tests only (sandbox daemon is fine).

## 2. Dictation (B19, upstream `app/src/components/dictation-controls.tsx`)
- Port upstream's insert-and-send and elapsed timer overlay, wording verbatim.
- Move `AVAudioSession.setActive` (and category setup) off the main thread in `Chat/DictationController.swift`
  (Xcode reports a hang-risk fault). Keep the existing nonisolated-helper pattern there: closures handed to
  Apple frameworks must be formed in `nonisolated static` functions or be `@Sendable` (a closure formed on the
  main actor and called off-main traps at runtime). Same for `Chat/VoiceAudioEngine.swift` if it activates the
  session on main.

## 3. Provider glyphs (composer model chip)
`ComposerModelChip` / `ProviderGlyph` show a monogram. The provider snapshot carries `iconSvg`
(`ProviderSnapshotEntry.iconSvg`). Render it: a small SVG-path renderer for the subset these icons use (check
the actual strings from the fixtures/upstream: likely single-color `path d=` with M/L/H/V/C/S/Q/T/A/Z, maybe
`viewBox`), drawn as a SwiftUI `Shape` in the ink color (monochrome, UX-SPEC §0.1). Fall back to the monogram
for anything unparseable. Put the parser in PaseoCore (pure, tested with real icon strings), the Shape in PaseoUI.

## Done
PaseoCore clean build + all tests green, Mac gate BUILD SUCCEEDED, commit `V4: ...` on `v4-host-voice-glyphs`.
