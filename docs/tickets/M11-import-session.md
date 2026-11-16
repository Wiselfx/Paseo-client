# M11: Import session, plus two follow-ups

Branch `m11-import-session`. Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/tickets/PHASE3-BACKEND.md`,
and the shared UI rules at the top of `docs/tickets/M3-workspace-panel.md`. Update the matching
`docs/PARITY.md` rows in the same commit (and fix the stale "Agent hard delete" row if M7e's
delete already covers it: check `delete_agent_request` use in PaseoUI). Cite path:line for every
wire claim. Upstream: `/home/paseo/dev/paseo-reference/packages` — protocol `messages.ts`
(`ImportAgentRequestMessageSchema` ~:1937, features `importSessionWorkspaceTarget`,
`importSessionSearch` ~:3988), app `components/import-session-sheet*.ts(x)`,
`hooks/use-import-session.tsx`, i18n `en.ts:419-435` (reuse its wording).

1. **Import session** (the main item): import an existing CLI/terminal agent session from the
   host into a Paseo agent, as upstream does.
   - PaseoProtocol: the list/search and import request/response types the upstream sheet uses,
     with the compat gates. Decoding tests from scrubbed fixtures (synthetic ids/titles, /tmp paths).
   - PaseoStore: a small store (or a slot on an existing one, your call; keep HostSession wiring
     minimal) for listing/searching sessions (debounced search when `importSessionSearch`),
     scope This workspace / Sessions on host when `importSessionWorkspaceTarget`, and import →
     the new agent id. Tests with FakeDaemonClient.
   - PaseoUI: an "Import session" sheet in the app's sheet style, reachable where upstream puts
     it on a phone (sidebar / workspace menu; also add it to the M9 command palette if that has a
     registry). On success, open the imported agent. Calm empty/loading/error states. Hidden
     when the daemon lacks the feature.
2. **Notification tap → specific terminal**: M10 routes terminal attention taps to the workspace
   panel only. Add the smallest way for the panel to open on a given terminal id and use it from
   the tap path (`AttentionTarget`, `PaseoShellView`).
3. **Stale review drafts** (M3k): drafts whose anchor is gone from the current diff are invisible;
   add a quiet "N comments no longer match this diff · Clear" line in the Send feedback bar.

Live checks only against the sandbox (`/tmp/fixture-sandbox`, agent
`1c51ee58-765c-4f8d-bf27-7009338b361e`); listing sessions is read-only and fine, but do NOT import
any real session (only import if the list offers one under /tmp/fixture-sandbox; otherwise rely
on tests). Never touch other agents. Done = PaseoCore `rm -rf .build && swift build --build-tests
&& swift test` fully green, `swiftc -parse` on every touched UI/App file, `Tools/api-audit`
(README) with no new real findings. No background tasks or subagents; don't end your turn while
waiting. Commit "M11: import session", don't push. Final message: what changed per item, wire
citations, test totals, unsure-compile spots.
