# Shared rules for the L-round (upstream-first fixes, 2026-11-13)

Read `AGENTS.md` first (UI rules R-1…R-7), then this file, then your ticket. This round fixes the
defects found by auditing every upstream doc against our code (`/home/paseo/dev/docs-audit/findings/`:
`FINDINGS.md`, `LEDGER.md` D-xxx, `LEDGER-EXTRA.md` X-xxx, reviewed in `REVIEW.md`). Read the ledger
entries your ticket names before you touch code.

## The intent (this is the whole point of the round)
Stick to reality. Do not make the job harder by building a path when one already exists. Do not
re-implement or invent. Upstream Paseo has spent years on the app, the daemon and the protocol; what
they built is the specification and the best available answer. Offload as much as possible to it and
learn from it. **Whenever you implement or change any function, feature, behaviour or performance
measure: first find how upstream does it, copy its behaviour, and cite it.**

## Upstream-first procedure (mandatory, every change)
1. **Find upstream's version** before writing code. The tree is `/home/paseo/dev/paseo-upstream-ref`
   (read-only): `docs/` and `public-docs/` (intent), `packages/protocol/src` (wire), `packages/server/src`
   (daemon behaviour), `packages/client/src` (SDK: how a client should call the daemon),
   `packages/app/src` (the official app: what the user sees and does).
2. **Match it**: same message, same fields, same ordering, same gating (capability/feature flag), same
   user-facing words (use `packages/app/src/i18n/resources/en.ts` verbatim), same states and defaults.
   Where Swift needs a different shape, keep the behaviour identical.
3. **If upstream does not have it, we do not build it.** Remove or leave it out; tell the lead in the final
   message ("upstream has no X: removed / not added").
4. **If upstream has a daemon-side answer, do not rebuild it client-side** (derive nothing the daemon
   already sends; ask the daemon, do not guess).
5. **Cite it.** Put `Upstream: <path>:<line>` in a comment above each behavioural change (one line, not a
   essay) and list every citation in the commit message body and final message. A change with no upstream
   citation is rejected unless the ticket says "no upstream equivalent".
6. **Reuse before writing**: grep our tree for an existing helper, type or pattern first. Use only Apple
   APIs that already appear in this repo (grep for a precedent); if you need a new Apple API, say which in
   the final message and keep it minimal. A wrong Apple API is the most common way a worker breaks the build.
7. **Keep wire-name fidelity**: Swift names may be camelCase; wire strings stay exactly upstream's.

## Hard rules
- Stay inside your ticket's "Owns" list. Anything else you notice goes in the final message under
  "Found, not fixed" with `file:line` and the exact fix. Never edit another worker's files.
- Mission-critical (from `_J-common.md`): O(1) per frame/keystroke/token; nothing jumps; main actor free
  of file/decode/parse work; tokens only (`Palette`, `Typography`, `Space`, `Radius`, `Motion`, `Haptics`,
  `Metrics`); Swift 6 strict concurrency with no warnings; no force unwraps, no `fatalError`.
- Tests are the spec: never edit, weaken or delete an existing test. Add new test files. Core changes
  need Swift Testing tests in `Packages/PaseoCore/Tests`.
- No new dependencies. No `#if DEBUG`-only code paths that change Release behaviour.
- Never send to, prompt, create or probe a `claude`-provider agent; live checks use `pi` +
  `opencode-go/beam-free` only. Never open `claude-style-lab`.
- Do not push, merge or rebase. Commit on your branch with a message starting with your ticket id
  (e.g. `L1: …`), a body listing the upstream citations, and the trailer
  `Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>`.

## Proof (what "done" means here)
- PaseoCore changes: `. ~/.local/share/swiftly/env.sh; cd Packages/PaseoCore; swift build --build-tests`
  must show no errors or warnings in your files, and `swift test` must pass; paste the summary line
  (counts) in your final message.
- PaseoUI/App changes cannot compile here. Re-read every edited function once as a compiler would:
  every symbol you use must exist (grep it), labels and optionality must match its declaration, no
  main-actor helper called from a detached task without `nonisolated`, nested types qualified.
  `swiftc -parse` each touched file. List every Apple API or initializer you were not 100 % sure of.
  The lead compiles on the Mac gate and will bounce guesses.
- `Tools/style-lint/style-lint.sh` on your files: no new hits.

## Final message
1. What you changed (file list, one line each). 2. The upstream citations (path:line → what you matched).
3. Test output summary. 4. "Upstream has no X" decisions. 5. Found, not fixed. 6. Unsure items.
If you could not finish, say exactly what is missing. Do not claim a test passed unless you ran it.
