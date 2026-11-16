# M3g: terminal and scripts extras

Branch `m3g-terminal-extras`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. You may
edit `Workspace/WorkspaceTerminalsView.swift`, `Workspace/PaseoTerminalView.swift`, new files and,
for a missing store call, new PaseoCore files with tests (keep `TerminalsStore.swift` edits
minimal; M7d/T16/M8c are in PaseoCore). Update Terminals & scripts rows in PARITY. Reference:
`docs/research/01-app-features.md:220-237`, `docs/research/03-protocol-terminals-scripts.md`.

1. **Virtual key bar** above the keyboard while a terminal is focused: Esc, Tab, Ctrl (sticky,
   one-shot), ↑ ↓ ← →, `|`, `~`, `/`, `-`; hide/show keyboard button. Light haptic per key.
2. **Tabs**: when a workspace has several terminals, a chip strip (live title, activity dot when
   output arrived since last viewed), long-press → Rename (store support if the protocol has it,
   else local label persisted per terminal id; say which) and Close (confirmation if a process is
   running).
3. **Scripts**: Restart (stop then start, one action), and for scripts with proxy URLs a "View
   service" button opening the preferred URL (Safari view) with Copy URL in its menu.
4. **Local links**: `path:line[:col]` in terminal output tappable (SwiftTerm link detection if it
   exposes it; skip and say so if not) → opens the file viewer at that file.
5. Terminal scrollback setting (Settings row is out of scope; use a sensible fixed default and
   note it).

Commit "M3g: terminal extras", don't push. Final message: what changed, store gaps,
unsure-compile spots (SwiftTerm APIs especially).
