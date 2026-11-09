# M7h: message actions, fork, images in prose

Branch `m7h-message-actions`. Rules: top of `docs/tickets/M3-workspace-panel.md`; backend per
`PHASE2-CONVENTIONS.md` (sandbox only; throwaway agents you create; scrubbed fixtures; tests).
Update Conversation & turns / Rich content rows in `docs/PARITY.md` in the same commit. You may
edit `Conversation/*` except `ChatComposer.swift`, `ChatMentions.swift`, `ChatSlashCommands.swift`,
`ChatQueue.swift`, `ChatAttachments.swift`; `Chat/ClaudeMarkdownView.swift` callers; new files;
new PaseoProtocol/PaseoStore files + minimal wideners.
Reference: `docs/research/06-dsh-ux-spec.md:81-85` (folder `message-actions/`), doc 01:44 (fork),
upstream fork implementation (find it: `fork` in `packages/app/src` + protocol; cite file:line).

1. **Message actions** on your own bubbles (long-press menu, after Copy/Rewind): **Edit** (puts
   the text back in the composer via the store's draft and rewinds conversation to before that
   message on confirm, only where rewind is supported), **Rerun** (rewind to before + resend the
   same text), DSH wording. Hide what the host/provider can't do.
2. **Fork chat from here** if the protocol supports it (upstream "Fork in a new tab/workspace"):
   on iOS one action "Fork from here" → creates the forked agent and opens it. Hidden on provider
   subagents. If no wire support, say so and skip.
3. **Images in prose**: pass `imageContent` to `ClaudeMarkdownView` so `![alt](url)` renders
   (remote http(s) via the existing image loader with size caps; workspace-relative paths through
   the existing local image loader); tap opens the media viewer.

Full PaseoCore rebuild+tests if touched; swiftc -parse every touched file. Commit "M7h: message
actions", don't push. Final message: what changed, store gaps, unsure-compile spots.
