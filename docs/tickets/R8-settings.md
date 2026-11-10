# R8: Settings, Schedules, History, Search

Branch: `r8-settings`, from `foundation` after R4 is merged. Read `docs/tickets/_R-common.md`,
UX-SPEC §5, PLAN §RE and §RI (items 3, 9, 10, 11, 18, 19, 20, 21) and audit C.

**Owns:** `Settings/`, `Schedules/`, `History/`, `Sidebar/CommandCenterView.swift`, `Onboarding/`.

## 1. Settings becomes a native navigation stack (Claude iOS look)

**Structure.** Split `Settings/PaseoSettingsView.swift` (1,913 lines) into:
- `SettingsRoot.swift`;
- one file per page: `GeneralPage`, `OverviewPage`, `HostsPage` (merged, §2), `AgentsPage`,
  `MetadataPage`, `VoicePage` (exists), `WorkspacesPage`, `ProjectsPage`, `ProvidersPage`,
  `AboutPage`, `SidebarPage` (exists), `TerminalPage` (exists), `DiagnosticsPage` (exists),
  `HelpPage`.

**Root:**
- `SheetScaffold("Settings", detents: .large)`, which provides the `NavigationStack`;
- `navigationDestination(for: SettingsRoute.self)`, where `SettingsRoute` is an enum covering every
  page plus nested routes (`.provider(id)`, `.project(id)`, `.metadataModel`, `.diagnostics`, …).

**Navigation:**
- Nested pages push onto the stack, so back returns to the parent (audit C #10). Every hand-rolled
  `page` switch, its `withAnimation` page swap and the manual back chevron go.
- Swipe-back is native.

**Look:**
- Every page is a `List` with `.listStyle(.insetGrouped)`, `.scrollContentBackground(.hidden)`,
  `.background(Palette.background)`, and rows with `.listRowBackground(Palette.panel)`.
- Rows are R4 `ListRow`s. Section headers are `Section { } header: { Text("…") }`, styled by the
  system and kept sentence case.
- Toggles use `Palette.toggleTint`.
- **Root sections and order:**
  1. **App:** General, Sidebar, Terminal.
  2. **Host:** Overview, Hosts, Pair a device, Agents, Metadata, Voice, Workspaces, Projects,
     Providers.
  3. **About:** About, Diagnostics, Help & support.
  4. The **Disconnect** button as the last section (destructive, centered).

**Symbols:** Hosts uses `network`; there is no `link` (UX-SPEC §0.3). Model uses `cpu`; Providers
becomes `square.stack.3d.up`.

**Refresh:**
- No refresh buttons anywhere.
- Pages that load host state (Overview, Agents, Metadata, Voice, Workspaces, Projects, Providers)
  use `.refreshable { await session.hostSettings.load() }` or `agentControl.refreshCatalog()` for
  Providers.
- Local pages (General, Sidebar, Terminal, About, Help) have none.
- The help text "pull to refresh on a Host page" is now true; keep it.

**Fonts and pickers:**
- Fonts come only from roles; the 90 `.system(size:)` calls go with the rewrite.
- The appearance section uses R4 `AppearancePicker`.

## 2. Hosts in one place (audit C #3, #19)

`HostsPage` merges Connections and Hosts:
- **Rows:** one per saved host: label, endpoint subtitle, and a checkmark on the connected one.
- **Tap:** switches to that host through `hostSwitch` (the existing `HostSwitchContext` API the
  Search action uses). It confirms first when agents are running, with the existing wording if
  present.
- **Swipe** (trailing): "Remove", destructive, then confirmation "Remove host?" with the existing
  danger-zone text.
- **Detail:** each row has an info button that pushes a detail page with Rename, the endpoint
  details and Remove host.
- **Last row:** "Add host" opens the existing `AddHostMethodsSheet` (through `hostSwitch` or a
  callback; if `RootView` owns it, use the existing `model.addHostRequested` route via the
  environment, and name any missing hook in your final message).
- Delete `ConnectionsPage.swift` and the Overview "Danger zone" remove. Remove lives only in Hosts.

## 3. Schedules

- `ClaudeSchedulesView` becomes `SheetScaffold("Schedules")` with `navigationDestination` for the
  detail and editor pages (no hand-rolled stack).
- **List:**
  - a `List` with `ListRow`s;
  - each row has a context menu (Pause/Resume, Run now, Edit, divider, Delete) and a trailing swipe
    (Delete), using the existing action wording;
  - `.refreshable`.
- **Polling:** replace the 5 s `Timer` poll with
  `.task { while !Task.isCancelled { await load(); try? await Task.sleep(for: .seconds(5)) } }`,
  which stops when the view goes away. Also skip the reload while `scenePhase != .active`.
- **Editor:**
  - `sheetDirty` when edited, with the discard confirmation on back;
  - a keyboard toolbar "Done" (`ToolbarItemGroup(placement: .keyboard)`) for the number pad and
    the prompt editor.
- **Copy:** "automation.manage permission" becomes a plain sentence with the same meaning. Write it
  from the upstream error wording if `en.ts` has one; otherwise propose one under "Unsure" and use
  it.
- **Formatters:** `PaseoFormat` replaces the `DateFormatter`s in `ScheduleShared.swift`.
- **Toasts:** through `ToastCenter`; delete the `showToast` closure parameters.

## 4. History (`History/ClaudeHistoryView.swift`)

- `SheetScaffold("History")`, a `List`, `.refreshable`.
- **Grouping:**
  - precompute the groups in a small `@Observable` model (`HistoryModel`), rebuilt when
    `agentLifecycle.entries` changes (`onChange` of the entries' count plus the last id);
  - dates are parsed once;
  - search is debounced at 120 ms and filters precomputed lowercase titles.
- **Formatter:** `relativeAge` uses `PaseoFormat.relative`.
- **Row actions** per PLAN §RH:
  - context menu: Open, Rename…, Copy agent ID, divider, Archive/Delete (destructive);
  - swipe trailing = Archive (destructive); leading = none;
  - the archive rule is as R6: confirm only while running, otherwise an Undo toast.
- **Opening an archived agent:** show `InlineProgress` in the row while unarchiving, then open it.
  On failure, a toast with the error.

## 5. Search (`Sidebar/CommandCenterView.swift`)

**Performance:**
- `sections` is built **once** per input change, in an `@Observable` `SearchModel`:
  - inputs are the query (debounced at 100 ms), agents, workspaces and projects;
  - a precomputed `[workspaceId: (latestActivity: Date, isRunning: Bool)]` is built once per agents
    change, so neither the comparators nor the per-row dot scan agents.

**Look:** `SheetScaffold("Search")` keeps today's field placement.

**Actions:** always include History, Schedules and Usage (they open their sheets), whatever the
Sidebar settings say (audit C #9). Use the wording of the sidebar rows.

**Toasts** come from `ToastCenter`, which shows above the sheet (audit C #8).

**Empty workspaces:** a workspace with no agents opens a draft, unchanged.

## 6. Onboarding (`ConnectView`, `WelcomeView`)

- `WelcomeView` uses `AppearancePicker`.
- `ConnectView` uses `PrimaryButtonStyle` (with `isWorking` while connecting) and `ListRow` for saved
  hosts. Its `.sensoryFeedback` is already `Haptics.failure()` (R2); verify.

## Proof

- `swiftc -parse`.
- Style lint 0 in your folders.
- Final message: the new Settings route map, and every copy change with its source.
- **Unsure:** `List` inside a `SheetScaffold` `NavigationStack`, and `.refreshable` on `insetGrouped`.
