# M7e: agent lifecycle in History

Branch `m7e-agent-lifecycle`. Backend parts follow `docs/tickets/PHASE2-CONVENTIONS.md`
(sandbox-only: create and delete only throwaway agents you create in `/tmp/fixture-sandbox`;
never touch any other agent; scrub fixtures). UI rules: top of `docs/tickets/M3-workspace-panel.md`.
Update the Agents & models / Search & history rows in `docs/PARITY.md` in the same commit. You may
edit `Chat/ClaudeHistoryView.swift`, new files, new PaseoProtocol/PaseoStore files plus minimal
one-line wideners. Do not edit `ClaudeChatView.swift` (M7d) or `Sidebar/*`.
Reference: `docs/research/04-protocol-agents-permissions-settings.md` §4 (4.2 delete, 4.3 archive,
and whatever upstream uses to list archived agents and to unarchive: find it in
`/home/paseo/dev/paseo-reference` and cite file:line).

1. **Archived agents** in History if the protocol can list them (fetch with an archived filter or
   whatever upstream's sessions screen does), marked with a quiet "Archived" badge, "Load more"
   paging if the wire pages. If unarchive exists, tapping an archived agent unarchives then opens
   it; if it doesn't, opening shows the read-only transcript if possible, else say so.
2. **Row actions** (swipe and context menu): Rename (store has it), Archive (confirmation when
   the agent is running: upstream copy), Delete permanently (`delete_agent_request`, destructive
   confirmation "Delete agent? This removes its history for good."), Copy agent ID.

Full PaseoCore rebuild + tests; swiftc -parse every touched UI file. Commit "M7e: agent
lifecycle", don't push. Final message: what changed, test counts, store gaps, unsure-compile spots.
