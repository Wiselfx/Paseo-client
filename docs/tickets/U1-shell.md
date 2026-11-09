# U1: Shell, drawers, sidebar (DeepSeek)

Branch `u1-shell`. Read `_U-common.md` first. Spec: UX-SPEC §0.1, §0.3, §0.4, §1 (all), §2. Audit: A1–A5, A7, A8.

## Work

1. **Shell** (`Chat/PaseoShellView.swift`, `Chat/EdgeDrawer.swift`):
   - Lay out the shell full-bleed, including safe areas (§1.1). The device screenshot shows white bands above and below the app: find out where they come from (`App/Sources/RootView.swift` and the app scene may be involved; you may edit those for this) and remove them.
   - Constant display-radius corners, the hairline edge, the dim inside the clip, the sidebar canvas equal to `background`.
   - One critically damped settle (§0.4), no double `withAnimation`. Keep the panel mounted (no `if` insertion mid-animation).
   - The right panel becomes a full-width push with parallax (§1.3), and its dismiss gestures.
2. **Workspace panel header** (`Workspace/WorkspacePanel.swift`, header only): a `chevron.left` back button that closes the panel, the workspace name, then the tabs. Leave the tab contents alone.
3. **Sidebar** (`Sidebar/PaseoSidebar.swift`, `Sidebar/SidebarDirectory.swift`, `Sidebar/SidebarProjectGroup.swift`):
   - **Footer:** avatar leading, "New session" inverted pill trailing (§2.5); remove the host chip and the host badge.
   - "Add project" moves into the navigation list, right after Import session.
   - The "New session" pill and each workspace row's `+` call a new closure, `onNewSession(workspaceId: String?)`, which the shell provides. For now the shell routes it to the existing `openNewAgent`. U2 replaces that with the draft. Pass the current workspace (the selected agent's workspace) for the pill, or nil when there is none.
   - The old "New workspace" pill action (`ClaudeNewWorkspaceSheet`) is no longer in the footer. Keep it reachable as a navigation row "New workspace" (`en.ts:1269`) under Add project, gated as before.
4. **Settings → Appearance:** delete the "Sidebar badge" section and its per-host appearance, if nothing else reads it after step 3 (`Chat/PaseoSettingsView.swift`, `Settings/HostSwitchContext.swift`). Keep the stored data harmless: there's no migration, and unknown keys are ignored.

## Acceptance

Describe in your final message, frame by frame, what the user sees when they:

- edge-swipe the sidebar open halfway and let go;
- open the panel from the header button;
- swipe the panel away from the middle of the Files list;
- swipe it away from inside the diff view.
