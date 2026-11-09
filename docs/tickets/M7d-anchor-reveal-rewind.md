# M7d: answer anchoring, text reveal, rewind

Branch `m7d-anchor-reveal`. Store + UI. Store side per `docs/tickets/PHASE2-CONVENTIONS.md` (new
files, fixtures, sandbox only). UI: the **transcript section** of `Chat/ClaudeChatView.swift`,
`Chat/ClaudeChatComponents.swift`, `Chat/ClaudeFileCalls.swift`, new files (not the composer: M8c
owns it). Update PARITY rows in the same commit. DSH source:
`/home/paseo/dev/dsh-claude-style-reference/packages/client/src/features/{chat-anchor,chat-reveal,message-actions}/`;
DSH live at :3050 is the style truth.

1. **Chat-anchor**: when you send, your message scrolls to the top of the viewport and the answer
   grows below it (DSH chat-anchor), instead of the tail-follow pushing it off; follow (M7b) takes
   over once the answer passes the bottom. Reduce Motion: no animated scroll.
2. **Chat-reveal**: newly arriving assistant prose fades in per chunk (DSH chat-reveal timing;
   measure from source), never re-animating text already shown and never on history load. Keep
   it cheap (no per-character views on long messages; a trailing-chunk opacity ramp is fine).
3. **Rewind** (`docs/research/04-protocol-agents-permissions-settings.md` §4.8; gate
   `features.rewind` + snapshot `supportsRewind*` flags): store method `rewind(toMessageId:scope:)`
   (conversation / files / both), tests. UI: long-press your bubble → "Rewind to here" (with the
   scope choices the provider supports and the can't-undo warning copy from upstream
   `docs/research/01-app-features.md:58`). Not offered until the message's provider echo landed.
4. Cleanup from M7c: remove now-dead `ClaudeRollingNumber` (if unreferenced) and `ClaudeStepRow`'s
   unreachable `.file` branch; make M7 find scroll to a merged file row (give the merged row the
   ids of all its calls' seqEnds or map seq → row id).

Commit "M7d: anchor, reveal, rewind", don't push. Final message: what changed, test counts,
unsure-compile spots.
