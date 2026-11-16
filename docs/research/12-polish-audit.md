# 12 · Polish audit

Branch `p1-polish-audit`, 2026-11-09. Scope: `App/Sources` and every screen in
`Packages/PaseoUI/Sources/PaseoUI` (127 Swift files). Read-only review of the code plus the
ClaudeUI/DSH specs (`06-dsh-ux-spec.md`, `08-dsh-live-observation.md`) and upstream Paseo's
`packages/app/src/i18n/resources/en.ts`. No simulator, no screenshots.

The brief is pinned: cream, serif titles, the Claude accent, `ClaudePalette`/`ClaudeTypography`/
`ClaudeMotion`, 0.5 pt dividers, DSH Claude behavior. This audit does not propose a new palette,
typeface or look. It asks one question: **where does the app stop feeling like one Claude app?**

> **Lead note (2026-11-09):** the blue accents and system fonts in Settings/Welcome/sheet rows are
> ClaudeUI's own (the import `188a168` uses `.tint(.blue)`, blue checkmarks and `.system(size:)`
> throughout its settings: it mirrors the Claude iOS app). Pinned style wins, so the blue→orange
> and system→ClaudeTypography swaps were reverted on merge. The gray (`secondary` → adaptive
> `secondaryInk`) and the rest of the fixes stay. Finding 1's token pass is on hold for the user.

## Verdict

The chat surface and the workspace panel are the best-built parts of the app. The transcript,
turn grouping, permission card, composer and workspace setup sheet already feel deliberate and
calm. The weak seam is the Settings family: it is the one area that still looks like a generic
iOS settings screen dropped into a Claude app (fixed-size system fonts, a second gray, raw blue
accents). The second seam is chrome duplication: several standalone screens have hand-rolled
headers that do not match the shared `SheetHeader`, and six screens have their own toast.

The problems are mostly systemic, not per-screen invention. Fixing four foundations (settings
tokens, one header, one toast, one 44 pt hit-target rule) removes most of the remaining
inconsistency.

## Ranked findings

Each finding lists evidence, what is wrong, why it matters, the fix, risk and category. Status is
either **fixed** in this branch or **proposal** (medium/high risk, needs a visual pass in Xcode).

### 1. Settings is not built from ClaudeStyle — consistency, accessibility · medium

**Evidence**
- 179 fixed-size `.font(.system(size:))` calls in `Chat/PaseoSettingsView.swift` +
  `Settings/` (e.g. `PaseoSettingsView.swift:158,361,368`,
  `HostsPage.swift:24,40,73`, `AgentProfilesSection.swift:31,72,95`,
  `ProjectSettingsView.swift:262,381`, `ClaudeSheets.swift:43-64`).
- 88 `ClaudePalette.secondary` references in the same family (a flat gray) instead of the
  adaptive `secondaryInk` (e.g. `HostsPage.swift:25,41`, `AgentProfilesSection.swift:31`).
- Raw blue (before this branch): `PaseoSettingsView.swift:324,330,391,400,411,483,1290` (the
  appearance tiles and every switch), `SidebarPage.swift:80`, `WelcomeView.swift:185,192`, plus
  the blue checkmark in the shared `SheetRow` (`ClaudeSheets.swift:63`).
- `SheetRow` used a hard-coded `Color(white: 0.72)` for every settings row symbol
  (`ClaudeSheets.swift:42`), which ignores light/dark and pure black.

**What is wrong.** The settings screens use the old generic row kit, not the roles the rest of
the app uses. Fixed point sizes do not scale with Dynamic Type; `secondary` is tuned for one
appearance; blue is not the Claude accent.

**Why it matters.** Settings is where a user changes the app's appearance. If that screen looks
like a different app, the illusion that this is one Claude client breaks exactly where the user
is paying the most attention. Fixed sizes also exclude larger accessibility text sizes.

**Fix.** Convert the settings family to `typography.sans/serif` roles and palette tokens, in one
pass, with an Xcode visual check. Replace `.tint(.blue)` with `ClaudePalette.orange` (or the
`Toggle` default tint if the team decides switches should stay system). Keep frames as
`minHeight`, not fixed `height`, so text can grow.

**Done here:** the Claude accent on the appearance tiles and every visible switch in General, the
Sidebar page tint, the shared `SheetRow` colors and checkmark, the Context sheet, and the Welcome
appearance sheet.
**Still open:** the bulk of `PaseoSettingsView`, `HostsPage`, `TerminalPage`,
`AgentProfilesSection`, `AgentProfileEditSheet`, `ProjectSettingsView`, `ProviderDetailSheet`,
`DiagnosticsPage`, `HelpMenu`.

**Risk.** Medium: many small visual changes across Settings; needs one Xcode pass in light, dark
and a large Dynamic Type size.

### 2. Two sheet-header grammars — consistency, hierarchy · medium

**Evidence**
- Shared sheet header: `ClaudeSheets.swift:8-22` — sans 17 semibold, 58 pt row, 42 pt glass
  circle, used by Add project, Context, Usage, Forge search, Import, New workspace, Commit,
  Create PR, Setup, project/script/provider sheets.
- Schedules/History/Search: `SchedulesListPage.swift:42-53`, `ClaudeHistoryView.swift:140-153`,
  `CommandCenterView.swift:147-160` — serif 19 semibold, 56 pt row, 42 pt circle.
- Settings: `PaseoSettingsView.swift:156-198` — sans 17 semibold, 44 pt row, 44 pt circle,
  refresh button on every subpage.

**What is wrong.** The same kind of modal has three title typefaces, three row heights and two
control sizes. `SheetHeader` is the majority, but it is the one that does not use the serif title
role the brief names.

**Why it matters.** A sheet's header is the strongest signal of "this belongs here". Right now
opening Schedules feels like Claude; opening New workspace feels like the old app. Users do not
name it, they just feel the seam.

**Fix.** Make `SheetHeader` the only header: serif 19 (`typography.serif(19, relativeTo: .headline,
weight: .semibold)`), 44 pt control diameter, 56 pt row. Then delete the three hand-rolled
headers and use it from Settings, Schedules, History and Search.

**Risk.** Medium: touches every sheet; title truncation (`titleMaxWidth: 200`) and the Settings
refresh button need a layout check.

### 3. Hit targets under 44 pt — accessibility · medium (individually low)

**Evidence.** 70 sub-44 frames in icon/row controls. High-traffic examples:
- Queue row actions 30×30 in a 32 pt row: `Conversation/ChatQueue.swift:55,66,72`.
- Find bar arrows 26×30, close 30×30: `Chat/ClaudeFindBar.swift:74-90,99`.
- Permission buttons 36 pt: `Chat/ClaudePermissionCard.swift:269`.
- Composer model chip 36 pt: `Conversation/ChatComposer.swift:129,300`.
- Workspace page switcher 32 pt: `Workspace/WorkspacePanel.swift:306-325`.
- File viewer toolbar 28×28: `Workspace/WorkspaceFileViewer.swift:300-360`.
- Turn actions 28×28: `Conversation/ChatTurns.swift:226`, `Workspace/WorkspacePRPane.swift:273`.
- Turn rail 26×26: `Conversation/ChatTurnRail.swift:49`.
- Project script plus 30×30: `Settings/ProjectSettingsView.swift:468`.

**What is wrong.** The visual sizes are part of the pinned DSH density. The problem is that the
*touch* area is the same as the visual area.

**Why it matters.** Apple's floor is 44×44 pt. A 30 pt pencil in a queue row is a miss waiting to
happen, especially one-handed or with motor impairment.

**Fix.** Keep the visual circle, add a transparent 44 pt frame and `.contentShape(.rect)` (as done
for the composer expand and back-to-end controls). For rows that are already ≥44 pt (schedule
rows), add `.contentShape(.rect)` to the row so the whole row is tappable.

**Done here:** composer expand control (`ChatComposer.swift:249-257`) and transcript
back-to-end (`ChatTranscript.swift:408-415`) now have 44 pt targets without moving the visible
circle. **Still open:** the rest above, as a mechanical pass.

**Risk.** Low per control; medium in aggregate because enlarging targets can overlap neighbours
(queue row, find bar, file toolbar). Check each in Xcode; do not blindly add 44 pt frames to the
turn rail (buttons are 6 pt apart and would overlap).

### 4. Six toast implementations, three durations, two positions — consistency, bloat · medium

**Evidence**
- Sidebar: top toast at `padding(.top, 58)`, 1.5 s — `PaseoSidebar.swift:263-276`,
  `SidebarToasts.swift:124-128`.
- Schedules: bottom toast at 18 pt, 2.5 s — `Schedules/ClaudeSchedulesView.swift:100-121`.
- Files: bottom 18 pt, 2 s — `Workspace/WorkspaceFilesView.swift:529-546`.
- Terminals: bottom 18 pt, 2 s — `Workspace/WorkspaceTerminalsView.swift:194-211`.
- Changes: 2 s — `Workspace/WorkspaceChangesView.swift:1336-1342`.
- Composer: 2.5 s — `Conversation/ChatComposer.swift:447-451`.
- File viewer flash: 1.5 s, not a toast — `Workspace/WorkspaceFileViewer.swift:120-126`.

**What is wrong.** Same "message + optional undo" pattern reimplemented six times. Placement and
duration disagree; all respect Reduce Motion now, but only after six separate fixes.

**Why it matters.** Toast position is learned. A message that appears at the top in the sidebar
and the bottom in Files reads as two different apps. It is also six places to fix a timing or
VoiceOver bug.

**Fix.** One `ToastHost` view/modifier: bottom above the safe area (or top for the sidebar if that
is deliberate), 2 s default, `accessibilityReduceMotion` aware, one announcement path, optional
undo trailing button. Delete the five copies. Keep the sidebar's archive toast separate only if
its 5 s undo genuinely needs a different policy.

**Risk.** Medium: touches multiple screens; the sidebar's top placement may be intentional
because the bottom is occupied by the composer/panel. Confirm with the user first.

### 5. Empty and error states are uneven — state · low

**Evidence**
- Good: `Workspace/WorkspaceFilesView.swift:466-500` (reason + retry), `WorkspaceChangesView.swift:
  596-620` (message + retry), `Settings/ProjectSettingsView.swift:176-205` (title, message,
  retry), `Schedules/SchedulesListPage.swift:154-180` (icon, serif title, one line of direction,
  New schedule).
- Weak: History's failed state was a message and a button but no title
  (`Chat/ClaudeHistoryView.swift:229-260`, now has the upstream "Couldn't load agent history"
  title); History's loading state is a spinner + "Loading history…" (`:224-228`), which is
  acceptable once the label exists.
- Weak: Workspace panel's loading page was a bare `ProgressView` with no label
  (`Workspace/WorkspacePanel.swift:377-382`, now labelled).
- Weak: several failures end in a raw daemon string; `ProjectSettingsView.swift:186` used
  "Unknown error" (now "Something went wrong. Try again.").
- Weak: Usage sheet's failed state has no retry (`Chat/ClaudeUsageReportsSheet.swift:56-66`,
  M14 owns it).
- Weak: empty search results are not always distinguished from empty data; History now does
  ("No sessions yet" vs "No sessions match"), Schedules has one empty state only.

**What is wrong.** The pattern exists but is not applied everywhere: some states direct the user,
some just report.

**Why it matters.** An empty screen is a question the user cannot answer. "No sessions yet" is a
fact; "Start one from the sidebar" is the answer.

**Fix.** Adopt the Schedules/ProjectSettings shape as the house pattern: icon, one-sentence title,
one line of direction, one action if an action exists. For failures: what happened + Retry. Never
ship a spinner without a label.

**Done here:** History failed-title, empty/loading copy and 44 pt Retry; Changes Retry;
Workspace panel loading label; Project Settings copy. **Still open:** Usage sheet (M14), other raw
error strings.

**Risk.** Low; copy and one button style.

### 6. All-caps labels use two different systems — consistency, copy · low

**Evidence**
- Sidebar/Command Center: 12 pt semibold, no tracking, `.textCase(.uppercase)` —
  `Sidebar/SidebarDirectory.swift:6-10`, `Sidebar/CommandCenterView.swift:237-240`.
- History/Schedule detail/editor: 11 pt semibold, tracking 0.8, manual `.uppercased()` —
  `Chat/ClaudeHistoryView.swift:289`, `Schedules/ScheduleDetailPage.swift:140`,
  `Schedules/ScheduleEditorPage.swift:219`.
- Settings section labels are sentence case — `PaseoSettingsView.swift:361,379`.

**What is wrong.** The same structural device (a section label) has two sizes and two tracking
values, and Settings opts out entirely.

**Why it matters.** All-caps is a strong "this is a label, not content" signal. Two treatments
make the History sheet feel like a different hierarchy from the sidebar.

**Fix.** Pick one caption role (`typography.sans(11, weight: .semibold)` + tracking 0.8 is the
more Claude-like of the two) and use it for every section label. Or drop the caps and use sentence
case everywhere; the brief says sentence case for copy, and caps are a hierarchy decision. Do not
keep both.

**Risk.** Low, but a global visual change; confirm the direction before applying.

### 7. Process rows are below HIG density — accessibility · medium

**Evidence.** `Conversation/ChatWorkGroup.swift:237-264`: step rows are 24 pt (tool) or 36 pt
(other), the group summary is 17.5 pt. `Chat/ClaudeChatComponents.swift:116` uses 28×28 for a
control inside a row.

**What is wrong.** DSH's dense work log is deliberate, but rows are interactive and smaller than
44 pt.

**Why it matters.** The transcript is the most-used screen; the work log is where a user taps to
inspect a tool call. Small rows are hard to hit and hard to read at large text sizes.

**Fix.** Keep the visual density (the brief pins it), but give each row a 44 pt hit area with
`contentShape` and `minHeight`, or make the entire group header the hit target and leave step
rows read-only. Do not simply double the row height; that would lose the DSH rhythm.

**Risk.** Medium: layout in the transcript; needs an Xcode pass.

### 8. Settings copy still names implementation — copy · low

**Evidence**
- "This daemon cannot create workspaces." — `Sidebar/PaseoSidebar.swift:485`.
- "Setting an icon needs a host with projectCustomIcon support." — fixed to "This host can't set
  project icons." (`Settings/ProjectSettingsView.swift:380`).
- "The host reports no usage sources for this device." — `Chat/ClaudeUsageReportsSheet.swift:70`
  (M14).
- "Requires `automation.manage`" / "true push … without a relay" — Help/Diagnostics, e.g.
  `Settings/DiagnosticsPage.swift` and `Settings/HelpMenu.swift` (read-only here).
- "Unknown error" — fixed.

**What is wrong.** Some strings name the host protocol, a capability key or a config field
instead of the user's situation.

**Why it matters.** "projectCustomIcon" is not a thing a user can act on. "This host can't set
project icons" is. The brief allows fixing our own/system-shaped copy, but not replacing upstream
wording; each remaining string needs a check against upstream `en.ts` before changing.

**Fix.** Keep upstream strings as-is. For host-capability failures, translate to "This host
can't …" and link to Help if there is a real next step. Do not rename daemon/protocol terms that
upstream uses.

**Risk.** Low per string; needs product judgment on which terms are intentional.

### 9. Duplicated controls and a crowded Files toolbar — bloat, hierarchy · medium

**Evidence**
- Files toolbar has New file/folder, an overflow menu, and pull-to-refresh. The overflow menu also
  had "Refresh"; removed in this branch (`Workspace/WorkspaceFilesView.swift:277-285`). The header
  still has a separate refresh control and the list has `.refreshable`
  (`WorkspaceFilesView.swift:373`).
- File viewer toolbar: back, filename, preview/source, edit, overflow (28 pt controls) —
  `Workspace/WorkspaceFileViewer.swift:300-360`.
- Panel page switcher has three text segments in 32 pt and no close control
  (`Workspace/WorkspacePanel.swift:306-325`).
- "Copy agent ID" appears in the header menu, the Context sheet and the agent controls sheet.
- Transcript search is only reachable from the title menu; no visible affordance
  (`Conversation/ChatHeader.swift:60-80`).

**What is wrong.** Removing is often the fix. The Files header carries four ways to do two jobs
(refresh, create) and the panel has no obvious way out.

**Why it matters.** A toolbar with four icon-only controls at 28 pt is hard to scan and hard to
hit. Hidden search means users do not know it exists.

**Fix.** One refresh path per screen (pull-to-refresh; keep the header refresh only if it is the
primary affordance on a non-scrollable error state). Add a close control to the panel header.
Promote search to a visible magnifier next to the title menu. Keep Copy agent ID in one place
(the Context sheet is the natural home).

**Done here:** removed the duplicate Refresh menu item. **Proposal:** the rest.

**Risk.** Medium: navigation/affordance changes; needs the panel owner's sign-off.

### 10. Motion coverage is complete outside M14 — motion · low

**Evidence.** 48 `withAnimation` calls. Every file that animates content has an
`accessibilityReduceMotion` branch except `ConnectView.swift`, which M14 owns. Verified here:
- follow indicator `Conversation/ClaudeChatView.swift:219`
- terminal toast `Workspace/WorkspaceTerminalsView.swift:208-212`
- file preview segment and reveal scroll `Workspace/WorkspaceFileViewer.swift:462-469`,
  `Workspace/WorkspaceFilesView.swift:373-379`
- Settings page slide `Chat/PaseoSettingsView.swift:203-210` already branches on Reduce Motion
- transcript reveal/back-to-end/jump scrolls `Conversation/ChatTranscript.swift:285-291,
  394-400, 452-457` already branch
- Home hero rise `Chat/ClaudeHomeHero.swift:117,148-157` already branches

**What is wrong.** Nothing outstanding outside M14. The risk is regression: new animation code
should copy the `reduceMotion ? nil : …` form, not plain `withAnimation`.

**Why it matters.** Reduce Motion is an accessibility setting, not a preference. The rule should
be mechanical, not per-screen memory.

**Fix.** Keep the pattern; add the guard to `ConnectView.swift:334` under M14. Do not add checks
to pure opacity fades.

**Risk.** Low.

### 11. Brand casing and forge names were wrong — copy · low

**Evidence.** `Workspace/WorkspacePRPane.swift:194` built "Open on \(forge)" with
`(status.forge ?? "github").capitalized`, producing **"Open on Github"**. The same file uppercases
unknown review states at `:82,98,516`. Forge search rendered `#-1` when an item had no number
(`Chat/ForgeSearchPicker.swift:234`).

**What is wrong.** `.capitalized` is not a brand-name formatter. A missing number is not `-1`.

**Fix.** Map known forges to GitHub/GitLab; fall back to `.capitalized` only for unknown values.
Omit the number when nil.

**Done here.** Both fixed. **Why it matters.** "Github" is the kind of small wrongness that makes
a polished app feel un-reviewed; `#-1` looks broken.

**Risk.** Low.

### 12. VoiceOver order and labels are good in chat, thin in lists — accessibility · low

**Evidence**
- Good: `Chat/ClaudePermissionCard.swift:503` uses `.isSelected`; `EffortLadder.swift:75,136`
  same; sidebar rows expose collapsed/expanded (`SidebarProjectGroup.swift:54`,
  `SidebarDirectory.swift:109`).
- Fixed here: agent menu now reads its title (`ChatHeader.swift:67`); file rows include size/date
  (`WorkspaceFilesView.swift:461-468`); schedule rows include cadence and next run
  (`SchedulesListPage.swift:133`); workspace pages use `.isSelected`
  (`WorkspacePanel.swift:323`); the composer attachment pill and its remove button are now
  separate elements (`Chat/ComposerAttachments.swift:194-203`).
- Still thin: turn rail labels are "Jump to message N" (fine) but the rail itself has no
  container label; the find bar's result count is not announced.

**What is wrong.** Labels exist where the action is simple, but composite rows sometimes collapse
into one label that omits state, or expose an unlabeled image.

**Why it matters.** VoiceOver users need the same information the eye gets: which attachment,
which schedule state, which page is selected.

**Fix.** For composite rows, one element with label + value; for pickers, `.isSelected`; for
images inside buttons, hide the image and label the button. Add a `.accessibilityLabel("Message
navigation")` to the rail and announce find result counts.

**Risk.** Low; verify with VoiceOver in Xcode.

## Screen-by-screen notes

Short notes for screens not covered above. "OK" means it matches the brief and needs no change.

### App shell

- `App/Sources/RootView.swift`: welcome gating and session ownership are clear. OK.
- `PaseoShellView.swift`: sidebar + panel split uses `ClaudeDivider`; the edge drawer is
  deliberate. The main-area error line sits at the bottom with no Retry
  (`PaseoShellView.swift:224-233`); treat it like other failures.
- `PaseoClientApp.swift`: no UI findings.

### Sidebar

- Row hierarchy (project → workspace → agent) is carried by indentation and 0.5 pt dividers, not
  boxes. This is the best structural pattern in the app; keep it.
- `Scheduled` was renamed to `Schedules` to match upstream (`PaseoSidebar.swift:315`, upstream
  `en.ts:1292`).
- Empty-project/empty-workspace toasts were rewritten to sentence case and to say what to do
  (`SidebarProjectGroup.swift:94`, `SidebarWorkspaceRow.swift:97`).
- Plus buttons are 24×24/30×30 (`SidebarProjectGroup.swift:14,58`); see finding 3.
- Two clock metaphors: Schedules uses `clock`, History uses `clock.arrow.2.circlepath`
  (`PaseoSidebar.swift:315,318`). Acceptable, but if Schedules becomes a list it should use a
  calendar/clock that survives.
- The archive undo toast is the one place a 5 s timeout and a bottom placement are justified
  (`PaseoSidebar.swift:276-303`).
- Usage footer is quiet and does not compete. OK.

### Command Center / search

- Serif "Search" title, focused field, grouped results. Good.
- Section headers use 12 pt caps while History uses 11 pt tracked caps (finding 6).
- Result rows carry icon + title + subtitle; labels are present. The empty state already names
  the query ("No results for “x”") and distinguishes "No recents yet"; good.
- The search field is a capsule inside a rounded container; History's field is a rounded rect
  (`CommandCenterView.swift:145-180` vs `ClaudeHistoryView.swift:160-180`). One shape per control
  type.

### Chat header and transcript

- Title menu (rename/archive/search) is the right Claude pattern, but search is invisible
  (finding 9). The menu label now includes the agent title.
- Connection banner says "Attempt N" and offers no action
  (`Conversation/ChatHeader.swift:180-188`). Replace with "Reconnecting…" and a Retry only if the
  host allows a manual reconnect.
- Back-to-end: 44 pt target fixed; visible circle is unchanged.
- Turn rail: numbered rail only for ≥4 turns is excellent structure-as-information. Its 26 pt
  marks are a known touch-target compromise (finding 3).
- Work groups: summary + expandable card is the best density/legibility trade in the app. The
  count chip ("3 steps") earns its place; do not add more chrome.
- "Turn complete." was vague; now "This turn ended without a reply." Only shown when a turn has
  no prose, which is honest.
- User bubbles keep the context menu and a single timestamp; no extra metadata. Good.

### Composer

- One input, one send/mic control, attachment tray, model chip, fast-mode chip. Good.
- The dictation-denied banner now uses the type roles; its "Settings" action deep-links to
  Settings. Good.
- Expand control is a 44 pt target now; check the hit area does not overlap the send button at
  narrow widths.
- Queue rows expose edit/send-now at 30 pt (finding 3); the row itself is 32 pt
  (`ChatQueue.swift:72`).
- Attachment remove button has a label; the pill and remove action are now separate VoiceOver
  elements. Good.
- `actionError` is inline red text with a 13 pt role; good, but it has no Retry (errors here are
  usually send failures; the composer draft is preserved, so retry is the send button).

### Permission card

- Best-in-app hierarchy: question header, one-line context, options with selection state,
  Other, Decline. Buttons are 36 pt (finding 3).
- Raw tool names appear in the "Allowed: tool" line; that is the protocol, not user language.
  Keep if upstream does; otherwise say "Allowed for this request".
- The card used `Divider()` (1 pt) at `ClaudePermissionCard.swift:197,205,415`; now
  `ClaudeDivider` for the pinned 0.5 pt hairline.

### Sheets

- `SheetHeader`, `SheetRow`, `RowGroup` are the shared kit. `SheetRow` now uses palette tokens;
  `RowDivider` now uses `ClaudeDivider`.
- New agent, Add project, Import session, Setup, Commit, Create PR all use the shared header and
  one primary action. Good.
- Import session has "Show all" with no way back to the filtered list
  (`Chat/ImportSessionSheet.swift` around the toggle). If "Show all" is a filter, make it a
  toggle; if it is navigation, add Back.
- Forge search: placeholder token fixed; selected state now exposed; `#-1` fixed. The auth
  callout is a good example of "what happened, how to fix it" (install/auth commands).
- Setup sheet: copyable command, single Done. Best error/empty handling in the app.
- Context sheet: token roles and adaptive gray now; still a dense table, but appropriate for a
  diagnostic sheet.
- Agent controls: many rows, each with a value and chevron; good. It still uses the generic
  secondary gray in places; covered by finding 1.
- Usage sheet: M14 owns it; see excluded section.

### Workspace panel

- Page switcher (Changes/Files/Terminal) is text, not icons, and uses `.isSelected` now. Good.
  Height 32 and no close control are the open issues (finding 9).
- Empty agent list: "No agents in this workspace yet." sits under New agent/Import rows; the
  order already answers the empty state. Good.
- Loading page now has a label; do the same for any other bare spinner.
- The panel's setup line ("3 checks need attention. Opens setup details.") is a strong
  structure-as-information pattern. Keep.

### Files

- Directory list: name, size/date, icon; row label now includes the meta. Good.
- Toolbar has new file/folder, overflow, refresh and pull-to-refresh; remove one more (finding 9).
- Empty state names the path and offers New file; good.
- Error state now has a 44 pt Retry in Changes, but Files' own retry is still 32 pt
  (`WorkspaceFilesView.swift:516`). Align.
- Long-press context menu (copy path, new file/folder) is consistent with sidebar long-press.
  Good.

### File viewer / diff

- Preview/source segment, edit mode, save/discard, conflict alert, image/text/binary branches.
  This is the most complete screen. Keep.
- Toolbar at 28 pt is the main issue (finding 3); the visible icons are right.
- `TextEditor` uses a fixed monospaced size; check Dynamic Type in Xcode (code only).
- Markdown preview uses the shared markdown view; no new styling. Good.
- Diff view: line numbers and +/- colors are pinned; review-comment sheet uses the shared header.
  OK.

### Changes / PR

- One adaptive primary action (Commit → Push → Create PR) is the right hierarchy; the sheet says
  "Create pull request" while the button says "Create PR", matching upstream (`en.ts:838`).
- "Open on GitHub/GitLab" fixed (finding 11).
- Checks row summarizes failing/running/passed; good density. It exposes three numbers, no
  progress bar; acceptable.
- PR empty state directs to Create a pull request; good.
- Forge status letters (A/M/D/R) have no legend. Check in Xcode whether each row speaks the
  letter; add a legend only if the diff is the primary surface.

### Terminal

- Close dialog now matches upstream: "Close terminal?" / "Any running process in this terminal
  will be stopped immediately." (`WorkspaceTerminalsView.swift:124-133`; upstream
  `en.ts:730-731`). The destructive button already said "Close terminal".
- Terminal chips/toolbar at 30-32 pt; same hit-target rule (finding 3).
- Keyboard accessory uses raw colors that predate ClaudePalette; out of the pinned style but
  functional. Flag for a follow-up, not this ticket.

### Schedules

- Empty state now reads as a title + direction + New schedule, with serif title (finding 5).
- Row now announces cadence and next run; good.
- Detail screen uses a status pill + next-run line; section labels are tracked caps (finding 6).
- Editor uses a form-like list with one primary Save; good.
- "Interval cadences can't be edited here yet" is honest but a dead end. If editing is supported
  upstream, link to the upstream editor behavior; otherwise say "Create a new schedule to change
  the cadence."
- Polling on a timer is invisible; refresh control exists. Fine.

### Settings

- Top finding. The information architecture (root list → subpage, back/refresh in the header) is
  understandable, but the visual kit is the old one.
- General page switches all had blue tint; now Claude accent. Good.
- Appearance tiles are duplicated in Welcome; see proposals.
- Hosts page copy is long but useful; "Keychain" and "this device" are clear.
- Project settings: icon capability copy and "Unknown error" fixed; "Try again" renamed "Retry"
  for action-name consistency.
- Diagnostics/Help: the most jargon-heavy screens. They are for debugging, so some protocol
  language is legitimate; the rule is "user-facing first sentence in plain words, details below".
- Search in Settings: no search field. With ~8 pages and dozens of rows, a search would help, but
  it is a new component; proposal only.

### Welcome / connect

- Welcome's button said "Settings" but opened an Appearance sheet; renamed "Appearance" with a
  half-circle symbol. This is the one place a user could be misled about what a control does.
- The sheet duplicates the Appearance section of Settings (tiles + scale + motion). See
  proposals.
- Direct connection wording is upstream; keep.
- ConnectView is M14-owned; see excluded.

## Best screens (copy these patterns)

1. **Workspace Setup sheet** — one job, copyable command, one Done, a failure line that says
   what to do.
2. **Permission card** — one question, explicit options, selected state, Other, Decline.
3. **Workspace Setup line in the panel** — a status that is also the affordance ("3 checks need
   attention. Opens setup details.").
4. **Chat work group** — summary line with a count, expandable detail, no extra chrome.
5. **Turn rail** — numbering only when it encodes order, and only for long chats.
6. **Sidebar depth** — indentation + 0.5 pt dividers instead of boxes.
7. **New workspace / Add project** — one primary action, disabled state explains itself, no
   secondary buttons competing.
8. **File viewer** — preview/source segment, edit/save/discard, conflict state.

## What was fixed in this branch

Low-risk, local fixes only. 26 files, 153 insertions / 93 deletions.

**Copy**
- Sidebar "Scheduled" → "Schedules" (upstream `en.ts:1292`).
- Empty workspace/project toasts: sentence case and a next step
  (`SidebarWorkspaceRow.swift:97`, `SidebarProjectGroup.swift:94`).
- History empty states: "No sessions yet" / "No sessions match" (upstream `en.ts:281-282`) plus
  "Start one from the sidebar." / "Try a different title."
- History and Changes "Try again" → "Retry" (upstream uses `retry: "Retry"`); Project settings
  "Try again" → "Retry".
- History's failed state now has the upstream title "Couldn't load agent history"
  (`en.ts:235`) above the host message.
- "This host can't set project icons." replaces the capability-key sentence.
- "Something went wrong. Try again." replaces "Unknown error".
- "This turn ended without a reply." replaces "Turn complete."
- Terminal close dialog matches upstream `en.ts:730-731`: "Close terminal?" and "Any running
  process in this terminal will be stopped immediately."
- Forge name casing: "GitHub"/"GitLab", not "Github"/"Gitlab". Forge search omits `#-1`.

**Consistency / tokens**
- `SheetRow` symbol, badge, detail, value and chevron use `ClaudePalette` (adaptive secondary,
  tertiary, orange) instead of a hard-coded gray, `Color.orange` and `.blue`.
- `SheetRow`'s checkmark and all appearance tiles/switches use the Claude accent, not blue
  (General and Sidebar settings, Welcome appearance).
- `RowDivider` in the shared sheet kit and the permission card's three rules now use
  `ClaudeDivider` (0.5 pt) instead of `Divider()`.
- Context sheet uses `typography` roles and `secondaryInk`.
- Composer dictation banner and error line use `typography` roles.
- Welcome appearance sheet uses the type roles and adaptive gray.
- Removed the duplicate "Refresh" item from the Files overflow menu (pull-to-refresh and the
  header control remain).

**Accessibility**
- Agent menu label includes the agent title (`ChatHeader.swift:67`).
- File rows include size/date (`WorkspaceFilesView.swift:461-468`).
- Schedule rows include cadence + next run (`SchedulesListPage.swift:133`).
- Workspace page segments and file preview/source use `.isSelected` instead of
  `accessibilityValue("Selected")`.
- Step rows and folded work groups expose expanded/collapsed; forge results and shared sheet rows
  expose selected (the checkmark image is hidden from VoiceOver).
- Composer attachment pill and remove button are separate elements, so VoiceOver can remove
  without opening.
- Expand composer and back-to-end have 44 pt targets; loading workspace page has a label.

**Motion**
- Follow indicator, terminal toast, file preview segment and the Files reveal scroll now respect
  `accessibilityReduceMotion`.

## Proposals (medium/high, for the user)

1. **Unify the headers.** Make `SheetHeader` serif 19 / 44 pt / 56 pt and migrate Settings,
   Schedules, History and Search to it. Removes finding 2 and most of the "two apps" feel.
2. **One settings conversion pass.** Replace 179 fixed fonts + 88 flat grays + remaining raw
   accents across the settings family. Do it with an Xcode visual pass at default, large and
   accessibility text sizes, light/dark/pure black.
3. **One toast host.** Extract the six implementations into a single modifier and delete the
   copies. Decide top vs bottom once.
4. **A 44 pt rule for icon buttons.** Add a small `IconButton`/hit-slop helper and apply it to
   queue rows, find bar, permission card, file toolbar, panel switcher, schedule rows, project
   scripts. Keep visual sizes; only the target changes.
5. **Files toolbar diet.** One refresh path, one create action, overflow only for rare actions.
   Consider moving preview/source into the filename menu in the file viewer.
6. **Panel close and search affordance.** Add a close control to the workspace panel header and a
   visible search magnifier in the chat header. Both are navigation changes; confirm first.
7. **Welcome appearance de-duplication.** Either keep only the four tiles in Welcome and route
   "Scale"/"Motion" to Settings, or remove the welcome sheet and open Settings → Appearance. Right
   now the same controls exist in two places with different surrounding chrome.
8. **Section label direction.** Choose tracked 11 pt caps everywhere or sentence case everywhere.
   Do not keep the 12 pt/11 pt split.
9. **Remaining default dividers.** The permission card is done; audit the other default
   `Divider()` uses (e.g. `ClaudeChatComponents.swift:196,208`) and use `ClaudeDivider` in cards.
10. **VoiceOver pass.** Turn on VoiceOver and walk chat → composer → panel → settings. Check
    rotor order, the find result count, the turn rail container, and announce the selected state
    of sheet rows. Code review cannot prove this.

## Excluded by active tickets (observed, not changed)

- **M13 (Voice settings, speech providers).** No voice settings files exist on this branch, so
  there is nothing to review. When M13 lands, check its pages for the same fixed-font/flat-gray/
  blue-tint issues as the rest of Settings, and check that the API-key field never echoes a saved
  secret.
- **M14 (Usage overview, connection states).** `ClaudeUsageReportsSheet.swift` has 15 fixed-size
  fonts and flat `secondary` grays (`:54,61,64,72,96,101,114,118,125,133,144,148,151,164,168`),
  and its failed state has no Retry (`:56-66`). `ConnectView.swift` still has
  `.tint(.blue):327`, a `withAnimation(.easeOut(0.18))` without a Reduce Motion check at `:334`,
  and fixed sizes at `:164,183,219,342,453`. All are M14's to fix; noted for that branch.
- **R16 (relay crypto).** No UI on this branch. Nothing to audit.

## Verification

- `swiftc -parse` on all 26 touched files: clean.
- `Packages/PaseoCore`: `swift build` succeeds; `swift test` passes (20 tests, 6 suites).
- `Tools/api-audit`: 313 `unknown-type`, 4 `missing-static`, 2 `missing-member`. All are
  pre-existing generic false positives (`Content.blur`, `Content.simultaneousGesture`,
  `Option.AllCases`, `Option.RawValue`); none names a type or member added by this change.
- Not compiled: SwiftUI views and `App/` cannot build on this Linux machine. The parse-clean
  edits still need an Xcode build and a visual pass. Specific spots to check:
  - `ChatComposer.swift:249-257`: 44 pt transparent frame around the 28 pt expand circle;
    confirm it does not overlap the send button at narrow widths.
  - `ChatTranscript.swift:408-415`: 44 pt frame plus `composerHeight + 7` padding keeps the
    visible circle where it was; confirm visually.
  - `ClaudeSheets.swift:79`: `RowDivider` is now `ClaudeDivider`; confirm the 0.5 pt line sits
    correctly inside rounded row groups.
  - `ClaudeHistoryView.swift:267-273`: the empty state now always shows a second line, including
    when the query is empty.
  - `ForgeSearchPicker.swift:265`: `resultTitle` handles a nil issue number; confirm no caller
    expected `#-1`.
