# P-round common rules (audit fixes)

Read `AGENTS.md` first. These rules sit on top of it.

1. **Use roads that already exist.** Before writing anything, search the repo for the store, RPC, wire type, view or
   component that already does part of the job and reuse it. Add no new abstraction, setting, file or copy that the
   upstream behaviour does not need. If you can solve it by wiring something that already exists, do that.
2. **Upstream is the spec (R-7).** Find the upstream behaviour in `/home/paseo/dev/paseo-upstream-ref`
   (`docs/`, `public-docs/`, `packages/protocol|server|client|app`), match fields, ordering, capability gating and
   user-facing words from `packages/app/src/i18n/resources/en.ts` verbatim, and cite `Upstream: path:line` in code
   comments and the commit body. If upstream does not have it, do not build it: list it in your final message.
3. **The audit entry is a pointer, not the truth.** Entries are in `/home/paseo/dev/docs-audit/findings/` (LEDGER.md,
   LEDGER-EXTRA.md, REVIEW.md). Open the cited upstream and client lines yourself before changing anything. If the
   entry is wrong or already fixed, say so and change nothing for it.
4. **No new tests are required from you** (the lead writes tests later). Do NOT edit or delete any existing test. If an
   existing test must change because upstream says so, stop and list it in your final message instead.
5. **Verify what you can.** PaseoCore builds and tests on Linux:
   `. ~/.local/share/swiftly/env.sh; cd Packages/PaseoCore; swift build --build-tests; swift test`. Run it when you touch
   Core. `Packages/PaseoUI` and `App/` cannot be compiled here: run `swiftc -parse` on each edited file and re-read
   every API as a compiler would.
6. **Stay in your files.** Edit only what your ticket owns. Anything else goes in "Found, not fixed".
7. Work only in your worktree, absolute paths, commit on your branch, never push or merge. End the commit message with
   `Co-Authored-By: DeepSeek V4 Pro <noreply@deepseek.com>`.
8. **Final message:** what you changed per file, upstream citations, build/test results, anything you were unsure of.
