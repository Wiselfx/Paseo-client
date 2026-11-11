# Shared rules for the H-round (device feedback 3, 2026-11-11)

The user tested IPA `5584843` on an iPhone and reported ten defects. Each one is something they hit
with their own fingers. This round fixes them **properly**: the user explicitly said "concrete
fixes, not hack jobs". Read `AGENTS.md` (UI rules R-1…R-6), `_R-common.md`, `_D-common.md` and
`_E-common.md` first. Everything in them still applies. This file overrides them where they
disagree (notably: there are no subagents on Pi; you work alone).

## Mission-critical, above everything else

**Responsiveness, smoothness, layout stability, UX.** In that order, and before features.

1. **Nothing per frame or per keystroke.** A scroll frame, an audio buffer or a keystroke may only
   do O(1) work and may only write SwiftUI state when a *boundary* is crossed (a Bool flips, an
   integer bucket changes). Accumulate in a non-observed reference box (see
   `TranscriptScrollTrack`) and publish the edge. A fix that works but invalidates a body per
   frame is a failed fix.
2. **Nothing jumps.** Content the user is looking at never moves unless the user moved it or asked
   for it (send, back-to-end, a jump). Showing/hiding chrome must not change the layout of what is
   under it. Size changes happen off-screen or are animated with a `Motion` token.
3. **R-1 narrow observation.** A view reads only what it draws. If a fix makes a big view (the
   composer, the transcript, the shell) read a value that changes often, extract a small child
   view that reads it instead.
4. **Motion through `Motion.*.resolved(reduceMotion:)`, haptics through `Haptics`, values through
   tokens.** New numbers go into `DesignSystem/Metrics.swift` (or the token file that fits) with a
   one-line reason. `Tools/style-lint/style-lint.sh` must pass on your files.
5. **Thread and isolation safety.** Swift 6 strict concurrency, no warnings. Nothing blocking on
   the main actor (audio session calls, file reads, image decode, network).

## What "a proper fix" means here (read this twice)

The bug list is the user's *symptom*, not your spec. The user wrote short sentences; they want the
behaviour to be right, not the sentence to be literally satisfied.

- **Root cause first.** Before you write code, find *why* it happens, with `file:line`, and write
  it down. A fix that suppresses the symptom (a magic offset, a delay, a `DispatchQueue.main.async`
  to "let layout settle", a threshold nudged until it stops happening, a `.id()` to force a
  rebuild) is rejected at review unless you prove there is no structural fix.
- **Design the behaviour, then implement it.** Each ticket gives the lead's intended behaviour.
  Where it leaves a choice, choose what a careful Apple engineer would ship, say why in one line,
  and keep it consistent with the rest of the app (Claude iOS feel, DSH style; `docs/UX-SPEC.md`).
- **Make it better overall, not just not-broken.** If the right fix means restructuring a small
  piece of code you own, do it. If it means touching a file you don't own, stop and say so in
  "Found, not fixed" with the exact change you'd make.
- **Every state.** Light and dark, Reduce Motion, VoiceOver, keyboard up and down, empty and long
  conversations, slow and failed network, the draft (new chat) screen as well as a conversation.

## Hard rules

- **Never touch Claude agents.** Never send to, prompt, create or probe any agent whose provider
  is `claude`, by any route (`paseo-probe`, MCP, CLI). Read what a `paseo-probe` subcommand does
  before pointing it at anything. For a live agent, create your own with `pi` +
  `opencode-go/beam-free` and archive it when done.
- **Upstream reference code** is `/home/paseo/dev/paseo-upstream-ref` (clean read-only clone of
  getpaseo/paseo at `v0.16.0-beta.1`, the running daemon's version). **Never open, read or grep
  `/home/paseo/dev/claude-style-lab`** — it is a lab with modified code, not a reference.
- Stay inside your ticket's **Owns** list. Other files: "Found, not fixed".
- Do not edit or weaken existing tests. Add tests in new files.
- No new dependencies. No force unwraps, no `fatalError`.
- Never commit secrets, real hostnames, tokens or the user's agent titles (the repo is public).

## Report what you see (proactive, but disciplined)

While you read code, you will notice other problems. **Fix them only if they are in your owned
files and directly affect your fixes** (list under "Also fixed"). Everything else goes under
"Found, not fixed", each with: `file:line`, what's wrong, the concrete failure a user would hit,
and the fix you'd propose. Don't pad this list; every item must be something you verified by
reading the code. "No findings" is a fine answer.

## Proof (every ticket)

- `swiftc -parse` on every touched UI file (the full app can't compile here; the lead runs the Mac
  gate and sends compiler errors back to you).
- PaseoCore changes: `cd Packages/PaseoCore && swift build --build-tests && swift test` green
  (`. ~/.local/share/swiftly/env.sh` first). Logic you can put in PaseoCore (pure state machines,
  parsers) belongs there, with tests.
- `Tools/style-lint/style-lint.sh` clean on your files.
- Commit on your branch, message starts with the ticket id (`H2: …`). Do not push, merge, rebase.

## Final message

1. Per numbered item: **root cause** (`file:line`), **the behaviour you built** (as the user will
   experience it), **the change**, **how you verified it** (tests, or a call-by-call walk of the
   hot path).
2. Hot-path statement: what runs per scroll frame / keystroke / audio buffer after your change.
3. "Also fixed".
4. "Found, not fixed".
5. Every Apple API you weren't 100 % sure of (name + the signature you used). The lead checks these
   on the Mac gate; DeepSeek has invented AVFoundation/SwiftUI signatures before.
6. "Unsure" — what needs the user's device to confirm.
