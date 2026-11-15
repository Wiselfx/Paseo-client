# Q1: files and git (open with, open location, stash and switch, forge search)

Read `AGENTS.md`, then `docs/tickets/_P-common.md` (same rules: upstream and daemon roads first, no extra work, no existing tests edited,
one commit per item, never push), then this file. Do the items in order. For each, first read the PARITY row
(`docs/PARITY.md`, search the feature name) and the upstream code it cites, then decide: build it as upstream does, or skip it and say why.

1. **Open with… / contended file types** (PARITY rows "Open with…" and "Files settings — contended file-type selector"): upstream's picker for
   file types that more than one panel can show, per-extension default, "Ask every time" / "Always use". Port upstream's behaviour and `en.ts` copy
   verbatim into the file viewer and the Files settings page.
2. **Open location** (PARITY rows "Open location settings" / "Open location section"): where files, changes, PR and service URLs open. On iPhone
   keep only the destinations that exist on a phone (upstream's own mobile behaviour decides); do not invent destinations.
3. **Stash & Switch** (PARITY row "Branch switch on a dirty tree"): only if upstream has a stash request in `packages/protocol/src/messages.ts`.
   If not, skip and say so.
4. **Forge search** (PARITY row "Forge search"): the store exists (`PaseoStore`); add the screen where upstream offers it (attachment pickers and
   branch starts). Reuse the existing store; no new RPC.

Owns: `Packages/PaseoUI/Sources/PaseoUI/Workspace/*` (file viewer, files list, git/branch sheets), `Packages/PaseoUI/Sources/PaseoUI/Settings/*` for the
Files settings only, the attachment picker UI, and the Core stores for files/git/forge only when a wire type is genuinely missing. Do NOT touch
`HostSession.swift`, `AgentControlStore.swift`, `TerminalsStore.swift`, `HostSettingsStore.swift`, `OverviewPage.swift`, `ChatHeader.swift`,
`ChatSubagents.swift` (another worker owns them).
Commits: `Q1.1 open with`, `Q1.2 open location`, `Q1.3 stash and switch`, `Q1.4 forge search`.

Final message: per item done / skipped (why), files, upstream citations, build and test results, doubts.
