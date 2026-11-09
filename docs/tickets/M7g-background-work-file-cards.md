# M7g: background work and file mention cards

Branch `m7g-background-work`. Backend follows `docs/tickets/PHASE2-CONVENTIONS.md` (sandbox only:
start background work only in the sandbox agent or throwaway agents you create in
`/tmp/fixture-sandbox`; scrubbed fixtures, tolerant decoding, observable errors, tests). UI rules:
top of `docs/tickets/M3-workspace-panel.md`. Update `docs/PARITY.md` rows in the same commit. You
may edit `Conversation/ChatTranscript.swift`, `ChatTurns.swift`, `ChatWorkGroup.swift`,
`ChatHeader.swift`, `ChatSheets.swift`, `Conversation/ClaudeChatView.swift` (wiring), new files,
new PaseoProtocol/PaseoStore files, minimal wideners. Not the composer files.

1. **Background work** (the gap you found): wire types + store for `agent.background_work.list` /
   `.stop` / `.update` (doc 04 ~line 1033; gates `features.agentBackgroundWork(Stop)`; cite
   upstream `messages.ts` lines). UI: a quiet row near the transcript end while anything runs
   ("2 background tasks"), tap → sheet with each item (kind, command/label, started, status) and
   **Stop** (confirmation for running shells) when the stop gate is on.
2. **File mention cards**: `@relative/path` tokens in user bubbles and file paths in assistant
   prose that resolve to workspace files render as tappable (dotted underline like DSH chat-files);
   tap opens the workspace file viewer (the panel's viewer, same path M3e/M7c use). No extra
   lookups per render: resolve lazily on tap and show the viewer's own not-found state.

Full PaseoCore rebuild+tests; swiftc -parse every touched UI file. Commit "M7g: background work
and file cards", don't push. Final message: what changed, test counts, store gaps, unsure-compile spots.
