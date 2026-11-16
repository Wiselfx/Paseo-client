# M2: The Claude-style chat on live data

The app's UI is now `Packages/PaseoUI` (ClaudeUI, after M1). The data layer is finished:
`HostSession`, `ConversationStore`, `AgentControlStore`, `WorkspaceDirectory`, `CheckoutStore`,
`TerminalsStore` in `Packages/PaseoCore/Sources/PaseoStore`. This ticket makes ClaudeUI's chat
the app, running on those stores, with the DSH Claude-style turn UX. The user's bar: it must feel
like Claude for iOS plus the DSH plugin: smooth, coherent, polished. Not generic, not ugly.

Specs (read all three before coding):
- `docs/research/07-claudeui-adoption-map.md`: §5 is the chat seam (exactly where and how to swap
  in `Turn`s), §3 rows 1–18 the decisions, §6.1 the chat gaps.
- `docs/research/06-dsh-ux-spec.md`: turn layout, sizes, timings, status line wording and
  timing, composer details. **Reuse its values and wording. Do not invent quips or new styles.**
- `docs/research/04-protocol-agents-permissions-settings.md` only if a store API is unclear.

Rules:
- Views read store objects (`@Observable`) directly and call their async methods. They never
  import or touch PaseoKit/PaseoProtocol requests. Keep ClaudeUI's `SessionState` only for
  UI-local state (sheet presentation, dictation UI, selection), not for data the stores own.
- Use ClaudeUI's palette, typography (`ClaudePalette`, Newsreader serif), sheet chrome
  (`SheetHeader`, `RowGroup`, `SheetRow`) and motion. New views must look like they were always
  part of ClaudeUI.
- One haptics helper (`Paseo/DesignSystem/Haptics.swift`): selection ticks on disclosure/picker
  changes, send impact, a soft settle when a turn completes. Never a failure haptic on success.
- Reduce Motion respected everywhere you animate.

## Part A: conversation (commit "M2a: conversation")

1. ClaudeSessionView's transcript renders `ConversationStore.turns` (map §5.4): user bubble
   (ClaudeUI's), then the turn per DSH §1: header ("Completed in Xs" when done; the live
   status line while running), the "N thoughts, M tool calls" work groups with rolling digits,
   the scrolling process card (`min(400pt, 50% of height)`), 36pt rows with trailing chevrons,
   each thought/tool call expandable to its detail, the height-roll + fade timings. Assistant prose
   with `ClaudeMarkdownView`. Port the tool detail views from `Paseo/ConversationFeature`
   (shell/read/edit diff/search/fetch…) and restyle them; reuse `ToolCallPresentation` and
   `WorkGroup.summary` from PaseoStore.
2. Live status line (DSH §2): its exact wording and per-state logic (Thinking…, Reading {file},
   Running tools…, …), 1 s wording lock, the highlight sweep, loader dots, "No response yet"
   after 10 s of silence. Drive it from store state (active turn, newest row kind).
3. Composer: ClaudeUI's composer bound to `ConversationStore.draft`/`send`/`cancel`, Stop while
   running, steer when sending mid-turn. Load older history when scrolled to the top.
4. Pickers: ClaudeUI's model and effort sheets list real providers/models/thinking options and
   modes from `AgentControlStore`, and switch the open agent's model/thinking/mode.
5. Permission cards: pending permission requests render inline in the transcript as ClaudeUI-style
   cards (what the agent wants, the daemon's offered actions), answering through the store; they
   animate away when resolved.

## Part B: the shell (commit "M2b: shell")

1. ClaudeUI's sidebar shows `WorkspaceDirectory` groups: project → workspaces (name, branch,
   status dot) → that workspace's agents. Selecting an agent opens its conversation.
2. **Tabs inside a workspace**: the conversation header shows the workspace's agents as tabs
   (swipe/scroll chips in ClaudeUI style) plus "New agent", which creates an agent in the same
   workspace via `AgentControlStore` (provider/model picker, first prompt from the composer).
   Agents are not spread across new workspaces.
3. Attention: sidebar rows show needs-attention dots; opening clears attention.
4. Connection: the connect screen restyled with ClaudeUI's sheet chrome; a reconnecting banner.
5. Delete the old generic screens in `Paseo/` (AgentsFeature, ConversationFeature, HostsFeature,
   duplicated DesignSystem pieces) once nothing uses them. Keep Haptics.
6. `App/Sources` becomes a thin composition root around the ClaudeUI shell.

## Verification (no Xcode here)

- `rg` every type you delete; `swiftc -parse` every Swift file in `Packages/PaseoUI` and `App`.
- PaseoCore must still pass `swift test`. If you truly need a store change, keep it minimal,
  add a test, and call it out.
- If you add SwiftUI previews, give them fixture data from `PaseoFixtures`-like JSON, not live.
- Final message: what each part delivered, every place you're less than certain compiles
  (file:line), and what the user should look at first in the simulator.
