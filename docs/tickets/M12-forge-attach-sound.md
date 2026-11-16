# M12: attach an issue or PR, sound cues, PARITY sweep

Branch `m12-forge-attach`. Read `AGENTS.md`, `ARCHITECTURE.md`, `docs/tickets/PHASE3-BACKEND.md`,
shared UI rules at the top of `docs/tickets/M3-workspace-panel.md`. Cite path:line for wire claims.

1. **Add issue or PR** (composer): the attachment menu gains "Add issue or PR" (GitLab wording
   "Add issue or MR" when the forge is GitLab), gated like upstream. It opens a searchable picker
   (`forge.search.request`, legacy `github_search_request` fallback per its COMPAT gate; doc 02
   §6.5, upstream `components/attachments-picker*`, `git/use-forge-search-query.ts`), debounced,
   with kind filter (issues / PRs), auth/CLI-missing states reusing M3j's gh callout wording.
   Picking one adds a pill to the tray ("Remove {{kind}} {{number}}"), sent as the same attachment
   type upstream sends (check `AgentAttachment` in PaseoProtocol; add the case if missing, with
   tests from scrubbed fixtures). Store work goes in PaseoStore with FakeDaemonClient tests.
2. **Sound cues** (DSH `sound-cues`, folder path in PARITY): an optional short sound when an
   agent finishes or is blocked while the app is in the foreground and you're not looking at that
   agent, levels Off / Soft / Clear (DSH wording) in Settings → General → Notifications. Feed it
   from M10's `AttentionCenter` intents (don't duplicate the attention logic). Use a system sound
   or a tiny synthesized tone (AVFoundation), no bundled audio; respect the silent switch
   (ambient audio session) and don't interrupt other audio.
3. **PARITY sweep**: walk every `missing` row and fix the stale ones you can prove from code (at
   least Help-and-support footer/home links vs M4g's Help page, App diagnostic report vs M4e,
   DSH `message-actions` vs M7h). Recount the table.

Live checks only against the sandbox (`/tmp/fixture-sandbox`, agent
`1c51ee58-765c-4f8d-bf27-7009338b361e`): forge search is read-only and fine. Never touch other
agents. Done = PaseoCore `rm -rf .build && swift build --build-tests && swift test` green,
`swiftc -parse` on every touched UI/App file, `Tools/api-audit` no new real findings. No background
tasks or subagents; don't end your turn while waiting. Commit "M12: forge attach, sound cues",
don't push. Final message: what changed, wire citations, test totals, unsure-compile spots.
