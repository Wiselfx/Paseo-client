# M7f: transcript display, subagents track, question card

Branch `m7f-transcript`. UI rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
Conversation & turns rows in `docs/PARITY.md` in the same commit. You may edit
`Conversation/ChatTranscript.swift`, `ChatTurns.swift`, `ChatWorkGroup.swift`, `ChatHeader.swift`,
`ChatSheets.swift`, `Conversation/ClaudeChatView.swift` (wiring only), `Chat/PaseoSettingsView.swift`
(one row), and new files. Do **not** edit `ChatComposer.swift` or the other composer files.
Store: T12 `ConversationSubagents.swift`; doc 04 §11.2 and line ~1033 (background work).

1. **Chat display** setting (Settings → General → Chat: Full / Collapse tool calls / Collapse
   turns; `@AppStorage`, default Full) and turn collapse: in "Collapse turns", completed turns
   older than the last show the prompt + first ~6 lines of the reply with **Show more**; "Show
   less" to fold back; "Collapse tool calls" keeps work groups collapsed by default. Find (M7)
   must still expand whatever holds a match.
2. **Subagents track** (store-only today): a quiet pill under the header when the agent has
   provider subagents ("2 subagents", "1 working", "1 needs input", failure ink when failed);
   tap → sheet listing them with status, open one's timeline read-only, Detach and Archive /
   Archive finished where the store supports them.
3. **DSH question card**: restyle the model question card per
   `dsh-claude-style-reference/.../features/question-card/` (find the folder via PARITY) and keep
   it at the end of the conversation while pending.
4. **Background work** surface if the store/protocol exposes background shells/monitors (doc 04
   ~1033): a small row above the transcript end listing them; else list as a store gap.

swiftc -parse every touched file; PaseoCore rebuild+tests only if you touch it (sandbox only,
scrubbed fixtures). Commit "M7f: transcript display", don't push. Final message: what changed,
store gaps, unsure-compile spots.
