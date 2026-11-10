# Shared rules for the R-round (refactor and polish)

You implement exactly what your ticket says. The lead owns taste and UX decisions. The ticket
spells out what to build, how it should move and what it should cost. **Don't redesign, add
features or re-decide anything the ticket decides.** If the ticket is ambiguous or something it says
is impossible, pick the most literal reading, do it, and list it under "Unsure" in your final message.

## Read first

- `docs/refactor/PLAN.md`: the whole plan. §1 (rules R-1…R-6) applies to every line you write.
- `docs/UX-SPEC.md`: the behavior spec. It is amended 2026-11-10; the amendments win.
- `docs/refactor/audits/A-design-system.md`, `B-perf.md` and `C-ux-flows.md`: findings with file:line.
  They are evidence, not orders. Line numbers may have drifted; verify before acting.
- `AGENTS.md`.

## Hard rules

- **Files:** only the paths your ticket owns, plus new files you add under them. If something outside them
  must change, don't change it; name it in your final message.
- **Wording:** never invent user-facing copy.
  - Keep existing strings, or port upstream verbatim from
    `/home/paseo/dev/paseo-reference/packages/app/src/i18n/resources/en.ts` (cite path:line).
  - Approved exceptions are listed in your ticket.
- **No new dependencies.**
- **No behavior changes beyond the ticket.**
- **No `#if os(...)`** beyond the existing `#if canImport(UIKit)` file wrappers.
- **Swift 6 strict concurrency:**
  - closures that Apple frameworks may call off main are `@Sendable` or formed in `nonisolated` code;
  - no `private` declaration used from another file;
  - memberwise inits follow declaration order.
- **Keep `body` small:**
  - no modifier chain over ~10;
  - split into subviews (separate `View` structs, not computed properties, wherever the ticket asks
    for narrow observation);
  - give closures in ternaries an explicit type.
- **No force unwraps or `fatalError`.**
- **Safety:**
  - never touch the user's real agents, daemon config or saved hosts;
  - no `set_daemon_config_request` or `get_pairing_offer` against the real daemon;
  - no secrets, hostnames or screenshots in the repo;
  - the sandbox is `/tmp/fixture-sandbox`.

## Compiling

- **PaseoUI can't compile on Linux.** Run `swiftc -parse <file>` on every touched UI file. That
  catches syntax only, so be exact with Apple API signatures, and list every Apple API you were not
  100 % sure of (name, labels, availability) in your final message.
- **The lead compiles your branch on a Mac** (iOS 26 SDK) and sends the real compiler errors back to you.
  Fix them in place on the same branch.
- **PaseoCore:** `cd Packages/PaseoCore && swift build --build-tests && swift test` must be green.
  New logic gets new test files; never edit or weaken existing tests.

## Done

1. Commit on your branch with the ticket name in the message (for example `R1: folder moves and dead code`).
   Several commits are fine. Do not push, merge or rebase.
2. No background tasks, no subagents; don't end your turn while waiting on anything.
3. **Final message:**
   - what you did, per ticket section;
   - test output summary (PaseoCore, if touched);
   - `swiftc -parse` result;
   - **Unsure:** Apple APIs and ambiguous spec points;
   - anything left undone, and why.
