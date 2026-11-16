# R7: workspace panel, Files, Changes, diffs, terminals

Branch: `r7-workspace`, from `foundation` after R4 is merged. Read `docs/tickets/_R-common.md`,
UX-SPEC §1.3 and §6, and PLAN §RD. Evidence: audit B N3, N4, N9, N10 and E; audit C #4, #11 and §6.

**Owns** `Workspace/` (except the drawer plumbing in `WorkspacePanel.swift` that R5 removes; don't
touch `dismissDrag`, `withPanelDismiss` or `PanelVisibilityTracker`. If R5 merged first, they're
already gone), plus `Conversation/Turn/ClaudeToolDetail.swift` and
`Conversation/Turn/ClaudeFileCalls.swift` (the diff pieces only).

## 1. Diffs (the worst cost in the app)

### `WorkspaceChangesDiffView`

- `model` and `sideModel` are computed properties that every row re-reads (`lineRow` reads
  `model.totalWidth`), which makes rendering quadratic. Replace them with a `@State var render: DiffRender?`
  built by a `.task(id: DiffKey(file.path, file.revision-or-hash, hideWhitespace, wrap))`.
  - Build off main (`Task.detached`) when the file has more than 500 lines; otherwise build inline.
  - Pass rows their `totalWidth` and line data as values.
  - Group the draft anchors once per render into `[lineKey: [Draft]]`.
- **The list:** `ScrollView(.vertical) { LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) }`,
  one `Section` per hunk with its header pinned.
  - Horizontal scroll (no wrap): one horizontal `ScrollView` wraps the `LazyVStack` and its width is
    `totalWidth`. Or, if that kills laziness, each row is fixed-width and clipped, and a single
    horizontal offset is shared. **Pick the variant that keeps the `LazyVStack` inside the vertical
    `ScrollView` lazy** and explain the choice.
- **Line rows:** an `HStack` of the gutter numbers (`.codeCaption`, `tertiaryInk`, fixed width from
  the max line number) and the text (`.code`). The background is `Palette.diffAdded` /
  `diffRemoved` / clear.
  - No `Button`. Tapping a row selects it (for review comments) via `.onTapGesture`.
  - No `.textSelection` on the list; "Copy line" goes in the row's context menu.
- **Long hunks:** hunks over 400 lines start collapsed to their first 40 lines, plus a row "Show N
  more lines". That wording is approved.
- **Side-by-side:** remove the option and its code paths. It can never show on a portrait iPhone
  (audit C Mac §). Remove the menu item that toggles it too.
- **`ClaudeDiffView`** (in `ClaudeToolDetail.swift`):
  - parse once into `@State` via `.task(id: diff hash)`;
  - render rows in a `LazyVStack` inside its 300 pt-capped `ScrollView`.
- **`ClaudeFileCalls.diffStat`:** compute once per call, cached in a static `NSCache<NSString, Box>`
  keyed by the diff string's hash and length. It is drawn by R4's `DiffStat`.
- `WorkspaceCommitDiffView` and `WorkspaceChangesView` use `DiffStat` and `Palette.diff*` too.

## 2. File viewer (`WorkspaceFileViewer`)

- Decode and highlight **off main**, into a cached `FileRenderModel` (`@State`, built by
  `.task(id: path + revision)`):
  - the base64 decode;
  - `UIImage` creation, downscaled to the screen with the `CGImageSource` thumbnail API;
  - the line split;
  - the highlighted `AttributedString`.
- Nothing decodes in `body`. `canCopy` and the copy button use the model.
- **Text files:**
  - ≤ 500 lines: today's single selectable `Text` (from the model).
  - more than 500 lines: a `LazyVStack` of line rows (gutter plus text). "Copy" in the toolbar
    menu copies the whole file.
- **Editing:**
  - while editing with changes, back / close asks `confirmationDialog("Discard changes?")` with
    "Discard changes" / "Keep editing" (approved);
  - the viewer's sheet sets `interactiveDismissDisabled(isDirty)`.
- **Tap targets:** the toolbar buttons (back, Cancel, Edit, Mention) get 44 pt hit areas.

## 3. Files page becomes a real navigation stack

- `WorkspaceFilesView` uses a `NavigationStack(path:)` of folder paths, with
  `navigationDestination(for: FilePathItem.self)`. Folder taps push; system back and
  swipe-back work.
- **Panel handoff:** set `shellDrawer.panelHandlesBack = !path.isEmpty`
  (`@Environment(\.shellDrawer)`, optional), so the shell's panel-close pan yields to the stack's
  swipe-back in subfolders.
- **States:**
  - loading: `LoadingState`;
  - empty: `EmptyState(systemImage: "folder", title: <existing empty text>)`;
  - error: `InlineBanner(.failure, …, action: ("Try again", reload))`.
- **Formatters:** `PaseoFormat.relative` / `dateTime` (R4) replace the per-row formatters
  (`WorkspaceFileFormat.swift:47`).

## 4. Changes page

- The file list and the commits list become `LazyVStack`s.
- The overlay menu that builds one button per file goes; each row gets a context menu with the same
  actions.
- **Pull-to-refresh** is already there; delete any refresh toolbar button.
- **Errors:** both `errorBanner`s (here and in Terminals) are replaced by `InlineBanner`.
- **Copy:**
  - "Discard Changes" becomes "Discard changes" (sentence case, matching `:750`);
  - the merge button's raw "Merge (squash)" uses the upstream label (find it in `en.ts`; cite it).
- **Commit and Create PR sheets:** already scaffolded in R4. Verify `sheetDirty` is wired.

## 5. Panel chrome (`WorkspacePanel`)

- **Header:** `ShellHeader(leading: .back(close), title: workspace name in .title, trailing: page
  actions menu)`.
  - The trailing menu holds the page's secondary actions (Import session, Setup…, Copy path).
    Collect them from the scattered page toolbars.
- **Tabs:** a system `Picker(selection:) { … }.pickerStyle(.segmented)` with the four pages and the
  UX-SPEC §0.3 symbols as `Label`s (title + image). The selected-segment tint follows the system.
  Height is no longer fixed (Dynamic Type).
- **Agents page:**
  - rows use `ListRow`;
  - the context menu follows PLAN §RH order: Open, Rename…, Copy agent ID, divider,
    Archive (destructive);
  - Archive follows R6's rule: confirm only while running, otherwise archive with an Undo toast
    "Agent archived";
  - the "New agent" row is renamed **"New session"** (audit C #5);
  - remove the row's own `Haptics.selection()` when the tap also closes the panel; the shell plays
    the haptic.
- **Terminals:**
  - `ListRow`/chip styling from R4;
  - `EmptyState` and `LoadingState`;
  - toasts through `ToastCenter`;
  - the chips' height becomes `minHeight: 44`;
  - the key bar uses `Haptics.light()` (R2 did the routing; verify).
- **PR pane:**
  - `VerdictPill` / `StatePill` → R4 `StatePill`;
  - its `RelativeDateTimeFormatter` → `PaseoFormat.relative`;
  - "Unsupported item: x" rows are hidden in release builds (`#if DEBUG` is allowed for this one
    case only).

## Proof

- `swiftc -parse`.
- Style lint 0 in `Workspace/`.
- Final message: which horizontal-scroll variant you chose and why.
- **Unsure:** pinned section headers in a `LazyVStack` inside a horizontal `ScrollView`,
  `NavigationStack(path:)` inside the panel's hosting controller, and the segmented `Picker` with
  `Label`s.
