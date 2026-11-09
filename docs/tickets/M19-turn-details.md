# M19: turn summary line, "View turn details", "Sent by"

Branch `m19-turn-details`. Read `AGENTS.md`, `ARCHITECTURE.md` and the shared UI rules at the top of
`docs/tickets/M3-workspace-panel.md`. Small, self-contained UI ticket.

Upstream: `/home/paseo/dev/paseo-reference/packages/app/src/agent-stream/turn-collapse/`
(`model.ts`, `summary-line.tsx`, `model.test.ts`) and labels in `i18n/resources/en.ts:2144-2149`.
Port wording verbatim (cite path:line); never invent copy.

## Work

1. Read upstream's turn-collapse model: what the summary line shows, when "View turn details" appears,
   what it opens, and where "Sent by {{name}}" comes from (which message field carries the sender).
2. If any logic is pure (what to summarize, sender name), put it in PaseoStore with tests in a new
   test file. If the sender is not in our timeline model, stop and say so (don't change protocol types).
3. UI: in our `Collapse turns` mode (`Conversation/ChatTurns.swift`, `showsCollapsedTurn`), add the
   "View turn details" affordance and "Sent by {{name}}" exactly where upstream's behaviour maps on
   iPhone. Reuse existing styles in that file; no new colors or fonts.
4. Update the PARITY row "Turn collapse levels" (and recount if a status changes).

Files: `Conversation/ChatTurns.swift`, maybe one PaseoStore file + one new test file, `docs/PARITY.md`.

Done = `swiftc -parse` touched UI files; PaseoCore `rm -rf .build && swift build --build-tests && swift test`
green; `Tools/api-audit` no new real findings (baseline in its README). No background tasks or
subagents; don't end your turn while waiting. Commit "M19: turn details", don't push. Final message:
what changed, wording sources, any SwiftUI API you're not 100% sure of (exact signature).
