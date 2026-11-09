# M18: Settings split view on wide layouts

Branch `m18-settings-split`. Read `AGENTS.md`, `ARCHITECTURE.md`, the shared UI rules at the top of
`docs/tickets/M3-workspace-panel.md`, and `docs/research/01-app-features.md:268`. PARITY row:
"Settings surface — App + Host groups with split view on wide layouts". Update it and recount.

Today `PaseoSettingsView` (`Packages/PaseoUI/Sources/PaseoUI/Chat/PaseoSettingsView.swift`) is one
column: `root` list, or `detail(for: page)` pushed over it with a back chevron. Keep that exactly as
it is on iPhone.

**On wide layouts** (decide by the container's width, ≥ 700 pt, read once with `onGeometryChange`
or a container-relative check; not the size class alone, because sheets on iPad can report compact):

1. Two columns: the existing root list on the left (fixed ~320 pt, its own scroll), the selected
   page's detail on the right, separated by the existing hairline color. No new list design: reuse
   the same rows and groups; the selected row gets the existing chip/selection fill.
2. Selection defaults to General. Tapping a row swaps the right column (respect Reduce Motion like
   `open(_:)` does). Nested pushes that exist today (Metadata → Model, project pages, anything else
   that goes deeper) push inside the right column with a back chevron there; the left column stays.
3. Header: on wide, the left column shows "Settings" + the close button; the right column shows the
   page title + the page's refresh button where one exists today. No back chevron at the top level.
4. Make sure the sheet is big enough on iPad to be wide: check how Settings is presented (sidebar
   avatar) and, on iPad only, use the larger presentation sizing SwiftUI offers (e.g.
   `.presentationSizing(.page)`), keeping iPhone's sheet unchanged.
5. Any page that sets its own `.sheet`/`.confirmationDialog` keeps working in both layouts.

No behavior changes to pages themselves, no new copy (titles already exist). Keep the diff small:
extract shared pieces rather than duplicating `root`/`detail`.

Done = `swiftc -parse` every touched file, PaseoCore `rm -rf .build && swift build --build-tests &&
swift test` green, `Tools/api-audit` (see its README) no new real findings. No background tasks or
subagents; don't end your turn while waiting. Commit "M18: settings split view", don't push. Final
message: what changed, how wide/narrow is decided, unsure-compile spots.
