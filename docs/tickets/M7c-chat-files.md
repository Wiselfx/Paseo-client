# M7c: file-call rows and tool summaries in the turn

Branch `m7c-chat-files`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
matching Conversation & turns rows in `docs/PARITY.md` in the same commit. You may edit the
**transcript section** of `Chat/ClaudeChatView.swift`, `Chat/ClaudeToolDetail.swift`,
`Chat/ClaudeTurnGlyphs.swift`, `Chat/ClaudeStatusLine.swift` and new files (not the composer:
M6a owns it).

Spec: `docs/research/08-dsh-live-observation.md:133-160` (measured DSH chat-files), doc 06
(`chat-files/`), DSH source under `dsh-claude-style-reference/packages/client/src/features/chat-files/`;
upstream summary copy `docs/research/01-app-features.md:54`. The DSH harness at :3050 is the style
truth (token per STATUS/memory; no screenshots unless stuck).

1. **File-call rows**: Read/Edit/Write tool calls render as DSH file rows: verb · filename (name in
   Mono with the dotted underline link style used elsewhere), `+N −M` for edits in success/failure
   ink at low emphasis, consecutive calls on the same file merged into one row ("Edited · Foo.swift
   ×3"). Tapping the filename opens the file in the workspace panel's file viewer (reuse the
   existing open-file path if the shell exposes one; otherwise the existing tool detail sheet, and
   say what's missing).
2. **Summary line**: the collapsed work-group summary reads like the reference ("Edited 3 files,
   ran 2 commands, read 4 files" style; keep DSH's wording where it has one) instead of raw counts,
   singular/plural correct.
3. Keep row heights from doc 08 (36 pt file rows) and the existing expand/collapse behaviour.

Commit "M7c: file-call rows and tool summaries", don't push. Final message: what changed,
unsure-compile spots.
