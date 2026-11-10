# D3: sidebar width, settings rows, turn-detail type, compact numbers

Branch `d3-layout`, from `foundation`. Read `_D-common.md` first.

**Owns:**
- `Shell/ShellContainer.swift` (sidebar geometry only)
- `Sidebar/`
- `Settings/`
- `DesignSystem/Typography.swift`
- `DesignSystem/PaseoFormat.swift`
- `DesignSystem/Components/` (ListRow, PageList, DiffStat; new files allowed)
- `Conversation/Transcript/ChatWorkGroup.swift`
- `Conversation/Turn/` (fonts only)
- `Conversation/Sheets/` (fonts and number formatting only)

## 1. The sidebar is wider than the drawer (cut-off pill, titles not truncating)

`ShellContainerController.viewDidLayoutSubviews` sets `sidebarHost.view.frame = view.bounds`, so
the sidebar lays out at full screen width while only `drawerWidth` (82 %) is revealed. That is why:
- the "New session" pill is cut off at the right;
- long workspace titles run under the card instead of ending in "…".

**Fix:** frame the sidebar host at `CGRect(x: 0, y: 0, width: drawerWidth, height: view.bounds.height)`.
Then check the sidebar's own layout at that width:
- the footer is avatar on the left and the pill on the right, both inside `Space.lg` margins;
- every row title is `lineLimit(1)` with `.truncationMode(.tail)`;
- the pinned row's diff and time line truncates its **title**, never the stats.

## 2. Settings rows: the chevron is "totally off"

`SettingsRoot.routeRow` wraps `ListRow` in a `NavigationLink` inside a `List`, and
`.panelRow()` zeroes the row insets. The system disclosure chevron then hugs the cell's edge,
outside the row's own `Space.lg` padding, misaligned with the value text and the separators.

**Fix in one place:**
- add `ListRow.Accessory.disclosure(String?)`: optional value text, then a `chevron.right` in
  `.glyph(.small, weight: .semibold)` `tertiaryInk`, spaced `Space.sm`, inside the row's padding;
- add a `PageLink<Value: Hashable>` in `PageList.swift`: the `ListRow` drawn by us, with the
  `NavigationLink(value:)` behind it at `opacity(0)` (or an equivalent that suppresses the system
  indicator), keeping the push, the highlight and VoiceOver's button trait;
- replace **every** `NavigationLink` row in `Settings/`, `History` and `Schedules` that uses
  `.panelRow()` with `PageLink`. Grep for them and list them.

**Also:**
- the "App", "Host" and "About" section headers sit flush with the row text (leading `Space.lg`),
  in `.paseo(.footnote, weight: .semibold)` `secondaryInk`, sentence case;
- the separators start at the title's leading edge (`listRowSeparatorLeading` alignment to the
  title), not under the icon.

## 3. Turn details: the big fonts

R2 mapped every small serif (`serif(13)`, `serif(14)`, `serif(15)`, `serif(16)`) to `.title`
(serif 20). On device:
- "Read 6 files and searched 2 times" and the "Search" and "Shell" row titles are huge;
- "Read" and "Edit" (another path) are small.

Restore DSH's sizes with two new roles:
- `TextRole.processTitle`: serif 14, relative to `.subheadline`. The group summary ("Read 6 files
  and searched 2 times"), at medium weight.
- `TextRole.process`: serif 13, relative to `.footnote`. Every tool row's title (Read, Edit,
  Search, Shell, Think…) at medium, and the opened reasoning text at regular.

**Every tool row uses the same title font**, whichever view draws it (`ChatWorkGroup` rows and
`ClaudeFileCalls` rows). The subtitle (path or command) stays `.footnote` sans `tertiaryInk`, and
the file-path subtitle stays mono `.codeSmall`.

The other R2 serif mappings to fix (from `git show bcabcc2` and the other R2 commits):

| File | Was | Now |
|---|---|---|
| `ClaudePermissionCard` | serif 14 | `.processTitle` |
| `ClaudeToolDetail` | serif 16 | `.paseo(.callout)` sans (it is body text in a detail view) |
| `ChatSubagents` | serif 15 / 14 | `.processTitle` |
| `ChatSubagents`, `ChatBackgroundWork` sheet titles | serif 19 | `.title` (leave) |

## 4. Compact numbers

Add `PaseoFormat.compactCount(_ value: Int) -> String`:
- `950` → `950`
- `1_000` → `1k`
- `1_250` → `1.3k`
- `12_400` → `12k`
- `133_900` → `134k`
- `1_200_000` → `1.2M`

One decimal only under 10k / 10M; no trailing `.0`. Use it for:
- **context token counts** everywhere they show (context sheet, controls sheet, usage lines):
  "12k / 200k";
- **diff stats in the sidebar** (`DiffStat` gets a `compact: Bool` parameter, true in sidebar rows):
  `+134k −18.8k` reads `+134k −19k`. Elsewhere (Changes pane, PR pane) keep exact numbers.

Add PaseoCore-free unit tests if `PaseoFormat` is testable from `PaseoUITests`; otherwise list the
cases in your final message.

## Proof

- `swiftc -parse` on every touched file.
- Final message: the `PageLink` replacement list, and a before/after table of every font change.
