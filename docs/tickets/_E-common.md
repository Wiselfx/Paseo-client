# Shared rules for the E-round (device feedback 2, 2026-11-11)

The user tested the D-round IPA (`3b65c9d`) on an iPhone, next to the official Claude iOS app.
The verdict: we stay native (the React Native experiment lost). The terminal tab is "very smooth".
Everything else on this list is a defect the user hit with their own fingers.

**Mission-critical, above everything else: responsiveness, smoothness and UX.**
- A keystroke, a tap, a drawer drag must never stall, drop a frame, lose focus or jump.
- A fix that works but adds main-thread work per frame or per keystroke is a failed fix.
- If you have to choose between "more features" and "this feels perfect", choose perfect.

Read `AGENTS.md` (UI rules R-1…R-6), `_R-common.md` and `_D-common.md` first. Everything there
applies. This file adds to them.

## Hard rule: never touch Claude agents

- Never send to, prompt, create or test against any agent whose provider is `claude`: through
  `paseo-probe`, the MCP, the CLI or anything else.
- If a test needs a live agent, use `pi` with `opencode-go/beam-free`.
- `paseo-probe` subcommands can send messages into a conversation. Read what a command does before
  pointing it at any agent.

## Work style

- **Use UIKit where UIKit is the right tool, SwiftUI where SwiftUI is.**
  - UIKit: text input, first responder, gesture-tracked motion, `WKWebView`, `AVPlayer` layers,
    layer shadows, anything per-frame.
  - SwiftUI: layout, static content, sheets, lists of value rows.
  - Do not wrap something in a `UIViewRepresentable` just to style it.
  - Do not fight UIKit state (first responder, scroll offset) from SwiftUI state on every update.
- **Root cause first.** Every fix in your final message states the root cause in one sentence,
  with `file:line`. "Tweaked until it looked right" is rejected.
- **Read before you write.** Read every file you touch end to end, and the views that host it.
- **You may use OMP subagents.** Use up to 3, each in its own worktree, only for independent
  sub-parts. You own and review their diffs; the final branch is yours.
- **Fold in what you find.** If you notice a nearby defect (feel, perf, layout, correctness)
  inside your owned files, fix it and list it under "Also fixed". If it's outside your files,
  list it under "Found, not fixed".
- **No literal values outside `DesignSystem/`** (`Tools/style-lint/style-lint.sh` must pass on
  your files).

## Proof (every ticket)

- `swiftc -parse` on every touched UI file.
  - PaseoCore changes: `swift build --build-tests && swift test` green.
- `Tools/style-lint/style-lint.sh` clean on your files.
- Commit on your branch with the ticket name (`E1: …`). Do not push, merge or rebase.
- The lead compiles your branch on the Mac gate and sends compiler errors back to you.
- **Final message:**
  - each numbered item: the root cause (`file:line`), the change, how you verified it;
  - "Also fixed";
  - "Found, not fixed";
  - every Apple API you weren't 100 % sure of;
  - "Unsure".
