# App feature inventory — `packages/app`

Source: `/home/paseo/dev/paseo-reference/packages/app/src` (Expo / React Native client for desktop, mobile and web). All paths below are relative to that directory unless noted. UI labels are exactly as the app shows them (see `docs/glossary.md` in the reference repo). Every claim cites `path:line`.

## Routes (expo-router)

| Route / file | What it shows | How you get there |
| --- | --- | --- |
| `/` — `app/index.tsx:19` | Startup splash; redirects to the resolved start route (welcome / last workspace / host root / open-project / setup) | Cold start; the app decides via `resolveStartupRoute` (`navigation/host-runtime-bootstrap.ts:244`) |
| `/welcome` — `app/welcome.tsx:3` | `WelcomeScreen` — first-run welcome / onboarding entry | Startup redirect when no host is configured; also reachable from Settings → General via "Show setup again" (`screens/settings-screen.tsx` GeneralSection) |
| `/new` — `app/new.tsx:14` | `NewWorkspaceScreen` — create a workspace + draft agent/terminal | "New workspace" everywhere (sidebar header row, command center, keyboard shortcut), deep link |
| `/open-project` — `app/open-project.tsx:4` | `OpenProjectScreen` — pick a project/folder to open on a host | Sidebar "Add project" flow, deep link `#connect=`/`#offer=` (`app/_layout.tsx:687`), desktop "open-project" event (`app/_layout.tsx:733`) |
| `/sessions` — `app/sessions.tsx:4` | `SessionsScreen` — agent session history across workspaces | Sidebar "History" row |
| `/schedules` — `app/schedules.tsx:4` | `SchedulesScreen` — list/manage cron schedules | Sidebar "Schedules" row |
| `/settings` — `app/settings/index.tsx:8` | Compact: `SettingsScreen` root list; wide: redirect to `/settings/general` (`app/settings/index.tsx:12-14`) | Sidebar footer Settings icon |
| `/settings/[section]` — `app/settings/[section].tsx:37` | App-level settings section page (see Settings section below) | Settings sidebar on wide layouts; tapping a row on compact. COMPAT: `section=daemon` redirects to the local daemon's host section (`app/settings/[section].tsx:44`) |
| `/settings/hosts/[serverId]` — `app/settings/hosts/[serverId]/index.tsx:4` | Redirect to `/settings/hosts/[serverId]/connections` | Legacy/deep link |
| `/settings/hosts/[serverId]/[hostSection]` — `app/settings/hosts/[serverId]/[hostSection].tsx:7` | Host-level settings section page (host / projects / connections / pair-device / agents / metadata / voice / workspaces / providers / usage / terminals / plugins) | Settings sidebar Host group |
| `/settings/hosts/[serverId]/projects` — `app/settings/hosts/[serverId]/projects/index.tsx:7` | `ProjectsScreen` — per-host project list | Host settings → Projects |
| `/settings/hosts/[serverId]/projects/[projectId]` — `app/settings/hosts/[serverId]/projects/[projectId].tsx:7` | `ProjectSettingsScreen` — one project's settings | Projects list → Edit |
| `/settings/hosts/[serverId]/plugins/[pluginId]/[screenId]` — `app/settings/hosts/[serverId]/plugins/[pluginId]/[screenId].tsx:7` | Plugin-provided settings screen | Host settings → Plugins → a plugin's Settings |
| `/h/[serverId]` — `app/h/[serverId]/index.tsx:14` | Redirect to the host's last workspace (or host root) | Host switch |
| `/h/[serverId]/workspace/[workspaceId]` — `app/h/[serverId]/workspace/[workspaceId]/index.tsx:93` | `WorkspaceScreen` — the main workspace surface (tabs, panes, composer) | Selecting a workspace in the sidebar; deep links |
| `/h/[serverId]/agent/[agentId]` — `app/h/[serverId]/agent/[agentId].tsx:16` | Agent-ready resolver: resolves the agent's workspace and navigates to it | Deep links / notifications for an agent |
| `/h/[serverId]/sessions` — `app/h/[serverId]/sessions.tsx:4` | COMPAT redirect to `/sessions` | Legacy deep link |
| `/h/[serverId]/settings` — `app/h/[serverId]/settings.tsx:5` | COMPAT redirect to host settings (or `/settings`) | Legacy deep link |
| `/h/[serverId]/open-project` — `app/h/[serverId]/open-project.tsx:5` | COMPAT redirect to `/open-project` | Legacy deep link |
| `/h/[serverId]/plugin/[pluginId]/[surfaceId]` — `app/h/[serverId]/plugin/[pluginId]/[surfaceId].tsx:8` | Legacy redirect to plugin contribution route | Legacy deep link |
| `/h/[serverId]/plugin/[pluginId]/[contributionKind]/[contributionId]` — `app/h/[serverId]/plugin/[pluginId]/[contributionKind]/[contributionId].tsx:3` | `PluginSurfaceScreen` — plugin-provided full surface | Plugin surfaces (e.g. usage dashboards), deep links |

Modal/overlay surfaces that have no route of their own (all mounted in `app/_layout.tsx`): add-host flow (`AddHostFlowHost`, `app/_layout.tsx:532`), download toast (`app/_layout.tsx:551`), command center (`CommandCenter` at `command-center/command-center.tsx:767`, mounted `app/_layout.tsx:562`), add-project flow (`app/_layout.tsx:563`), host chooser (`app/_layout.tsx:564`), host confirmation sheet (`app/_layout.tsx:565`), provider settings host (`app/_layout.tsx:566`), workspace setup dialog (`app/_layout.tsx:567`), keyboard shortcuts dialog (`app/_layout.tsx:568`), app diagnostics (`app/_layout.tsx:569`), changelog (`app/_layout.tsx:570`), quitting overlay (`app/_layout.tsx:571`), onboarding (`OnboardingHost`, `app/_layout.tsx:576`), usage modal (no route; see Usage section).

## Feature inventory

## Agents & chat

The chat timeline renders an agent session's streamed timeline (`agent-stream/view.tsx`); agents open as workspace tabs (`app/h/[serverId]/workspace/[workspaceId]/index.tsx:93`).

User actions in an agent chat:

- **Copy turn / Copy message** — copy button at the end of a completed assistant turn (`message.actions.copyTurn`) and on each message (`message.actions.copyMessage`) (`components/message.tsx:538`, `components/message.tsx:668`, labels `i18n/resources/en.ts:331-332`).
- **Fork chat from here** — fork menu in the assistant turn footer, on completed turns next to Copy and on the in-flight turn next to the progress loader; opens a menu with **Fork in a new tab** / **Fork in a new workspace**; hidden on provider-subagent (read-only) panes (`components/message.tsx:673`, `agent-stream/turn-footer.tsx:119`, `components/assistant-fork-menu.tsx:101`, labels `i18n/resources/en.ts:333-335`; hook `hooks/use-fork-agent.ts`).
- **Worked for {{duration}}** — completed-turn footer shows the turn's duration; the in-flight turn shows an elapsed timer and loader (`components/assistant-turn-footer-label.ts:5`, label `i18n/resources/en.ts:409`).
- **Queue message** — the composer queue holds messages client-side until the turn ends (see Composer); queued rows offer **Edit queued message** and **Send queued message now** (`composer/index.tsx:391`, labels `i18n/resources/en.ts:163-164`).
- **Send and steer / Send and interrupt** — follow-ups admitted into a running turn (steer) or interrupting it (`i18n/resources/en.ts:131-132`; composer stop control `composer/index.tsx`).
- **Interrupt** — stop button / Escape interrupts the running turn (`i18n/resources/en.ts:140-141`; `composer/input/input.tsx:52` imports the Square stop glyph).
- **Permission requests in chat** — when the agent asks to run something or implement a plan, a card renders in the timeline: title is **Plan** for plan requests else the request title or **Permission Required**; buttons **Deny** and **Accept** (or **Implement** for plans); optional detail block with **Input** / **Output**; once answered the card shows **Approved plan** / **Rejected plan** / **Canceled plan** (`agent-stream/view.tsx:1485`, `agent-stream/view.tsx:1530`, labels `i18n/resources/en.ts:237-248`).
- **Question form** — question-kind permission requests render an inline form (**How would you like to proceed?**) with per-question options and a free-text "other" field (`components/question-form-card.tsx:35`, label `i18n/resources/en.ts:245`).
- **Plan card** — proposed plans render as a **Proposed plan** card with approve/reject (`components/plan-card.tsx:43-46`, labels `i18n/resources/en.ts:239-243`).
- **Subagents track** — pill above the composer summarizing subagents: **1 subagent** / **{{count}} subagents** / **{{count}} working** / **{{count}} failed** / **N needs input** / **{{count}} ready to review**; opens a panel; each row can **Detach …** / **Archive …** (tooltips **Detach subagent** / **Archive subagent**) plus **Archive finished subagents** (with retry "Retry ({{failed}}/{{total}})"); a subagent opened from the list shows as a page of the list's sheet with **Back to parent** / **Open parent** (`subagents/track.tsx:103`, labels `i18n/resources/en.ts:2036-2056`).
- **Tasks track** — tasks pill (**Tasks** panel, **{{completed}}/{{total}} tasks**, activity rows "Created/Added/Started/Completed {{count}}") (`composer/task-list/index.tsx:26-33`, labels `i18n/resources/en.ts:397-405`).
- **Tool calls** — collapsible tool-call rows grouped as "edited N files / ran N commands / read N files / Thought" with **Input**/**Output** detail expansion and an "Error" state (`tool-calls/presentation.ts`, `tool-calls/detail-level/overview/`, labels `i18n/resources/en.ts:2136-2161`).
- **Turn collapse / detail levels** — completed turns collapse to a summary line with **Show more**/**Show less** and **View turn details** (**Sent by {{name}}**); chat display mode (Full / Collapse tool calls / Collapse turns) is a setting (see Chat settings) (`agent-stream/turn-collapse/`, labels `i18n/resources/en.ts:2144-2149`).
- **Chat outline** — prompt rail for jumping between prompts (web/desktop wide screens) (`agent-stream/chat-outline/rail.web.tsx:164`, setting `settings.appearance.chatOutline.title` `i18n/resources/en.ts:2704-2707` ("Chat outline")).
- **Find in pane** — Cmd/Ctrl+F opens a find box (**Find**, placeholder **Find in pane**, **Previous match**/**Next match**/**Close Find**/**Find matches**); web only for chat; also used by terminals and the file editor with replace (`agent-stream/chat-find/index.web.tsx`, `pane-find/`, labels `i18n/resources/en.ts:2-23`).
- **Rewind** — "Rewind to this message" on user messages: **Rewind conversation** / **Rewind files** / **Rewind conversation and files**, with a can't-undo warning (`components/rewind/rewind-menu.tsx:49-51`, `components/rewind/rewind-menu.tsx:92`, labels `i18n/resources/en.ts:2003-2014`).
- **Context window meter** — meter in the composer/agent panel opens **Context window** details: **{{percentage}}% used**, **{{used}} / {{max}} tokens**, **Session cost {{cost}}**, plus the agent's usage report card (see Usage) (`components/context-window-meter.tsx`, `components/context-window-details.tsx`, labels `i18n/resources/en.ts:2183-2198`).
- **Empty state** — "Start chatting with this agent..." (`i18n/resources/en.ts:233`).
- **Agent stream errors/status** — "Couldn't load agent history", "This message was capped", "Scroll to bottom", "Reconnecting to host", "Updating messages", archived callout with **Unarchive** (`i18n/resources/en.ts:234-236, 256-281`).
- **Slash commands** — typing `/` in the composer offers provider commands plus client commands: `/exit` ("Archive the current agent") and `/clear` ("Archive this agent and start a fresh draft"), aliases `quit`, `q`, `new` (`client-slash-commands/index.ts:19-31`, provider commands `agent-commands/use-query.ts`).
- **Skills** — agents get Paseo orchestration skills installed host-side (Settings → host → Agents → Orchestration skills); in the composer `/` menu skills appear with a "Skill" tag (`i18n/resources/en.ts:1683`, `agent-skills/index.tsx:75`).
- **Background work** — background shells/monitors reported by the provider surface as background-work UI (`background-work/`); background agents stay hidden from tabs and status (see glossary).
- **Archived agents** — **Archive** (confirmation when running: "This agent is still running. Archiving it will stop the agent."); archived agents show an **Archived** badge and an **Unarchive** callout (`i18n/resources/en.ts:292-313`).
- **Agent list / History** — Sessions screen ("History", search placeholder "Search history", date sections Recent/Today/Yesterday/This week/This month/Older, **Load more**) (`screens/sessions-screen.tsx:63`, labels `i18n/resources/en.ts:279-290`, `i18n/resources/en.ts:293-300`).

Main source files: `agent-stream/view.tsx` (153 = permission list), `agent-stream/turn-footer.tsx`, `agent-stream/model.ts`, `agent-stream/stream-row.tsx`, `agent-stream/turn-collapse/`, `agent-stream/chat-find/`, `agent-stream/chat-outline/`, `components/message.tsx`, `components/assistant-fork-menu.tsx`, `components/rewind/rewind-menu.tsx`, `components/question-form-card.tsx`, `components/plan-card.tsx`, `subagents/track.tsx`, `composer/task-list/index.tsx`, `tool-calls/`, `timeline/`, `panels/agent-panel.tsx`, `panels/provider-subagent-panel.tsx`.

## Composer & attachments

The composer is the whole prompt surface (`composer/index.tsx:1220`).

- **Input** — text entry with placeholder "Message the agent, tag @files, or use /commands and /skills" (desktop) / "Message, @files, /commands" (mobile) / "Message..." fallback (`composer.placeholders` in `i18n/resources/en.ts:116-119`, `composer/input/input.tsx`).
- **Send / queue / steer** — send button (**Send message**, Enter), long-press to **Queue message** / **Long press to send now**; keyboard behavior configurable (see Chat settings: Enter vs ⌘/Ctrl+Enter); **Queue** vs **Send and steer** vs **Send and interrupt** when the agent is running (`i18n/resources/en.ts:124-140`).
- **Stop** — square stop button while the agent runs ("Interrupt agent", "Stop agent") (`composer/input/input.tsx:52`, `i18n/resources/en.ts:128`, `i18n/resources/en.ts:140-141`).
- **Fullscreen** — expand the input to fullscreen ("Fullscreen" / "Exit fullscreen") (`i18n/resources/en.ts` `composer.input`, `composer/input/fullscreen-exit.ts`).
- **Attachment tray** — selected attachments render as pills above the input (`composer/index.tsx:348` `renderAttachmentTray`, `composer/index.tsx:2336`).
- **Add attachment** — paperclip menu: **Add image** / **Paste image**, **Upload file**, **Add issue or PR** (GitLab: **Add issue or MR**) (`i18n/resources/en.ts:155-161`; file-pick logic `composer/index.tsx`; forge auto-attach `composer/forge-auto-attach.ts`).
- **Paste & drop** — clipboard image paste (`composer/clipboard-image.ts`, `composer/native-pasted-image.ts`), pasted large text becomes a file attachment (`composer/pasted-text.ts`), drag-and-drop files/images onto the composer (**Drop files here** / **Drop images here**) (`composer/attachments/drop.ts`, `components/file-drop/`).
- **Attachment types** — image, file (uploaded), workspace file (dragged from explorer), forge issue/PR/MR (via plugin resource / `GithubAttachmentPill`), review context, `chat_history` fork context, plugin resources, browser elements ("Element") (`composer/index.tsx` pill renderers, `attachments/`, labels `i18n/resources/en.ts:155-177`).
- **Attachment actions** — open/remove per pill ("Open image attachment", "Remove image attachment", "Remove file attachment", "Remove {{kind}} {{number}}" for issue/PR, "Open review attachment", "Open browser element attachment") (`i18n/resources/en.ts:163-176`).
- **Forge picker** — attaching an issue or PR opens a searchable picker on connected forges (`components/attachments-picker*`; forge search `git/use-forge-search-query.ts`).
- **Agent controls** — provider, model, mode, thinking and provider-feature controls (see Providers/models/modes); on a draft, the controls create the agent (`composer/agent-controls/index.tsx:983` `composer/agent-controls/index.tsx:1057` `composer/agent-controls/index.tsx:1098`).
- **Agent profiles** — pick a saved profile to fill provider/model/mode/thinking/features (see Settings → Agents → Agent profiles); profiles are consumed once at creation (`agent-profiles/`).
- **Dictation / voice** — mic button starts dictation (see Voice & dictation); voice-mode button (**Enable Voice mode**) enters realtime voice mode; mute/unmute toggles (`composer/index.tsx:1142`, `composer/input/input.tsx:57`).
- **Drafts** — new-agent composers live in a draft store; a draft can be restored, discarded, or forked from (`composer/draft/`, `stores/draft-store/`).
- **Queue track** — lane inside the composer listing queued messages with **Edit queued message** / **Send queued message now** (`composer/index.tsx:391`, `composer/index.tsx:397`).
- **@-files and /commands autocomplete** — popovers for files/commands/skills as you type (`composer/keyboard-scope.tsx`, `agent-commands/index.tsx`, labels `agentAutocomplete.*` `i18n/resources/en.ts:1674-1686`).

Main source files: `composer/index.tsx:1220`, `composer/input/input.tsx`, `composer/input/labels.ts`, `composer/attachments/`, `composer/dock/`, `composer/tracks.tsx`, `composer/agent-controls/index.tsx`, `attachments/`, `create-agent-preferences/`.

## Workspaces & projects

A workspace is one concrete `cwd` on one daemon, belonging to one project (glossary). The main surface is the workspace deck route (`app/h/[serverId]/workspace/[workspaceId]/index.tsx:93`, `:149`); each workspace keeps mounted-but-hidden deck entries so switching is instant.

### Left sidebar (`components/left-sidebar.tsx`)

- **Sidebar nav rows** (Header section, configurable): **New workspace**, **History**, **Search** (opens command center), **Schedules** — each can be shown/hidden and reordered in Settings → Sidebar (`components/sidebar/sidebar-nav-rows.tsx:81-106`, `sidebar-nav/model.ts:9-13`, labels `sidebar.actions.newWorkspace`, `sidebar.sections.sessions|search|schedules` `i18n/resources/en.ts:1269`, `i18n/resources/en.ts:1290-1292`).
- **Footer section**: **Usage** (hidden by default) — same reorder/visibility controls (`sidebar-nav/model.ts:9-13`, label `sidebar.footer.usage` `i18n/resources/en.ts:1276`). **Add project** and the icon row (**Hosts**, **Help and support**, **Settings**) are fixed (`sidebar-nav/model.ts:6-13`).
- **Projects & workspaces list** — grouped by project (or by status / by labels per Display preferences); each project row shows its workspaces; section grouping toggle ("Status", "Project", "Labels") (`components/sidebar/sidebar-status-list.tsx`, labels `sidebar.display.grouping.*` `i18n/resources/en.ts:1217-1223`).
- **Workspace row** — name (title or branch, per Display → Title), project/branch/host/PR/checks/services/labels/diff-stat/last-activity meta line (each toggleable under Display → Show), status bucket dot(s) (**Needs input** / **Failed** / **Ready to review** / **Working** / **Done**), service health, host badge (per host appearance settings), pin toggle, and trailing actions (`components/sidebar/sidebar-workspace-row.tsx`, `components/sidebar/workspace-meta-row/index.tsx`, labels `sidebar.statusBucket.*`, `sidebar.display.show.*`).
- **Pinned** — pinned workspaces in a **Pinned** section pinned to top (`sidebar.pinned.title` `i18n/resources/en.ts:1260`).
- **Display preferences** — "Display preferences" popover from the sidebar header: **Sort** (Created / Manual / Last prompt), **Grouping** (Project / Status / Labels), **Title** (Title / Branch name), **Show** (Branch, Project, Host, Pull request, Checks, Services, Labels, Diff stats, Last activity), **Checks** (Icon and text / Icon only / Hidden), **Host** filter, **Project** filter, **Background** agents toggle (`components/sidebar/display-preferences/menu.tsx`, labels `sidebar.display.*` `i18n/resources/en.ts:1200-1253`).
- **Workspace actions** (row kebab / right-click): **Copy path**, **Copy branch name**, **Rename workspace**, **Pin to top**/**Unpin**, labels menu (**Labels**), **Archive**/**Archive workspace**, **Hide from sidebar** (`components/sidebar/sidebar-workspace-menu.tsx:199-276`, labels `sidebar.workspace.actions.*` `i18n/resources/en.ts:1343-1356`).
- **Archive with undo** — archiving shows a toast "Workspace archived" with **Undo** (`i18n/resources/en.ts:1378-1379`, `workspace/archive-undo/`).
- **Archive/hide confirmations** — "Archive workspace?" (running-agent warning: "This agent is still running. Archiving it will stop the agent."), "Hide workspace?" with "Files on disk will not be changed." (`i18n/resources/en.ts:1357-1365, 1302-1310`).
- **Add project** — "Add project" row at the sidebar foot; opens the add-project flow (`sidebar.actions.addProject` `i18n/resources/en.ts:1268`, `components/add-project-flow-host.tsx`, `add-project-flow/`).
- **Project actions** — per project: **Open settings**, **Open in new window**, **Open in file manager**, **Remove project** (confirmation "Remove project?"…) (`i18n/resources/en.ts` `sidebar.project.actions.*` / `confirmations.remove*`).
- **Host groups** — per-host sections, **Switch host** picker ("Switch host", search "Search hosts...") (`i18n/resources/en.ts:1263-1266`, `components/left-sidebar.tsx` `SidebarHostPicker`).
- **Help and support** — footer icon: **Run diagnostics**, **Keyboard shortcuts**, **Report an issue**, **Discord**, **Create GitHub issue**, **What's new** (`components/sidebar/sidebar-help-menu.tsx`, labels `sidebar.help.*` `i18n/resources/en.ts:1280-1291`).
- **Sidebar callouts** — e.g. worktree setup discovery ("Set up worktree scripts") and plugin callouts (`components/worktree-setup-callout-source.tsx`, `contexts/sidebar-callout-context.tsx`).

### Workspace screen (`screens/workspace/workspace-screen.tsx`)

- **Tabs** — agents, terminals, files, diffs, PR pane, setup, browser: rename ("Rename"), close ("Close"), close to the left/right/above/below, close others, move to main panel, pin, **Copy resume command** / **Copy agent id** / **Copy terminal id** / **Copy file path**, **Reload agent** ("Reload agent to update skills, MCPs or login status."), confirmations for unsaved changes and running agents/terminals (`screens/workspace/workspace-desktop-tabs-row.tsx`, `screens/workspace/workspace-new-tab-menu.tsx`, labels `workspace.tabs.*` `i18n/resources/en.ts:644-749`).
- **Tab switcher** — compact-layout dropdown ("Switch tabs ({{count}} open)", search "Search tabs") (`screens/workspace/compact-workspace-header/tab-switcher.tsx`, labels `workspace.tabs.switcher.*` `i18n/resources/en.ts:658-663`).
- **New tab menu** — **New agent**, **New terminal**, **New browser**, **Changes**, **Files**, **Pull request**, terminal profiles (**Terminal profiles** / **Edit profiles**), **Maximize pane** / **Restore pane** / **Close pane**, **Split pane right** / **Split pane down**, **Exit focus mode** (`screens/workspace/workspace-new-tab-menu.tsx`, `screens/workspace/workspace-tabs-types.ts`, labels `workspace.tabs.actions.*` `i18n/resources/en.ts:684-698`).
- **Workspace header menu** — "Workspace actions": **New agent**, **New terminal**, **New browser tab**, **Import session**, **Copy workspace path**, **Copy branch name**, **Show setup**; on compact layouts it also hosts the scripts sub-pages and "Exit focus mode" (`screens/workspace/workspace-header-menu.tsx:109-136`, labels `workspace.header.actions.*` `i18n/resources/en.ts:752-762`).
- **Explorer sidebar** — dedicated dock with **Files** and **Changes** trees, toggle **Open/Close/Toggle Explorer sidebar**; on compact layouts the trees open in a sheet instead (`screens/workspace/explorer-sidebar.tsx`, `workspace-tabs/explorer-sidebar.ts`, labels `workspace.tabs.explorerSidebar.*` `i18n/resources/en.ts:700-706`).
- **Side pane** — files/diffs/subagents opened "On the side" render beside the work and close like ordinary panes (glossary; "Open location" settings).
- **Sheet tabs** — files/subagents shown over the workspace without entering the tab switcher; action **Open as tab** (`screens/workspace/sheet-pane/sheet-pane.tsx`, `workspace-tabs/`).
- **Splits** — split panes right/down, drag tabs between panes, focus mode (hide sidebar/chrome), maximize/restore pane (`screens/workspace/workspace-desktop-tabs-row.tsx`, keyboard shortcuts `settings.shortcuts.help.*`).
- **New browser tab** (desktop/web) — built-in Electron browser pane with Back/Forward/Stop/Refresh, URL bar, **Open browser dev tools**, **Annotate element** (attach an element to the agent with a message), **Screenshot element** (copies to clipboard), device size picker (**Responsive**…), unsupported-protocol blocking; the empty state on non-desktop reads "Browser is desktop-only" (`desktop/browser/pane/index.electron.tsx`, labels `workspace.browser.*` `i18n/resources/en.ts:598-632`).
- **Setup tab** — workspace creation setup log: statuses **Running/Completed/Failed/Blocked**; for fork PRs "Setup was not run" with **Run setup** (`i18n/resources/en.ts:558-596`, `panels/setup-panel.tsx`).
- **Import session** — import a terminal/CLI session from a host into an agent ("Import session", search "Search sessions...", scope **This workspace**/**Sessions on {{host}}**) (`i18n/resources/en.ts:419-435`, `hooks/use-import-session.tsx`).
- **Workspace deck retention** — recent workspaces stay mounted in memory for instant switching (`app/h/[serverId]/workspace/[workspaceId]/index.tsx:149`, `:229`).

### New workspace (`app/new.tsx` → `screens/new-workspace-screen.tsx:848`)

- **Project** picker (choose the project; suggestions for recent folders), **Host** picker, **Isolation** (**Local** — reuse checkout — or **New worktree**), **Branch** / **Starting ref** picker ("Start from…", search "Search branches and PRs"), optional **Title (optional)**, launch target **What to launch**: **Chat** or **Terminal** (+ "Prompt {{name}}" / "Run a command, or leave empty for a blank terminal"; **Manage profiles**), **Create** (`app/new.tsx:14`, `screens/new-workspace/form/`, labels `newWorkspace.*` `i18n/resources/en.ts:1384-1435`).
- **Workspace setup dialog** — shown when a worktree needs setup ("Create workspace", "Set up worktree scripts" callout linking to project settings) (`components/workspace-setup-dialog.tsx`, `i18n/resources/en.ts:1698-1708`, `:1294-1298`).
- **Worktree isolation** — new workspace from a git workspace uses the active workspace's project; host must support multiplicity/worktrees (`components/sidebar/sidebar-nav-rows.tsx:84-106`).

### Sessions / history (`app/sessions.tsx:4` → `screens/sessions-screen.tsx:63`)

- "History" — all agent sessions across hosts/workspaces, grouped by date (Recent, Today, Yesterday, This week, This month, Older), **Search history**, **Load more**, archived badge, empty "No sessions yet" / "No sessions match" / "Too many matches — narrow your search"; tapping one navigates to the agent (`i18n/resources/en.ts:279-290`).

### Projects (`screens/projects-screen.tsx:24`, `screens/project-settings-screen.tsx:100`)

- Projects list per host (Settings → host → Projects); project settings (Settings → host → Projects → project): **Edit project** (Name, Icon), **Worktree lifecycle hooks** (**Setup** / **Teardown** multiline, stale-config warning), **Scripts** (see Scripts), **Metadata generation** (**Branch names** / **Commit messages** / **Pull requests** prompt fields), save with **Save**; stale on-disk paseo.json shows "Config changed on disk" with **Reload** (`i18n/resources/en.ts:3222-3276`; screens/project-settings-screen.tsx).

### Workspace labels

- **Labels** — user-defined labels on workspaces; filter sidebar by label; assign from workspace menu or command center (`workspace-labels/`, labels `workspaceLabels.*`, screens/settings mentions).

Main source files: `components/left-sidebar.tsx`, `components/sidebar/`, `sidebar-nav/model.ts`, `screens/workspace/workspace-screen.tsx` (4123 lines), `screens/workspace/workspace-desktop-tabs-row.tsx`, `screens/workspace/workspace-header-menu.tsx`, `screens/workspace/workspace-new-tab-menu.tsx`, `screens/workspace/compact-workspace-header/`, `screens/workspace/explorer-sidebar.tsx`, `screens/workspace/sheet-pane/`, `screens/workspace/use-workspace-tab-rename.tsx`, `screens/new-workspace-screen.tsx`, `screens/new-workspace/form/`, `screens/sessions-screen.tsx`, `screens/open-project-screen.tsx`, `screens/projects-screen.tsx`, `screens/project-settings-screen.tsx`, `workspace-tabs/`, `workspace/`, `workspace-labels/`, `stores/workspace-layout-store.ts`, `stores/panel-store/`.

## Git, diffs & worktrees

### Changes panel (Explorer sidebar / changes tabs)

- **Changes** / **Diff** — the Changes tree (changed files by directory, combine/collapse, revert) and the working-tree diff viewer; tab tooltips "Working tree diff" / "Commit diff" (`panels/diff-panel.tsx:240,245,255`, labels `panels.diff.*` `i18n/resources/en.ts:2124-2127`).
- **Diff mode** — "Diff options" menu: **All changes** / **Uncommitted** / **Committed** ("Compared with {{baseRef}}") (`git/diff-pane.tsx:296`, labels en.ts:976-1002).
- **Unified vs side-by-side** — "Switch to unified diff" / "Switch to side-by-side diff" toggles (`git/diff-pane.tsx:244`, labels `i18n/resources/en.ts:972-976`).
- **Options** — **Inline diff**, **Hide whitespace**/**Show whitespace**, **Scroll long lines**/**Wrap long lines**, **Collapse all files**/**Expand all files** (`i18n/resources/en.ts:977-987`).
- **Commits** — "Commits" list ahead of base; per-commit rows open a commit diff tab (short-sha label) (`git/commits-section/`, label "Commits" `i18n/resources/en.ts:1004`).
- **Jump to file** — floating button + sheet to jump between changed files (`git/jump-to-file/index.tsx:55`, label `workspace.git.diff.jumpToFile.*`).
- **Base branch** — worktrees can change the comparison base ("Change base", picker) when the host exposes it (`git/workspace-base-branch-picker.tsx:33`).
- **Discard changes** — context menu "Discard changes" on a file with uncommitted changes; confirmation required (`git/actions-store.ts:375` area; `workspace.fileActions.revert` "Discard changes", `i18n/resources/en.ts:502`).
- **PR/MR badge & link** — sidebar rows and Changes toolbar show the PR/MR state ("Pull request #{{number}}"/"Merge request !{{number}}") with a forge icon; clicking opens the PR pane or the forge (`git/pr-status.ts`, `git/pull-request-connection.tsx`, `workspace.git.pr.*` `i18n/resources/en.ts:1021-1135`).
- **Checks** — PR checks section with per-check rows, status rollups ("{{count}} failing"…), "Checks passed/running/failed" summaries, add-check-output-to-chat (**Add to chat** / **Add all to chat**) (`git/pull-request-panel/checks-section.tsx:67,225`, labels `workspace.git.pr.*` `i18n/resources/en.ts:1021-1077`).
- **PR/MR pane** — "Activity" timeline: approvals ("{{given}} of {{required}} approvals"), reviews/comments threads with "Discussion thread"/"Resolved"/"Outdated" badges, **Add to chat** per thread/comment, **Open on {{brand}}** (`git/pull-request-panel/pane.tsx:571,705,967,1021,1067-1135`, labels `workspace.git.pr.*`).
- **Forge setup callout** — when `gh`/`glab` etc. is missing or unauthenticated the Changes pane shows a setup callout ("Install the {{cli}} CLI…") (`git/diff-pane.tsx` `computeForgeSetupAction`, labels `workspace.git.forgeSetup.*` `i18n/resources/en.ts:1130`).

### Git actions (repo toolbar split button — `git/actions-split-button.tsx:78`)

Grouped actions with unavailability explanations (`workspace.git.actions.*` `i18n/resources/en.ts:811-956`):

- **Commit** — "Commit" (host generates the message from the Metadata generation model).
- **Pull** / **Push** / **Pull and push** — with precise disabled reasons (not connected to a remote, local changes present, up to date / nothing to push / behind…).
- **Create PR** / **Create MR** — "Create PR" / "Create MR" (forge noun); **View PR** / **View MR**.
- **Merge locally** — merge the branch into base locally.
- **Update from {{baseRef}}** — merge base into the branch.
- **Merge PR (squash|merge|rebase)** / **Merge MR (…)** — direct merge.
- **Auto merge (squash|merge|rebase)** — enable/disable auto-merge.
- **Archive workspace** — suggested after merge (archive warning with unpushed/uncommitted counts; undo offered) (`git/use-actions.tsx`, `git/worktree-archive-warning.ts`).

### Branch switcher (`components/branch-switcher.tsx`)

- **Switch branch** — combobox: "Switch branch..." trigger, "Filter branches..." search, lists local branches (+ remote refs?); on uncommitted changes asks **"Stash & Switch"** vs cancel; offers restore afterwards (**Restore**/**Later**, "Stashed changes restored"); checkout failures toast (`branchSwitcher.*` `i18n/resources/en.ts:1654-1680`).

### Review (diff comments)

- **Add review comment** — inline in the diff: gutter "+" opens an editor ("Leave a comment"), **Comment** to save / **Cancel** / **Delete review comment**; draft comments persist per diff mode; **Send feedback ({{count}})** sends the accumulated review comments to a chosen open agent in this workspace (outline: review flow files/components under `review/`) (`review/comment-sheet.tsx:44-88`, `review/surface.tsx`, labels `review.*` `i18n/resources/en.ts:2192-2214`; editor `review/editor/index.ts`).

### Worktrees

- **New worktree** — creating a workspace with Isolation **New worktree** cuts a Paseo-managed worktree; the new-workspace screen exposes it (`new-workspace` section; `hooks/use-active-worktree-new-action.ts`; `i18n/resources/en.ts:1389-1390`).
- **Setup scripts** — worktree lifecycle: setup/teardown commands in paseo.json; run at worktree creation; settings callout "Set up worktree scripts" when missing (see Projects → project settings) (`components/worktree-setup-callout-source.tsx`, labels `sidebar.worktreeSetup.*` `i18n/resources/en.ts:1294-1298`).

Main source files: `git/diff-pane.tsx`, `git/diff-tree.ts`, `git/use-actions.tsx`, `git/actions-store.ts`, `git/use-status-query.ts`, `git/actions-split-button.tsx`, `git/changed-files-tree.tsx`, `git/commits-section/`, `git/pull-request-panel/`, `git/forge.ts`, `git/forges/`, `git/branch-switcher-operations.ts`, `components/branch-switcher.tsx`, `review/`, `composer/forge-auto-attach.ts`, `git/jump-to-file/`.

## Files

### File explorer (Files tree in the Explorer sidebar / Files panel)

- **Browse** — directory tree; click a folder toggles, click a file opens it (`components/file-explorer-pane.tsx:274`, `:576`).
- **Sort** — Name / Modified / Size cycle button (`components/file-explorer-pane.tsx:913-915`, labels `workspace.fileExplorer.sort.*` `i18n/resources/en.ts:521-525`).
- **Hidden files** — "Show hidden files" / "Hide hidden files" toggle (`components/file-explorer-pane.tsx:1202-1203`, labels `i18n/resources/en.ts:533-535`).
- **New file / New folder** — header buttons and empty-area right-click; inline name input ("File name" / "Folder name"), Escape cancels (`components/file-explorer-pane.tsx:222-223`, `:1258`, `:1270`, `panels/files-panel.tsx`).
- **Context menu** on entries: **Open file**, **Open in {{target}}**, **Open to the side**, **Copy path**, **Copy relative path**, **Reveal in {{target}}**, **Download**, **Add to chat**, **Collapse folder**, **Rename**, **Duplicate**, **Delete** (confirmation "Delete file?" / "Delete folder?" with "will be permanently deleted.") (`components/file-explorer-pane.tsx:632-832`, `components/file-actions-menu.tsx`, labels `workspace.fileActions.*` `i18n/resources/en.ts:487-516`).
- **Drag into composer** — dragging a file row into a composer attaches it as a workspace-file attachment (with line ranges from a selection) (`attachments/workspace-file-drag.ts`).
- **Add to chat** — attaches the file (or selected lines) to the focused agent chat (`panels/use-add-file-to-chat.ts`).
- **States** — "Loading files...", "Workspace is unavailable", "No files" / "No visible files", **Retry**/**Back**, "Failed to list directory" (`i18n/resources/en.ts:519-555`).

### Opening files

- **Open** — files open as tabs in the main pane, on the side, or in the Explorer sidebar; the destination is per-target in Settings → Open location (**Open location**: Main panel / On the side / Explorer sidebar) (`screens/settings/open-location/open-location-section.tsx:87`, destinations `i18n/resources/en.ts:2325-2331`).
- **File actions menu** — same menu as the explorer (see above); **Download** sends the file through a daemon token download (`components/file-actions-menu.tsx`, `hooks/use-file-download.ts`).
- **Open in editor / Reveal in file manager** — desktop/web header split button: preferred target opens the workspace; menu lists other targets; explorer directory rows get "Open in {{target}}" (`workspace/open-in-editor/button.tsx:84`, `workspace/open-in-file-manager/menu-item.tsx:26`, labels `i18n/resources/en.ts:1014-1019`; sidebar project menu **Open in file manager** label `sidebar.project.actions.openFolder`).
- **Open with…** — right-click a file tab: **Open with…** sub-menu; **Always use for .{{ext}}** / **Always use for {{filename}}**; first-open picker sheet "Open .{{extension}} files with" with **Don't ask me again** and **Use** (`file-panels/choice/open-with.tsx:33`, `file-panels/choice/picker.tsx:24`, labels `panels.file.filePanels.*` `i18n/resources/en.ts:2064-2079`).
- **Built-in viewers** — Markdown / HTML / Image preview plus a Source (code) editor floor; the editor has vim keybindings option (Settings → Editor), find/replace (**Find in pane**), autosave, conflict handling ("Changed on disk" / "File deleted on disk" with **Overwrite**/**Reload**/"Reload from disk?") (`file-panels/builtin.tsx`, `file-panels/source/`, labels `panels.file.editor.*` `i18n/resources/en.ts:2091-2107`).
- **File panels from plugins** — plugins can register file panels (e.g. custom viewers); seen in Settings → Files (`settings.files.empty` state "File panels appear here when a plugin adds one") and the **Open with…** menu (`plugins/`).
- **Find in file** (web) — **Find in pane** with **Replace** / **Replace with** / **Replace all** (`file-panels/source/find/index.web.tsx`).

## Terminals

- **New terminal** — "New terminal" from the header menu, the + menu, command center, or shortcut; a terminal profile can launch a named command (**Terminal profiles**: name, command, args; reorder/edit/delete in Settings → host → Terminals) (`screens/workspace/workspace-header-menu.tsx`, labels `workspace.tabs.actions.newTerminal` `i18n/resources/en.ts:684`, `settings.host.terminalProfiles.*` `i18n/resources/en.ts:3000-3022`).
- **Terminal tabs** — live terminal title on the tab chip, activity status dot (running → ring), rename ("Rename terminal"), **Copy terminal id**, close with confirmation ("Close terminal? Any running process in this terminal will be stopped immediately.") (`panels/terminal-panel.tsx`, `screens/workspace/use-workspace-tab-rename.tsx`, labels `workspace.tabs.menu.*` `i18n/resources/en.ts:666-677`).
- **Find in terminal** — Cmd/Ctrl+F opens the pane-find box: "Find in pane", "No matches", "{{current}} of {{total}}", **Previous match** / **Next match** / **Close Find** (`terminal/find/index.tsx`, labels `paneFind.*` `i18n/resources/en.ts:2-23`).
- **Paste / drop files** — paste or drop a file into a terminal: local-host files paste their path (shell-escaped), remote uploads first ("Uploading file…" / "File uploaded" / "Failed to paste file: {{reason}}", 50 MB cap) (`terminal/file-paste/`, `terminal/drop/terminal-file-drop.ts:50`, `i18n/resources/en.ts:638-641`).
- **Local links** — file paths (with `:line[:col]`) in output are clickable and open in the main pane (side pane with Cmd/Ctrl+click) (`terminal/local-links/`).
- **Terminal activity** — activity dots/rings on tab chips driven by host hook reporting (`workspace-status/`, `screens/workspace/terminals/`).
- **Virtual keys** — on compact/native: Ctrl/Shift/Alt bar, **Show keyboard** / **Hide keyboard** (`components/terminal-pane.tsx`).
- **Terminal scrollback** — Settings → Terminal: **Terminal scrollback** (lines kept in the buffer) (`screens/settings/terminal/terminal-section.tsx:10`, labels `i18n/resources/en.ts:2599-2603`).
- **Terminal agent hooks** — Settings → host → Terminals: **Enable terminal agent hooks** (notifications and status from terminal agents; installs hooks into agent config files) (`screens/settings/host-page.tsx` `EnableTerminalAgentHooksCard`, hard-coded labels).
- **Native renderer** — host-side native terminal renderer with its own install prompt ("Update the host to use the native terminal renderer.") (`i18n/resources/en.ts:635`, `terminal/native-renderer/`).

## Scripts & services

Workspace scripts are named commands declared in `paseo.json` — either long-running **services** or one-off **scripts**. UI calls the panel/menu **Scripts**; only services surface health in the sidebar.

- **Scripts menu** — header **Scripts** split button (icon-only play glyph colored by state) lists scripts; per row: **Run** / **Stop** / **Restart**, **View terminal** / **View service**, service routes **Reverse proxy** / **Memorable** / **Direct**, **Choose URL**, **Copy URL** (`screens/workspace/scripts/workspace-scripts-button.tsx:445`, labels `workspace.scripts.*` `i18n/resources/en.ts:772-806`).
- **Compact menu** — scripts listed as pages of the workspace sheet; trigger dot turns red ("Workspace actions, a service is unhealthy") when a service fails health (`screens/workspace/scripts/workspace-scripts-menu-pages.tsx`, labels `workspace.header.actions.workspaceActionsUnhealthy` `i18n/resources/en.ts:754`).
- **Status/health** — running (blue) / healthy (green) / unhealthy (red) / idle (muted); **exit {{code}}** badge; sidebar rows report the service ("Service {{name}} running" / "Service {{name}} unhealthy") (`screens/workspace/scripts/script-status.ts`, `script-marks.tsx`, `components/sidebar/workspace-meta-row/service-summary.ts`).
- **Open service** — **View service** opens the URL: in Electron the app asks (or remembers) **In Paseo** vs **External browser** (**Don't ask again**, stored in `serviceUrlBehavior`); Settings → Open location controls the behavior ("Clicking a script's service URL": **Ask** / **In Paseo** / **External browser**) (`utils/open-service-url.ts`, labels `i18n/resources/en.ts:2021-2026`, `:2357`, `:2592-2598`; route store `workspace-service-routes/store.ts`).
- **Configuring scripts** — paseo.json via project settings → **Scripts** group: **Add script**, Name, **Command** (multiline), **Run as a service** switch ("$PASEO_PORT" hint), **Edit** / **Remove** per row (`screens/project-settings-screen.tsx`, labels `settings.project.scripts.*` `i18n/resources/en.ts:3237-3276`).

## Schedules

Cron-style triggers that create new agents, plus heartbeats (cron prompt back into the same agent). UI: **Schedules** (sidebar row, `/schedules` route).

- **Schedules screen** — lists schedules across hosts (host picker, **All hosts**, status filter **Active** / **Ended**); empty states "No active schedules" / "No ended schedules" ("Schedules run agents on a cadence."); per-host load errors; hardcoded English copy (not translated) (`app/schedules.tsx:4`, `screens/schedules-screen.tsx:48-51`, `:55`).
- **Row actions** — status pills (**Active**/**Paused**/**Expired**/**Finished**/**Target gone**), last/next run, resume/pause toggle, **Run now** (new-agent targets only), edit (pencil), delete; overflow menu (**Delete**) (`components/schedules/schedule-row.tsx:55`, `:84-92`).
- **Create/edit** — form sheet titled "New schedule" / "Edit schedule" / "Edit heartbeat": **Name** (optional), **Prompt**, **Max runs** ("Unlimited"), **Host**, **Project**, **Model**, **Thinking**, **Mode**, **Archive on finish**, isolation **Local** / **Worktree**, cron cadence (**Cadence** editor); validation "Choose a cron cadence before creating this schedule"; buttons **Create schedule** / **Save changes** (`components/schedules/schedule-form-sheet.tsx:404-443`, `:537-544`, `:706-835`, `components/schedules/cadence-editor.tsx`).
- **Heartbeats** — agent surfaces expose create, update cron, and delete for heartbeats (see glossary); created from agents/CLI; the same form serves both ("Edit heartbeat" title at `components/schedules/schedule-form-sheet.tsx:406`).
- **Sidebar "Schedules" row** — navigates to `/schedules` (`components/sidebar/sidebar-nav-rows.tsx:168-186`).

Main source files: `app/schedules.tsx`, `screens/schedules-screen.tsx` (loadState/hydration), `schedules/`, `components/schedules/`, `screens/schedules-screen-state.ts`.

## Command center

Open with the Search row, a shortcut (`toggle-command-center`), or **Search** in the sidebar; placeholder "Search commands, files, workspaces, and agents..." (`i18n/resources/en.ts:85`, `command-center/command-center.tsx:767`).

- **Sections** — **Actions**, **Files**, **Workspaces**, **Agents**, plus plugin contributions and model/thinking/mode/fast groups (**Model**, **Thinking**, **Mode**, **Plan mode**, **Fast**) (`i18n/resources/en.ts:88-108`, `command-center/workspace-contributions.ts`, `command-center/agent-control-contributions.ts`).
- **Root actions** — **Add project**, **New workspace**, **Import session**, **Home**, **History**, **Schedules**, **Settings**, **Keyboard shortcuts** (when available), **Group by project** / **Group by status** toggle, **Toggle left sidebar** (`command-center/root-registration.tsx:150-330`).
- **Workspace actions** — **New agent**, **New terminal**, **New browser**, **Changes**, **Files**, **Pull request**, split/focus/close-pane actions, **Close tabs left/right/others**, **Rename agent/tab**, **Copy resume command** / **Copy agent id** / **Copy terminal id** / **Copy file path**, **Reload agent**, **Move tab**, workspace management (**Rename workspace**, **Copy path**, **Copy branch name**, **Pin/Unpin**, **Show setup**, labels group) and git actions (commit/pull/push/PR…) (`command-center/workspace-registration.tsx:239-279`, `command-center/workspace-contributions.ts`, `command-center/workspace-shortcuts.ts`).
- **File search** — search workspace files; results show `kind:path`; open / open in side pane / open in focused pane (`command-center/workspace-file-search.ts`, labels `shell.commandCenter.filePlaceholder`, `shell.commandCenter.openInSidePane|openInFocusedPane` `i18n/resources/en.ts:86-96`).
- **Workspaces search** — jump to any workspace; agents search — jump to any agent (`command-center/workspace-search.ts`).
- **Agent control groups** — switch **Model**, **Thinking**, **Mode**, **Plan mode**, **Fast** from the command center (`command-center/agent-control-contributions.ts`).
- **Keyboard-driven** — arrow keys + Enter; Escape closes; shows shortcut badges (`keyboard/`).

Main source files: `command-center/`, `app/_layout.tsx:562` (mounted), `stores/keyboard-shortcuts-store.ts`.

## Settings

Settings home (`screens/settings-screen.tsx`) lists two groups — **App** and **Host** — and renders as a split view on wide layouts / full-screen list on compact (`SIDEBAR_SECTION_ITEMS` `screens/settings-screen.tsx:164`, `HOST_SECTION_ITEMS` `screens/settings-screen.tsx:247`, groups "App"/"Host" `settings.groups.*` `i18n/resources/en.ts:2292-2295`). Back navigation returns to the workspace ("Back", `settings.backToWorkspace`). The active host picker sits above the Host group ("Switch host", plus **Add host** and **Enable built-in daemon** when applicable, `screens/settings-screen.tsx`).

### App sections (route `/settings/[section]`; slugs in parentheses)

- **General** (`general`, `screens/settings-screen.tsx:359`): **Language** dropdown (System, Arabic, English, Spanish, French, Japanese, Korean, Brazilian Portuguese, Russian, Simplified Chinese); **Show setup again** row (web/desktop) — reopens onboarding. **Sending** card (`screens/settings/general/sending-section.tsx:10`): **Send shortcut** (Enter / ⌘-Ctrl+Enter), **Default send** (Interrupt / Steer / Queue) — hardware-keyboard only rows; descriptions vary by selection.
- **Appearance** (`appearance`, `screens/settings/appearance/appearance-section.tsx:301`): **Theme** — Theme picker: Light, Dark, Zinc, Midnight, Claude, Ghostty, Pure black, System; **Fonts**: **Interface font** (desktop/web only), **Interface size**, **Content size**, **Code font**, **Code size** (px); **Layout**: **Content width** (px, reset); **Syntax**: **Highlight theme** (highlight.js theme for code, independent of app theme); live preview card below; **Sidebar view** plugin picker sits on Sidebar page (below).
- **Sidebar** (`sidebar`, `screens/settings/sidebar/sidebar-nav-section.tsx:184`): **Sidebar view** (plugin-provided views + "Default view"), **Header** card (New workspace, History, Search, Schedules — reorder up/down, visibility switch; plugin items listed), **Footer** card (Usage — hidden by default; the Add-project row and icon row always show). Rows show their shortcut badge.
- **Chat** (`chat`, `screens/settings/chat/chat-section.tsx:15`): **Always expand reasoning** (switch); **Chat display** (Full / Collapse tool calls / Collapse turns); **Chat outline** ("Show an outline for jumping between prompts", web/desktop only).
- **Terminal** (`terminal`, `screens/settings/terminal/terminal-section.tsx:10`): **Terminal scrollback** (lines kept in buffer). Terminal *profiles* are host-scoped (host → Terminals).
- **Browser** (`browser`, desktop only, `desktop/browser/settings/browser-data-section.tsx:12`): **Browser data** — **Cookies and site data** with a destructive **Clear browser data** button (confirmation dialog).
- **Editor** (`editor`, web only, `screens/settings/editor-section.tsx:9`): **Vim keybindings** (switch; "Applies to source files on web and desktop.").
- **Files** (`files`, `screens/settings/files-section.tsx:28`): one row per contended file-type selector claimed by >1 panel plugin: dropdown of candidate panels (default **Ask every time**), **Ask again** button, **Not on a connected host** state; empty state "File panels appear here when a plugin adds one".
- **Shortcuts** (`shortcuts`, hardware keyboard only, `screens/settings/keyboard-shortcuts-section.tsx:336`): sections **General** / **Projects & Workspaces** / **Tabs & Panes** / **Layout** / **Agent Input**; each row = chord + overflow menu (**Bind** / **Rebind** / **Clear** / **Reset to default**); press-to-capture binding; **Not set** state; **Reset all** button when overrides exist; "Reset to default" everywhere. Labels `settings.shortcuts.sections.*` / `settings.shortcuts.help.*`.
- **Integrations** (`integrations`, desktop only, `desktop/components/integrations-section.tsx:10`): **Command line** — switch installs/uninstalls the `paseo` CLI ("Control and script agents from your terminal"); docs link.
- **Notifications** (`notifications`, desktop only, `desktop/components/desktop-notifications-section.tsx:20`): **Notification permission** row (**Granted** / **Request** / **Requesting…** with **Refresh**), **Play sound** (switch; "Play a sound when a desktop notification arrives"), **Test notification** (**Send** button; hint "Send a notification using these settings"; "permission required" state; inline result).
- **Permissions** (`permissions`, desktop only, `desktop/components/desktop-permissions-section.tsx:17`): **Microphone** row (**Granted** / **Request** / **Requesting…**) with **Refresh**.
- **Diagnostics** (`diagnostics`, `screens/settings-screen.tsx:426`): **App diagnostic** (**Run** — collects daemon/provider/desktop/log details), **Test audio** (**Play test** / **Playing…** with inline result).
- **About** (`about`, `screens/settings-screen.tsx:477`): **App version** (this device); **What's new** row (→ changelog); **Release channel** (Stable / Beta segmented, desktop only); **App updates** (desktop only): status + **Check** / **Update to {{version}}** / **Installing…** with confirmation; **Connected hosts** sub-section — one row per host with daemon version (or "Offline"), "Version differs from this device" hint on mismatch (`screens/settings-screen.tsx:535`); **Community links** footer.

### Open location ("Open location" section — `screens/settings/open-location/open-location-section.tsx:87`)

Its own section titled **Open location** listing where content opens for each source: **Clicking a file in the Explorer sidebar**, **Clicking a change in the Explorer sidebar or a chat**, **Clicking a file in an agent chat**, **Clicking a file in a diff**, **Clicking a subagent in an agent chat**, **Clicking a pull request in the Explorer sidebar** (adds **Explorer sidebar** destination), **Clicking a script's service URL** (options **Ask** / **In Paseo** / **External browser**). Destinations: **Main panel** / **On the side** / **Explorer sidebar** (where applicable). Labels `settings.layout.openInSidePane.*` / `settings.general.serviceUrls.options.*` `i18n/resources/en.ts:2325-2361`.

### Host sections (route `/settings/hosts/[serverId]/[hostSection]`)

Per-host, scoped to the host selected in the settings sidebar picker (**Switch host**). Sections (`HOST_SECTION_ITEMS` `screens/settings-screen.tsx:247`):

- **Overview** (`host`, `screens/settings/host-page.tsx:363` `HostSettingsPage`): badges row — connection status (Connected/…), **Relay**/**Local**/**Remote SSH** badge, daemon version; error banner. **Appearance** card (`screens/settings/host-appearance-section.tsx`): **Name** (read-only + pencil → **Rename host** modal), **Color** (Default, Violet, Sky, Emerald, Orange, Pink, Indigo, Teal, Red, Amber, Blue), **Sidebar badge** (**Name** / **Icon only** / **Hidden**) + live preview. **Built-in daemon** card (desktop + local daemon): **Daemon** section — status (**Running**/Not running), **Manage built-in daemon** (switch; off = paused), **Keep running after quit** (switch), **Daemon logs** (**Open logs** / **Copy path**), **Full status** (**View** → CLI status modal), **Restart daemon** (**Restart**, "Restart and close terminals" variant when supported); **Update daemon** card (remote hosts w/ version mismatch). **Danger zone**: **Remove host** / **Remove localhost connection** (destructive confirm; removing localhost stops the built-in daemon).
- **Projects** (`projects`, `screens/projects-screen.tsx:24`): project list; tap → project settings (see Projects above).
- **Connections** (`connections`, `screens/settings/host-page.tsx:251`): one row per saved connection — label (**Via {{name}}** / **Relay (endpoint)** / **Local (path)** / **Remote SSH (host)** / **TCP (endpoint)**), live latency ("{{n}} ms" or **Timeout**), destructive **Remove** (confirm).
- **Pair device** (`pair-device`, `screens/settings/host-page.tsx:266`): **Pair a device** row → pairing QR/link modal (see Hosts & pairing).
- **Agents** (`agents`, `screens/settings/host-page.tsx:281`): **Enable Paseo tools** (switch; "Agents will be able to manage worktrees, agents and schedules"); **Browser tools** (switch + trust warning; agents can control in-app browser including logged-in state); **System prompt** (**Edit**; multiline append-system-prompt; **Reset**/**Save**); **Resume agents after restart** (switch + **Edit** resume prompt; `screens/settings/restart-recovery-card.tsx`); **Release idle agents** (switch; "Free up memory after an hour of inactivity."; `screens/settings/idle-runtime-cleanup-card.tsx`); **Orchestration skills** (section; switch install/uninstall + gear → skill picker ("All skills" toggle + per-skill list; **Choose skills**) + **Update** when drift; docs link; `agent-skills/index.tsx:48`); **Agent profiles** (section; add/edit/delete/reorder; fields: **Name**, **Icon**, **Provider**, **Model**, **Mode**, **Thinking**, **Features**, "When to use" notes; `agent-profiles/settings/agent-profiles-section.tsx:29`).
- **Metadata** (`metadata`, `screens/settings/metadata-generation-page.tsx`): **Metadata generation** — **Model selection**: **Automatic** / **Manual** (segmented); **Model** dropdown (Manual only); used for workspace titles, branch names, commit messages, PR drafts.
- **Voice** (`voice`, `screens/settings/voice/voice-page.tsx:43`): **Dictation** — **Dictation** switch + **Speech-to-text** row; **Voice mode** — **Voice mode** switch, **Listening** row, **Speaking** row; each row opens the provider sheet (see Voice).
- **Workspaces** (`workspaces`, `screens/settings/host-page.tsx:311`): **Archive merged PR workspaces** (switch; "Automatically archive clean Paseo workspaces after their pull request is merged"; hard-coded label).
- **Providers** (`providers`, `screens/settings/host-page.tsx:335`): section **Providers** — one row per detected provider: icon, label, status (**Available** / **Error** / **Not installed** / **Disabled**), model count, enable switch, overflow menu **Remove provider** (custom providers only); row opens provider settings sheet (diagnostic, models, custom models). Second section **Add provider** — provider catalog with **Install** buttons (`screens/settings/providers-section.tsx:356`).
- **Usage** (`usage`, `screens/settings/host-page.tsx:349`): **Plan usage** — host **Check usage** policy switch ("Applies to {{host}} on every device"), **Summary in sidebar** (device), **Percentages** (**Used**/**Remaining**), refresh-all, per-window pins (see Usage).
- **Terminals** (`terminals`, `screens/settings/host-page.tsx:1650`): **Terminal agents** — **Enable terminal agent hooks** (switch); **Terminal profiles** — **Add** (+) / edit / reorder / delete; fields **Name**, **Command**, **Arguments** ("Space-separated arguments…"); **Manage profiles** link from new-workspace; empty state "No profiles yet…".
- **Plugins** (`plugins`, `screens/settings/plugins-page.tsx:269`): warning "Plugins are trusted code"; **Enable plugins** global switch; **Plugin source** input ("owner/slug, directory, Git URL, or npm package") + **Install plugin**; plugin rows (status running/disabled/failed, description, source); **Settings** (opens plugin's settings screen), enable switch, overflow menu: **Logs** (**Refresh**), **Reload**, **Enable**/**Disable**, **Remove** (confirm "Remove {{name}}?") (`i18n/resources/en.ts:2405-2466`).

### Project settings (see Projects section above)

File-backed `paseo.json`: worktree hooks, scripts, metadata generation prompts (`screens/project-settings-screen.tsx:100`).

## Providers, models & modes

Supported providers: Claude Code, Codex, GitHub Copilot, OpenCode, Pi, Antigravity, Muse Code (plus custom/ACP providers). In the UI a provider is a catalog row on the host's Providers page; a model is a selectable entry inside it.

- **Providers page** (Settings → host → Providers) — per-detected-provider rows: icon, name, status dot + text (**Available** / **Not installed** / **Error** / **Disabled** / "Loading…"), optional "· N models", enable **switch**, overflow menu **Remove provider** (custom/config-owned providers only); row opens the provider sheet (`screens/settings/providers-section.tsx:356`, `provider-selection/model-catalog.ts`).
- **Add provider** — catalog list with per-entry **Install** (installs the CLI on the host) (`screens/settings/providers-section.tsx`, `settings.providers.addProvider`).
- **Provider diagnostic sheet** — diagnostic text (copy), discovered models list (add/remove, **Add custom model…**, **Add model** with **Model ID** input), refresh, "No diagnostic available" state; opened from the Providers gear or the model browser gear (`components/provider-diagnostic-sheet.tsx`, `components/provider-settings-host.tsx`, labels `settings.providers.diagnostic.*` / `settings.providers.models.*` `i18n/resources/en.ts:3183-3230`).
- **Selecting provider/model/thinking/mode** — composer agent controls: provider badge → searchable **Select agent provider** combobox; model chip → model browser ("Search models...", **Profiles** section: "Create profile", "Create profile from this model", "Edit {{name}}"); thinking chip → **Thinking** combobox ("Select thinking option ({{value}})"); mode chip → **Mode** sheet ("Search modes..."); provider features → inline chips or an aggregated **Features** sheet ("Open agent features") (`composer/agent-controls/index.tsx:983-1098`, `components/model-browser.tsx`, labels `agentControls.*` `i18n/resources/en.ts:200-231`, `modelSelector.*` `i18n/resources/en.ts:1770-1797`).
- **Agent profiles** — named launch bundles (provider, model, mode, thinking, feature values, notes) stored host-wide; applying one fills the controls once, records nothing; Settings → host → Agents → **Agent profiles** to add (+) / edit (pencil) / reorder / delete; fields **Name**, **Icon** ("None"), **Provider**, **Model**, **Mode**, **Thinking**, **Features**, **When to use** notes ("Helps agents choose this profile…") (`agent-profiles/settings/agent-profiles-section.tsx:29`, labels `settings.host.agentProfiles.*` `i18n/resources/en.ts:3024-3059`; glossary "Agent profile").
- **Model browser "Profiles"** — applying a profile from the composer's model dropdown (`components/model-browser.tsx:723-938`).
- **Metadata generation model** — host setting for titles/branch names/commit messages/PR drafts (Settings → host → Metadata; see Settings).
- **Custom providers** — via config (custom binaries, Z.AI-style aliases, ACP agents); not a first-class UI, documented for daemon config (`docs/custom-providers.md` in the reference repo).
- **Modes** — icon-only chips; labels from provider metadata (e.g. plan/default/full-access); cycle with the shortcut "Cycle agent mode" (`settings.shortcuts.help.cycleAgentMode`).
- **Fast mode** — command-center and composer surfaces expose **Fast** on/off for providers that support it (`shell.commandCenter.fastModeGroupLabel` `i18n/resources/en.ts:108`).

## Permissions

Two distinct surfaces, both called "permissions":

- **Agent permission requests (in chat)** — when a provider asks before running a tool/plan/etc., an inline card renders in the timeline: title **Plan** (plan requests) or the request name or **Permission Required**; buttons **Deny** (danger) and **Accept** (primary) — or **Implement** for plans; detail block shows **Input**/**Output**; once answered the card collapses to **Approved plan** / **Rejected plan** / **Canceled plan**; question-kind requests render the question form instead ("How would you like to proceed?") (`agent-stream/view.tsx:1485-1558`, `components/question-form-card.tsx`, `components/plan-card.tsx`, labels `agentStream.permission.*` `i18n/resources/en.ts:237-248`).
- **Desktop OS permissions** — Settings → **Permissions** (desktop only): **Microphone** row with status **Granted** / **Request** (**Requesting…**) and a **Refresh** button; macOS prompt flows through the desktop bridge (`desktop/components/desktop-permissions-section.tsx:17`, labels `settings.permissions.*` `i18n/resources/en.ts:2848-2859`). Desktop also owns **Notifications** (see Notifications) with its own **Notification permission** row.
- Notification permission is separately requested on desktop at startup (`app/_layout.tsx` `ensureOsNotificationPermission`) and via Settings → Notifications.

## Notifications

- **Agent attention notifications** — when a turn finishes needing input (or fails/completes with attention), the app raises an OS notification (skips pure errors unless attention-flagged; skips while you're viewing that agent; dedupes); desktop shows a dock/taskbar badge count of attention-tagged workspaces (`contexts/session-context.tsx`, `utils/agent-attention.ts`, `utils/desktop-badge-state.ts`).
- **Terminal attention** — same pipeline for terminals waiting on the user (`terminal_attention_required` feed).
- **Notification tap → route** — tapping routes to the agent (pinned) or the workspace/terminal; waits for navigation readiness; dedupes ids (`notification-open/react/index.tsx:24`, sources `notification-open/source*.ts`, parser `notification-open/model.ts`).
- **Desktop notifications settings** — **Notification permission** (**Granted** / **Request**), **Play sound**, **Test notification** (**Send**; result toasts/alerts; "Play a sound when a desktop notification arrives") (`desktop/components/desktop-notifications-section.tsx:20`, labels `settings.notifications.*` `i18n/resources/en.ts:2376-2390`).
- **Expo push (native)** — registers an Expo push token per host (cached in AsyncStorage), handles Android "default" channel, refetches on reconnect; web is a no-op (`push-notifications/internal/subscriptions.ts:59`, `push-notifications/index.native.ts`).
- **OS notifications (desktop/web)** — helper over Electron IPC or the web Notification API; icon + click routing (`utils/os-notifications.ts:144`).
- **Sound** — the desktop notification plays a sound; the app also has a thinking tone in voice mode (see Voice).

Main source files: `push-notifications/`, `notification-open/`, `utils/os-notifications.ts`, `utils/agent-attention.ts`, `utils/desktop-badge-state.ts`, `contexts/session-context.tsx`, `desktop/components/desktop-notifications-section.tsx`, `desktop/components/desktop-permissions-section.tsx`.

## Voice & dictation

- **Voice mode** (realtime conversation) — mic-disc button in the composer (**Enable Voice mode**); when active, an overlay replaces the composer footer with a live volume meter, mute toggle (**Mute Voice mode** / **Unmute Voice mode**) and an interrupt **Square** stop; the agent hears you and speaks replies (**Listening** / **Speaking** providers); a thinking tone plays while the agent decides; stop button = **Stop realtime voice and interrupt turn** (`composer/index.tsx:1142`, `components/realtime-voice-overlay.tsx`, labels `composer.voice.*` `i18n/resources/en.ts:143-153`, `realtimeVoice.actions.*` `i18n/resources/en.ts:1996-2002`).
- **Dictation** — mic button starts dictation into the message box: overlay with timer, live volume meter, transcript, buttons **Cancel dictation** / **Insert transcription** / **Insert transcription and send** / **Retry dictation**; waiting states ("Microphone interrupted. Waiting to resume…", "Dictation failed. Tap retry."); mic turns red while recording; keyboard shortcut `dictation-toggle` (`components/dictation-controls.tsx`, `composer/input/input.tsx` dictation overlay, labels `message.dictation.*` `i18n/resources/en.ts:362-372`, `composer.voice.startDictation|stopDictation` `i18n/resources/en.ts:143-153`).
- **Voice settings** (Settings → host → Voice) — **Dictation** switch ("Speak into the message box instead of typing"); **Speech-to-text** row; **Voice mode** switch ("Talk with your agents hands-free"); **Listening** (STT) and **Speaking** (TTS) rows; each row opens the provider sheet (`screens/settings/voice/voice-page.tsx:43`, labels `settings.voice.*` `i18n/resources/en.ts:2482-2536`).
- **Speech provider sheet** — **Provider**: **Local** (language input "Auto-detect"; local model catalog with Download/Delete, sizes, **Downloaded** / **In use** / **Recommended** badges) or **OpenAI** (**API key** saved on host, **Base URL**, **Model** (whisper-1 for STT / tts-1 for TTS), **Language** or **Voice** (alloy, ash, coral, echo, fable, nova, onyx, sage, shimmer)); **Save** / **Cancel**; "Set by {{envVar}}" disables a field when an env override owns it (`screens/settings/voice/speech-provider-sheet.tsx`).
- **Diagnostics** — Settings → Diagnostics → **Test audio** (**Play test** / **Playing…**) (`screens/settings-screen.tsx:451-463`, labels `settings.diagnostics.testAudio`, `…playTest`, `…playing`).
- **Keep awake** — while voice mode is live the app holds a wake lock ("paseo:voice") (`voice/voice-runtime.ts`).

Main source files: `voice/voice-runtime.ts`, `contexts/voice-context.tsx`, `components/dictation-controls.tsx`, `components/realtime-voice-overlay.tsx`, `components/volume-meter.tsx`, `audio/`, `dictation/`, `screens/settings/voice/`, `hooks/use-dictation.ts`.

## Hosts & pairing

- **Add host** — sidebar footer **Hosts** picker → **Add host** (also the only option in an empty settings sidebar); "Add connection" sheet offers four methods: **Direct connection** ("Local network or VPN." — Host/Port/Password/Optional, **Use SSL** toggle, **Advanced** → **Connection URI**, actions **Connect**/**Connecting...**), **Remote SSH** (desktop only — "Connect through the desktop SSH client."; **SSH host**, **Daemon password**), **Scan QR code** (native — "Encrypted relay connection."), **Paste pairing link** ("Encrypted relay connection."; validates `#offer=` links; optional **Host password** prompt when the offer is protected) (`hosts/add-host/internal/add-host-method-modal.tsx:63`, `add-host-modal.tsx`, `pair-link-modal.tsx`, `scan.tsx`, labels `pairing.connectionMethods.*` / `pairing.direct.*` / `pairing.remoteSsh.*` / `pairing.link.*` `i18n/resources/en.ts:1851-1954`).
- **Pair device** (host settings → Pair device, label "Pair device") — generates the pairing offer: if relay is disabled, an upsell (**Enable relay**, "Relay lets this device connect from anywhere…"); if enabled: QR code + copyable pairing link (**Copy** / **Copied**) with "Treat this pairing link like a password…" warning; **Retry** on failure (`screens/settings/host-page.tsx:266`, `desktop/components/pair-device-section.tsx`, labels `openProject.tiles.pairDevice.*` / `pairing.pairDevice.*` `i18n/resources/en.ts:1637`, `:1968-1993`).
- **Host confirmation sheet** — on deep links/paste: "Connect to this host?" — host **Host**, **Key fingerprint**, **Relay** rows, **Connect** (or changed-link variant "This link changes how you connect to this host. …") (`hosts/host-confirmation-sheet.tsx:17-62`, labels `pairing.hostConfirmation.*` `i18n/resources/en.ts:1840-1850`).
- **Host picker** — **Switch host** dropdown in Settings (plus **Add host** / **Enable built-in daemon** when applicable); sidebar footer **Hosts** icon opens the same picker; **All hosts** option for filters; per-option gear "Open {{label}} settings" (`components/hosts/host-picker.tsx`, `components/hosts/host-filter.tsx`, labels `settings.hostPicker.*` / `settings.addHost` `i18n/resources/en.ts:2300-2303`).
- **Host chooser** — searchable modal used by deep-link flows and "Choose host" (for open-project, import) — local-first order, **No matching hosts** empty, keyboard navigation (`hosts/host-chooser.tsx`).
- **Host settings** (Settings → host) — per-host pages for Overview (rename, color, sidebar badge, built-in daemon, restart, update, remove), Connections (latency rows, remove), Pair device, Agents, Metadata, Voice, Workspaces, Providers, Usage, Terminals, Plugins (see Settings). Rename host modal: **Rename host** (`screens/settings/host-appearance-section.tsx`, label `host.daemon.rename.*` `i18n/resources/en.ts:3061-3066`).
- **Built-in daemon** (desktop) — desktop app manages a local daemon: **Manage built-in daemon** toggle, **Keep running after quit** toggle, status, logs (**Open logs** / **Copy path**), **Full status**, stop-on-quit overlay ("Quitting Paseo..."/"Stopping the local daemon."), rosetta callout, **Enable built-in daemon** option in pickers (`desktop/components/desktop-updates-section.tsx:316`, `app/_layout.tsx` `shouldStartBuiltInDaemon`, labels `desktop.daemon.*` `i18n/resources/en.ts:1442-1502`).
- **Welcome screen** — first run: "Welcome to Paseo" + connection method tiles (**Scan QR code** / **Direct connection** / **Paste pairing link** / **Remote SSH** on desktop; **Settings**) (`components/welcome-screen.tsx:162`, labels `onboarding.title`, `pairing.connectionMethods.*`).
- **Onboarding** — desktop first-run modal, step rail: **Appearance** ("Welcome to Paseo" — pick a look), **Providers** ("Your agents" — "Paseo runs the agent CLIs already on this computer"), **Projects** ("Add your projects" + recent-folder suggestions with **Add N project(s)**), **Orchestration** ("Let agents use Paseo" — Enable Paseo tools / orchestration skills / CLI switch), **Mobile** ("Take your agents with you"; **Relay** recommended, **Tailscale**; store links); **Skip setup** / **Finish**; step counter "Step {{current}} of {{total}}"; never opens on phones (`onboarding/internal/onboarding-modal.tsx`, steps in `onboarding/internal/steps/`, labels `onboarding.setup.*` `i18n/resources/en.ts:1709-1760`). Re-open from Settings → General (**Show setup again**).

Main source files: `hosts/`, `components/hosts/`, `hosts/add-host/`, `desktop/components/pair-device-section.tsx`, `desktop/components/desktop-updates-section.tsx`, `desktop/daemon/`, `onboarding/`, `components/welcome-screen.tsx`, `navigation/host-runtime-bootstrap.ts`, `runtime/host-runtime.ts`.

## Plugins

Local plugins extend the app: sidebar items/views, workspace panels, file panels, themes, settings screens, slash commands, timeline renderers, usage sources, command-center entries.

- **Plugins page** (Settings → host → Plugins) — warning "Plugins are trusted code" ("They run on this host and inside the app without sandboxing. Install only code you trust."); global **Enable plugins** switch ("Global switch for every configured plugin"); install box: **Plugin source** input ("owner/slug, directory, Git URL, or npm package") + **Install plugin**; per-plugin rows: name, status badge (**running** / **disabled** / **failed**), description, source, Settings gear (only when the plugin declares settings screens), enable switch, overflow menu (**Actions for {{name}}**): **Logs** (**Refresh**, "No plugin output yet"), **Reload**, **Enable**/**Disable**, **Remove** (confirm "Remove {{name}}?", "This removes the configuration. The source directory is not deleted."); empty states "No plugins configured", "Plugin host is offline", "Update this host to manage plugins" (`screens/settings/plugins-page.tsx:269`, labels `settings.plugins.*` `i18n/resources/en.ts:2405-2466`).
- **Plugin settings screens** — opened from the plugins page; route `/settings/hosts/[serverId]/plugins/[pluginId]/[screenId]`; screens declared by the plugin render as tabs when ≥2; error states "This plugin settings screen is unavailable." / "Connect to this host to open plugin settings." / "Update this host to use plugin settings."; **Back to plugins** (`app/settings/hosts/[serverId]/plugins/[pluginId]/[screenId].tsx:7`, `plugins/settings/index.tsx`, labels `settings.plugins.screens.*` `i18n/resources/en.ts:2407-2412`).
- **Plugin surfaces** — full-screen plugin surfaces (`/h/[serverId]/plugin/[pluginId]/[contributionKind]/[contributionId]`, `PluginSurfaceScreen`), used e.g. by usage dashboards; legacy `/[surfaceId]` route redirects (`app/h/[serverId]/plugin/[pluginId]/[contributionKind]/[contributionId].tsx:3`, `plugins/surface-screen.tsx`).
- **Plugin sidebar items** — header/footer rows contributed by plugins; reorder/visibility via Settings → Sidebar; a plugin item may render several rows; legacy items open a full-screen surface (`plugins/sidebar-items/`, `sidebar-nav/model.ts`).
- **Sidebar views** — a plugin can replace the whole sidebar ("Sidebar view" picker in Settings → Sidebar; failing view shows a fallback with **Use default view**) (`plugins/sidebar-view/`).
- **Plugin workspace panels** — file/panel surfaces as tabs; plugin file panels appear in **Open with…** and Settings → Files (`plugins/workspace-panels/panel.tsx`).
- **Plugin buttons** — **Plugin header buttons** in the workspace header, **Plugin composer pills** above the composer, **plugin workspace menu** pages in "Workspace actions" (`plugins/buttons/view.tsx`).
- **Plugin command-center entries** — registered as command-center groups per plugin (`plugins/command-center/registration.tsx`).
- **Plugin client slash commands** — appear in the composer's `/` menu tagged with the plugin name (`plugins/client-slash-commands/`).
- **Plugin themes** — theme tiles contributed by plugins (Settings → Appearance → Theme) (`plugins/themes/`, `appearance/theme-picker.tsx`).
- **Plugin usage sources** — registered daemon-side; reports appear in Usage surfaces (see Usage) (`usage/`, daemon-side `usage-sources`).
- **Catalog sync** — the app auto-syncs the host plugin catalog on `plugin_catalog_changed` (`plugins/catalog-sync.tsx`).

Main source files: `plugins/`, `screens/settings/plugins-page.tsx`, `components/settings/…`, `app/settings/hosts/[serverId]/plugins/`.

## Usage

- **Usage modal** — opens from the sidebar footer Usage icon/row; **Usage** title; host filter (multi-host), **Refresh all**, settings cog (**Settings** → **Check usage** (host policy, "Applies to {{host}} on every device"), **Summary in sidebar** ("Pinned windows show in the sidebar footer"), **Percentages** segmented **Used**/**Remaining**); body per host config (`usage/usage-modal.tsx`, `usage/usage-section.tsx`, `usage/options.tsx`, labels `providerUsage.*` `i18n/resources/en.ts:2216-2284`).
- **Report cards** — one card per source+account: source icon, plan badge, status dot, per-window meter rows (Session / Weekly / Monthly / Code review / Credits) with "resets in {{duration}}" countdown, balance rows, **Pin**/**Unpin** per window, "Updated {{relativeTime}}", per-card **Refresh** (`usage/card.tsx`).
- **Pinned windows** — pinned windows render in the sidebar footer as one-line meters (icon + percent); off by default until "Summary in sidebar" is enabled; "Usage" sidebar footer item hidden while no pinned window has data (`usage/sidebar-item.tsx`, `usage/pinned.ts`, `sidebar-nav/model.ts` HIDDEN_BY_DEFAULT).
- **Host settings → Usage** — the same section embedded per host, titled **Plan usage** (`screens/settings/host-page.tsx:349`).
- **Agent context usage** — the context-window meter's details sheet shows the usage card for the agent's account only (no pins) (`usage/agent-usage.tsx`, `components/context-window-details.tsx`).
- **Off state** — "Usage is off on {{host}}." with **Turn on** (Check usage host switch) (`usage/usage-section.tsx`, labels `providerUsage.off` / `providerUsage.turnOn`).

## Anything else (desktop & app shell)

- **Desktop window** — window chrome without classic title bars (macOS traffic lights integrated), drag regions, minimize/maximize/close, sidebar toggle in the window corner; **Focus mode** hides chrome for the workspace ("Exit focus mode"); **Quitting Paseo...** overlay while the local daemon stops (`components/desktop/`, `components/quitting-overlay.tsx`, `components/headers/sidebar-menu-toggle.tsx`).
- **Updates** — desktop auto-checks for updates; sidebar callout "{{version}} is ready to install." with **What's new** + **Install & restart**; Settings → About → **App updates** (**Check** / **Update to {{version}}**) and **Release channel** (**Stable** / **Beta**); **What's new** row opens the changelog (`desktop/updates/`, `screens/settings-screen.tsx:477-531`, labels `settings.about.*` `i18n/resources/en.ts:2657-2686`).
- **Rosetta callout** — non-dismissible error if running the Intel build on Apple Silicon (`desktop/updates/rosetta-callout-source.tsx`).
- **Download toast** — progress toast for file downloads ("{{percent}}% · {{speed}} · {{eta}}", "Download complete" / "Download failed") (`components/download-toast.tsx`).
- **Changelog** — "What's new" sheet: rendered release notes of this build (embedded CHANGELOG.md), **Full changelog** external link, per-version sections, **Show more** (`changelog/`, mounted `app/_layout.tsx:570`).
- **App diagnostic** — Settings → Diagnostics → **Run** produces a copyable report (client/hosts/desktop/logs) (`components/app-diagnostic-sheet.tsx`, mounted `app/_layout.tsx:569`).
- **Keyboard shortcuts dialog** — "Shortcuts" overlay (Shift+? or menu / command center) listing every binding grouped General / Projects & Workspaces / Tabs & Panes / Layout / Agent Input, with **Not set** for cleared ones (`components/keyboard-shortcuts-dialog.tsx`, labels `settings.shortcuts.dialogTitle` / `settings.shortcuts.sections.*`).
- **Help and support** — sidebar footer menu (**Help and support**): **Keyboard shortcuts**, **What's new**, **Run diagnostics**, **Report an issue** (**Discord** / **Create GitHub issue**), plus version rows; community links (**Star** / **Sponsor** / **Community**) on Home and Settings → About (`components/sidebar/sidebar-help-menu.tsx`, `components/community-links.tsx`, labels `sidebar.help.*`).
- **Workspace pinning** — pin a workspace to the sidebar top (**Pin to top** / **Unpin**); global shortcut (`components/workspace-pin-shortcut-handler.tsx`, label `sidebar.workspace.actions.pin`).
- **Pin / rename / archive-undo shortcuts** — global keyboard handlers for pin, rename, undo-archive (`components/workspace-rename-host.tsx`, `workspace/archive-undo/`).
- **Import session** — "Import session" (header menu / command center / Home tile): import external CLI sessions (Claude Code, Codex, …) from a host into an agent tab (`hooks/use-import-session.tsx`, labels `importSession.*` `i18n/resources/en.ts:419-435`).
- **Home screen** — **Add a project**, **Import session**, **Setup providers**, **Pair device** tiles (desktop local daemon only) + community links (`screens/open-project-screen.tsx:27`, labels `openProject.tiles.*` `i18n/resources/en.ts:1622+`).
- **Startup splash** — startup screen with retry on managed-daemon failure ("My local daemon failed…" states) (`screens/startup-splash-screen.tsx`).
- **Attention rings** — workspace rows/tab chips show status rings for running/attention/failed states (`components/status-ring/`, `screens/workspace/workspace-tab-presentation.tsx`).
- **Provider settings host / worktree setup dialog / add-project flow / add-host flow** — global modal hosts mounted in the root layout (`app/_layout.tsx:532-576`).


Verified: 243 citations checked, 40 corrected
