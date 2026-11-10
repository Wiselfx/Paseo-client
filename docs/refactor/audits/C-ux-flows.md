# Audit C: UX flow coherence (2026-11-10, HEAD 29d78eb)

A read-only audit run by an Explore agent. The lead confirmed #2 and #14. Paths are relative to
`Packages/PaseoUI/Sources/PaseoUI/` unless they start with `App/`.

## Top 25 by user impact

1. **The panel from a draft is empty.**
   - It says "No workspace selected" even though the header names a workspace; `selectedWorkspace` reads only the open
     conversation (`PaseoShellView.swift:345-348`, `WorkspacePanel.swift:482-494`).
   - "Mention in chat" from a draft only closes the panel (`PaseoShellView.swift:382-385`).
2. **Two connection banners appear at once** with different wording (`PaseoShellView.swift:229-269`, `ChatHeader.swift:176-201`).
3. **Switching or adding a host works only through Search → "Switch host…"** (`CommandCenterView.swift:78,391,656`).
   - Settings → Hosts can only rename and forget, and its comment points to a footer that no longer exists (`HostsPage.swift:5-7`).
   - Add host is never offered while connected (`ConnectView.swift:230`).
4. **A swipe right in Files closes the whole panel** (`WorkspacePanel.swift:293`).
   - Files has a hand-rolled folder stack with no swipe-back (`WorkspaceFilesView.swift:20-40`).
   - The code viewer scrolls sideways (`WorkspaceFileViewer.swift:733`), against §1.3.
5. **"New session" has five names:**
   - "New session" (`PaseoSidebar.swift:479`);
   - "New agent" (`WorkspacePanel.swift:536`, `ChatComposer.swift:159`, `CommandCenterView.swift:73`, `SidebarProjectGroup.swift:45`);
   - "New agent here" (`SidebarWorkspaceRow.swift:40`);
   - "New agent in X" (`SidebarProjectGroup.swift:39`).
6. **A workspace with no agents behaves differently by entry point.**
   - Tapping its sidebar row shows a toast, "No agents yet. Long-press…" (`SidebarWorkspaceRow.swift:98-100`).
   - The same workspace in Search opens a draft (`CommandCenterView.swift:683`).
7. **Text size and Pure black reset the app** through `.id(rebuildKey)` (`RootView.swift:79-85,120`): Settings closes and the
   conversation drops.
8. **A Search toast is invisible.** It goes to the sidebar's toast, which sits under the open Search sheet (`CommandCenterView.swift:695`).
9. **Features can become unreachable.**
   - Hiding History or Schedules in Settings → Sidebar removes their only entry point, because Search has no
     action for them (`PaseoSidebar.swift:344-349`, `CommandCenterView.swift:64-69`).
   - Usage needs two switches on two different pages.
10. **Settings' back button always returns to the root**, skipping parent pages (Metadata → Model,
    Help → Diagnostics) (`PaseoSettingsView.swift:172-176,1244,315`). Settings, Schedules and Files have no edge swipe-back.
11. **Unsaved edits are lost silently.**
    - Nothing uses `interactiveDismissDisabled`.
    - The schedule editor's back (`ScheduleEditorPage.swift:141`) and the file viewer's back while editing
      (`WorkspaceFileViewer.swift:267-270`) discard without asking.
    - The commit, Create PR and new-workspace sheets can all be swiped away.
12. **Archiving an agent works three different ways:**
    - the header always confirms (`ChatHeader.swift:92-106`);
    - the panel always confirms, with different text (`WorkspacePanel.swift:670-676`);
    - History confirms only while the agent is running, and its button isn't destructive (`ClaudeHistoryView.swift:97-115,431-440`).

    A workspace archive has Undo; an agent archive never does.
13. **Swipe actions exist only in History and on saved hosts.** Schedule rows have neither swipe actions nor a context menu
    (`SchedulesListPage.swift:103-134`).
14. **Three sheet header styles**, and the code puts the close button leading, against UX-SPEC §0.3:
    - `SheetHeader`;
    - a serif-19 custom header (History, Search, Schedules, Labels);
    - a nav bar with "Done" (Subagents, Background Work, terminal file, full-screen composer).
15. **Dynamic Type is mostly ignored.**
    - There are 564 fixed `.system(size:)` calls, 91 of them in Settings, and `SheetRow` is fixed too.
    - Scaled fonts sit inside fixed heights: navigation rows 50 (`PaseoSidebar.swift:374`), panel tabs 32
      (`WorkspacePanel.swift:416`), headers 48.
16. **VoiceOver problems:**
    - the hidden sidebar stays in the accessibility tree (`PaseoShellView.swift:147-161`);
    - the scrim has no button trait (`EdgeDrawer.swift:174-186`);
    - there is no escape action;
    - toasts are not announced, except the archive one.
17. **Double haptics:** the row's own `Haptics.selection()` plus the drawer settle's (`PaseoShellView.swift:374`). This happens on workspace rows,
    the New session pill and the panel agent rows. Two places bypass the Haptics switch (`ComposerQueue.swift:35-38`, `PaseoTerminalKeyBar.swift:25,185`).
18. **Remove project lives in three places** with different feedback:
    - the sidebar shows a toast;
    - Settings → Projects throws the result away (`PaseoSettingsView.swift:1460-1476`);
    - `ProjectSettingsView.swift:75-101` has its own.

    Project settings can't be opened from the sidebar's project menu.
19. **Host management is duplicated.**
    - Connections and Hosts list the same endpoints; the same action is "Remove" on one and "Forget host" on
      the other (`ConnectionsPage.swift:5-9,55`, `HostsPage.swift:56`).
    - A third "Remove host" sits in Overview's Danger zone (`PaseoSettingsView.swift:785-826,854`).
20. **Developer jargon shown to users:**
    - "Copy agent ID" ×4;
    - "automation.manage permission" (`SchedulesListPage.swift:195`) and "agentProfiles feature" (`AgentProfilesSection.swift:29`);
    - "Server ID", "Protocol version", "Terminal agent hooks";
    - "Unsupported item: \(type)" (`ClaudeToolDetail.swift:304`, `WorkspacePRPane.swift:312`);
    - "host" and "daemon" are mixed across about 64 strings.
21. **Wrong copy:**
    - "Rename agent" says the name shows in the sidebar, but the sidebar doesn't list agents (`ChatHeader.swift:90`).
    - "pull to refresh on a Host page" refers to a gesture that doesn't exist (`PaseoSettingsView.swift:1616`).
    - The placeholders differ between the draft and the chat, and address "Paseo" (`DraftChatView.swift:349`, `ChatSlashCommands.swift:34-37`).
22. **Errors with no way out:**
    - a failed transcript load has no Retry (`ChatTranscript.swift:17,83-98`);
    - a sidebar directory error shows red text with no retry and no pull-to-refresh (`SidebarDirectory.swift:205-219`).
23. **"Copy agent ID" feedback is inconsistent:** the header shows a toast, the panel and History don't (`WorkspacePanel.swift:616-619`).
24. **Subagents' "Archive finished" is mislabelled.** It is a red, confirmed "archive" that only hides rows in memory until relaunch
    (`ChatSubagents.swift:258-261`).
25. **Tapping an archived agent unarchives it silently**, with no progress and no message (`ClaudeHistoryView.swift:326-333`,
    `CommandCenterView.swift:627-633`).

## Navigation map

```
Connect / Welcome ─ pairing sheets (scan, paste, confirm, password, choose host)
Shell
├─ Sidebar (edge swipe / ≡)
│  ├─ "…" menu: sort, branch, diff, PR badge, group by, active first, Labels › Manage
│  ├─ Search (sheet): agents, workspaces, projects, files, actions
│  │   (New agent, New workspace, Import, Settings, Toggle panel, Switch host…)
│  ├─ History (sheet) · Schedules (sheet: list › detail › editor, hand-rolled)
│  ├─ Import session · Add project · New workspace (sheets)
│  ├─ Project row: + / menu (New agent, Rename, Copy path, Remove)
│  ├─ Workspace row: menu (New agent here, Rename, Copy, Pin, Labels, Unread, Hide, Archive)
│  ├─ Usage footer (hidden by default) › Usage reports
│  └─ Avatar › Settings (hand-rolled pages)
├─ Conversation: title menu (Jump, Find, Rename, Copy ID, Archive) · composer + menu · controls sheet
└─ Panel (edge / ⧉): Agents | Files (hand-rolled) | Changes (NavigationStack; PR inside) | Terminal
```

**Duplicate entry points**
- Import session has three: the sidebar, the panel's Agents tab and Search.
- Project settings has two: the setup callout and Settings → Projects.
- Add project and New workspace share the same `plus` symbol.

**A back button that isn't one:** the chat's file sheet has a back labelled "Files" that actually closes the sheet.

## Interaction gaps

- **Find bar:** Return doesn't go to the next match (`ClaudeFindBar.swift:33-43`).
- **Schedule editor:** there is no way to dismiss the keyboard.
- **Composer:** there is no ⌘↩ to send.
- **Terminal close** confirms only while a process is running.
- **Pull-to-refresh** is missing on the sidebar, History, panel Agents, Terminals and Settings.
- **The turn rail:**
  - it sits over text with no reserved margin (`ChatTranscript.swift:676-678`);
  - its 24 pt strip overlaps the panel's trailing edge zone.
- **An existing agent with no turns** shows the new-session greeting (`ChatTranscript.swift:19-23`).

## State coverage

| Screen | Loading | Empty | Error | Offline |
|---|---|---|---|---|
| Transcript | bare spinner | greeting | text, no retry | double banner |
| Sidebar | text only | text | red text, no retry | none |
| History | spinner + text | yes | Retry | none |
| Schedules | bare spinner | yes | Retry | none |
| Files | bare spinner | yes | Retry | none |
| Changes | "Loading changes…" | placeholder | dismissable banner | none |
| Terminals | spinner | yes | banner | none |
| Settings host pages | "—" | n/a | inline | none |

## Feedback

- There are six toasts with different durations and positions; a second toast can be cleared early by the first one's timer.
- Local Settings pages show "Refresh host settings".

## Copy

**Casing**
- "Discard Changes" sits next to "Discard changes…".
- "Background Work" and "Photo Library" are in Title Case.

**Labels**
- The merge button shows the raw "Merge (squash)".
- Rename is labelled three ways.

**Symbols**
- Connections uses `link`, which §0.3 forbids.
- Model and Providers share `cpu`.

**Color:** the composer cursor is orange (`ChatComposer.swift:130`), against §0.1.

## Accessibility

- **Tap targets under 44 pt:**
  - Find next/previous/close: 26–30.
  - File viewer back, Cancel, Edit and Mention: 28–29.
  - Error dismiss: 26.
  - Code-block copy and expand: 28.
  - Message copy: 28.
  - Attachment remove: 20.
  - Project "+": 30.
  - Composer buttons: 36.
  - Terminal chips and panel tabs: 32 tall.
- Icon-only buttons are labelled.
- Reduce Motion is handled well.

## Mac

- **No adaptation:** there are no idiom checks; `TARGETED_DEVICE_FAMILY "1"` and portrait only.
- **Running as "Designed for iPhone":**
  - the drawers need a click-drag from the 24 pt edge;
  - the 55 pt corners don't match the window;
  - keyboard support is only Esc and the arrows in Search and Find;
  - there is no hover.
- **Unreachable diff option:** the side-by-side diff needs a regular width, which never happens, so the option can't be reached
  (`WorkspaceChangesView.swift:896`, `WorkspaceChangesDiffView.swift:48`).
