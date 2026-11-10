# R10: sidebar

Branch: `r10-sidebar`, from `foundation` after R5 is merged. Read `docs/tickets/_R-common.md`,
UX-SPEC §2, PLAN §RH and §RI (5, 6, 8, 12, 13, 17, 18, 22) and audit C.

**Owns:** `Sidebar/`, except `CommandCenterView.swift` (R8).

## 1. Look

- Navigation rows (Search, History, Schedules, Import session, Add project) use `ListRow` styling inside
  the lazy stack, with `PressableRowStyle` and `minHeight: 44` (not a fixed 50).
- Add project uses `folder.badge.plus`; New workspace keeps `plus` (audit C: two identical
  `plus` symbols).
- **Footer:** the avatar and the "New session" pill (UX-SPEC §2). The pill uses
  `PrimaryButtonStyle`, sized to its label.
- **Usage section:** one switch shows it (Settings → General owns it). Remove the second switch's
  dependency so it appears when its own toggle is on and the host supports usage.

## 2. Behavior

- **"New session" everywhere** (audit C #5): in the workspace row menu, the project menu ("New session"
  in that project's most recent workspace) and the `+` buttons. Remove "New agent here" and
  "New agent in X".
- **Tapping a workspace with no agents** opens a draft in it (`onNewSession(workspace.id)`), like
  Search (audit C #6). Delete the toast "No agents yet…".
- **Context menus** (long-press only; no swipe in the sidebar), in PLAN §RH order:
  - **Workspace:**
    1. New session;
    2. Rename…, Pin/Unpin, Mark as unread, Labels…;
    3. Copy path;
    4. Hide;
    5. a divider, then Archive (destructive).
  - **Project:**
    1. New session;
    2. Rename…, Project settings… (new item; opens the project page that Settings → Projects
       uses);
    3. Copy path;
    4. a divider, then Remove project (destructive).
- **Remove project:** one shared action with the same confirmation and toast as the project page
  (audit C #18). Put `ProjectActions.remove(project, session:, toast:)` in `Sidebar/` and tell R8 in
  your final message. If R8 has merged, use it in `ProjectSettingsView` too.
- **Archive workspace:** keep the existing Undo-when-supported / confirm-otherwise logic. Its toast
  goes through `ToastCenter` (delete `SidebarToasts`' own toast UI; keep its archive logic, renamed
  `WorkspaceArchiveActions`).
- **Haptics:** rows whose tap also closes the drawer don't call `Haptics.selection()`; the shell
  plays it (R5).
- **Errors:** the directory error becomes
  `InlineBanner(.failure, …, action: ("Try again", { await session.workspaceDirectory.refresh() }))`.
- **Pull-to-refresh** on the sidebar's `ScrollView` (`.refreshable`) refreshes the directory and
  the agents.

## 3. Preferences

The 16 `@AppStorage` comma-joined strings stay as storage. Wrap them in one `SidebarPreferences`
(`@Observable`) that parses them once and writes back on change. Rows then read a parsed `Set`
instead of splitting strings in `body`. Storage keys and values are unchanged, so existing
preferences carry over.

## Proof

- `swiftc -parse`.
- Style lint 0 in `Sidebar/`.
- Final message: the menu orders as built.
