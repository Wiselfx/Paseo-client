# M3: the workspace panel (four parallel tickets)

The user's direction: keep the main chat window clean. Everything about the *workspace*
(its agents, files, changes, terminals) lives in a panel that slides in from the **right edge**,
the mirror of the left sidebar drawer. The left drawer is navigation (projects → workspaces);
the right panel is "inside this workspace".

Shared rules for all four tickets:
- Read `AGENTS.md`, `ARCHITECTURE.md`, `Chat/ClaudeStyle.swift` (palette, `ClaudeTypography`
  sans/serif/mono roles, `ClaudeMotion`, `ClaudeDivider`, `ClaudeCard`, `ClaudeChevron`), and
  `Chat/PaseoSidebar.swift` (row styles, context menus, sheet chrome) so new views look like they
  were always part of the app: Anthropic Sans for UI text, Mono for code/paths/diffs, Serif for
  titles, `ClaudePalette` tokens only (no raw colors except where a spec gives hex), 0.5 pt
  dividers, Reduce Motion respected, selection haptics via `Paseo/DesignSystem/Haptics.swift`.
- Pages are given; their constructors are fixed contracts (stubs exist in
  `Packages/PaseoUI/Sources/PaseoUI/Workspace/`). Only replace your own file's body and add new
  files of your own; don't edit other tickets' files. Don't touch PaseoCore except reading
  (if a store is missing something, say so).
- No background tasks, no subagents, and don't end your turn while waiting on anything.
- SwiftUI can't compile here: `swiftc -parse` every touched file, `rg` any renamed/deleted
  symbol, and list every unsure-compile spot (file:line). Avoid exotic APIs; prefer patterns that
  already exist in this package. Paseo's own app is the feature reference
  (`/home/paseo/dev/paseo-reference/packages/app/src`), docs `docs/research/01`, `02`, `03`.
- Commit on your branch as "M3x: …", don't push. Final message: what you built, what's missing
  vs Paseo's app, unsure-compile spots.

---

## M3a: the panel and a clean chat header (branch `m3a-panel`)

1. `Workspace/WorkspacePanel.swift` (new): a right-side drawer over the chat (`PaseoShellView`).
   Opening: drag from the right ~24 pt edge zone (only when the panel and the left drawer are
   closed) tracks the finger 1:1; release settles with a spring by position + velocity; also a
   single glass circle button at the chat header's trailing edge (`sidebar.right` symbol) opens
   it. Closing: drag back, tap the dimmed chat. Reuse the left drawer's gesture/spring/dim/corner
   code (generalize it into a shared helper rather than copy it; the left drawer must behave the
   same afterwards). Width ~88% of the screen. Haptic tick on settle.
2. Panel content: header with the workspace title (serif 20) and `branch · diff stat` meta line;
   a segmented page switcher **Agents · Files · Changes · Terminal** (custom, ClaudeUI chip
   style, selection haptic on change, last page remembered per workspace); pages:
   - **Agents** (yours): the workspace's agents (title, provider · model, status dot, relative
     last activity), newest first, current one marked; tap switches the chat to it and closes
     the panel; a "New agent" row at the top (existing new-agent flow); long press: Rename,
     Copy agent ID, Archive (with confirmation).
   - Files → `WorkspaceFilesView(checkout:)`, Changes → `WorkspaceChangesView(session:checkout:)`,
     Terminal → `WorkspaceTerminalsView(session:workspace:)`, using `session.checkout(for:)`.
3. **Clean header**: remove the agent tab chips row from `ClaudeChatView`'s header. The header is:
   leading sidebar button, centered agent title (one line) with a small secondary
   `workspace · branch` line, trailing panel button. Nothing else.
4. Sidebar bottom bar: the avatar circle and the white "New workspace" pill are too close. Make it
   avatar at the leading edge, pill at the trailing edge (`Spacer` between), both vertically
   centered, 20 pt horizontal margins, like Claude iOS.

## M3b: Files (branch `m3b-files`, file `Workspace/WorkspaceFilesView.swift` + your own new files)

A file browser on `checkout.files` (`WorkspaceFiles`: `list(_:)`, `read(_:maxBytes:)`, `entries`,
`file`, `phase`, `error`). Navigation stack inside the page: directory rows (folder/file SF
symbols, name in sans 15, size/modified secondary if available), breadcrumbs or a back row,
pull to refresh. Tapping a file opens a viewer: text with syntax highlighting reusing
`ClaudeCodeHighlighter` (see how `ClaudeMarkdownView` highlights code blocks) in Mono, line
numbers, horizontal scroll, copy; images rendered if the read returns image bytes; binary/too
large shows a calm message. Live file updates if T11 added a subscription on the store (check
`GitExtras.swift` / `WorkspaceFiles`), otherwise refresh on appear. Long press a row: Copy path,
Copy relative path, "Mention in chat" (inserts `@relative/path` into the current conversation
draft only if you can reach it through the existing environment; otherwise skip and say so).

## M3c: Changes (branch `m3c-changes`, file `Workspace/WorkspaceChangesView.swift` + your own new files)

The Changes page on `CheckoutStore` (+ `session.gitExtras` / `GitExtras.swift` for the modern diff
pipeline, discard, branches, PR status). Top: branch, ahead/behind, PR status chip if any.
A compare switch (Uncommitted / vs base) where supported. File list with status letters/colors
(added/modified/deleted/renamed) and +/− counts; tap opens a unified diff view: Mono 12–13,
hunk headers, line numbers, added/removed backgrounds as subtle adaptive tints (green/red at low
opacity, readable in dark mode), horizontal scroll, long lines not wrapped. Actions: Commit
(message sheet, `commit(message:)`), Push, Discard file (confirmation, destructive), only when
supported. Empty state: "No changes" calm and centered.

## M3d: Terminal (branch `m3d-terminal`, file `Workspace/WorkspaceTerminalsView.swift` + your own new files)

Terminals on `session.terminals` (`TerminalsStore`, see `docs/research/03` and
`docs/tickets/T8-terminals.md`). Add the SwiftTerm package to `Packages/PaseoUI/Package.swift`
(`https://github.com/migueldeicaza/SwiftTerm`, a current release; product `SwiftTerm`) and render a
terminal with SwiftTerm's iOS `TerminalView` in a `UIViewRepresentable`, fed by the store's raw
bytes and sending keystrokes/resizes back through the store. Mono font (Anthropic Mono, via
`ClaudeTypography`/UIFont), colors from the palette (dark background even in light mode is fine).
Page: terminal picker (chips for the workspace's terminals + "New"), workspace scripts list
(start/stop, status) from `scripts(in:)`. Read SwiftTerm's source/API from the package checkout
(`swift package resolve` in a temp dir is fine) rather than guessing method names; quote the
exact API you used in your final message.
