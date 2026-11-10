# Audit A: design-system coherence (2026-11-10, HEAD 29d78eb)

A read-only audit run by an Explore agent; the lead spot-checked `ClaudeStyle.swift` and
`ClaudeSheets.swift`. Paths are relative to `Packages/PaseoUI/Sources/PaseoUI/`.

## 1. Tokens and code that bypasses them

**Typography**
- `ClaudeTypography` is defined in `Chat/ClaudeStyle.swift`. `serif` and `mono` apply the text-scale multiplier, but `sans`
  does not (:34 vs :45-52). When the custom font is missing, `sans` and `mono` fall back to `.system(style)`, which drops the requested size.
- There are 82 fresh `ClaudeTypography()` instances, 16 passed as a parameter, and **0 read from the environment**.
- The fonts follow **two type systems**:
  - Settings and sheets use SF system fonts with `ClaudePalette.secondary`.
  - Chat and Workspace use `typography.sans` with `secondaryInk`.
- There are 564 `.system(size:)` calls, about 314 of them on text. The most common sizes are 13 (154), 15 (120) and 17 (82).
- Only one SwiftUI text style is used (`.caption`).
- Worst files: `PaseoSettingsView` 90, `SpeechProviderSheet` 29, `ProjectSettingsView` 25, `PairingFlow` 22,
  `ClaudeUsageReportsSheet` 22, `ProviderDetailSheet` 22, `WorkspaceChangesView` 20.

**Palette**
- `ClaudePalette` holds about 28 colors, with these duplicates:
  - `primaryInk` and `shimmerInk` are identical.
  - `ink` and `primaryInk` are nearly identical.
  - `codeBackground` (7 uses) and `codeSurface` (11 uses) are nearly identical.
  - `secondary = Color(white: 0.56)` does **not adapt** to light/dark but has 181 uses; `secondaryInk` has 293.
- There are no spacing or radius tokens.

**Hardcoded colors**
- The same appearance-swatch colors are copy-pasted in `PaseoSettingsView.swift:614-638` and `WelcomeView.swift:258-265`.
- The terminal copies palette values by hand (`PaseoTerminalView.swift:54-55`, `PaseoTerminalKeyBar.swift:34,47`).
- `ClaudePaletteWarm.controlActive` #DD7757 (`PaseoTerminalKeyBar.swift:212`) differs from `orange` #D97757.
- The diff tints are private in `WorkspaceChangesDiffView.swift:724-734`, while `ClaudeToolDetail.swift:44` uses `successInk.opacity(0.14)`.
- `.tint(.blue)` / `Color.blue`: about 25 sites, most of them in `PaseoSettingsView`, `WorkspaceChangesView`, `SidebarDisplayOptions`
  and `ClaudeSheets.swift:64`.
- `.gray` / `.secondary`: `ClaudeMediaView.swift:8,76,81,85`, `WorkspaceTerminalsView.swift:661`.

**Corner radii**
- There are 104 literal radii with 13 distinct values. The most common are 14 (26), 12 (24), 8 (13), 16 (12) and 10 (10).
- The same `panel` surface is drawn with seven different radii.
- Sheets use corner radius 38 in most places but 40 in four.

**Motion**
- There are about 56 literal curves, against 28 `ClaudeMotion` references.
- `.easeOut(0.2)` appears 19 times; the others are 0.25 ×7, 0.18 ×7, 0.15 ×6, 0.35 ×4 and more.

**Haptics**
- `Haptics.*` has 294 calls. Three sites bypass the helper, and with it the user's Haptics switch:
  - `ComposerQueue.swift:36` (`QueueHaptics`, medium impact);
  - `PaseoTerminalKeyBar.swift:25`;
  - `ConnectView.swift:128` (`.sensoryFeedback(.error)`).

## 2. Duplicate or competing components

- **Sheet headers:**
  - `SheetHeader` (centered system 17 semibold title, **leading** 42 pt glass xmark), used in 26 files;
  - a hand-rolled serif-19 header with a 19 pt xmark, ×5 (`WorkspaceLabels:317,585`, `CommandCenterView:143`, `ClaudeHistoryView:139`,
    `SchedulesListPage:41`);
  - a 44 pt variant in `PaseoSettingsView:169`;
  - native navigation bars with a "Done" button (`ChatSubagents:221`, `ChatBackgroundWork:99`, `WorkspaceTerminalFileSheet:50`).
- **Buttons:**
  - Only one `ButtonStyle` exists, used once.
  - `.plain` ×189.
  - The system `.bordered` / `.borderedProminent` styles ×17.
  - Hand-rolled ink-capsule primary buttons ×21.
- **Cards:** `ClaudeCard` (radius 10), `RowGroup` (radius 28), `RichCard`, plus about 30 inline rectangles.
- **Rows:** `SheetRow` (4 files) and hand-rolled rows elsewhere. There are two dividers (`ClaudeDivider`, `RowDivider`).
- **Empty states:** about 9 different ones plus about 25 inline "No …" texts.
- **Loaders:** `ClaudeLoader` ×1 and `ProgressView` ×87 across 47 files, tinted five different ways.
- **Status dots:** `ClaudeStatusDot` and `PaseoStatusDot`.
- **Toasts:** six separate implementations, with durations of 1.5, 2 or 2.5 s and positions at top 58, bottom 18 or bottom 96.
- **Error banners:** `errorBanner` in both Terminals and Changes, plus History, the shell and dictation.
- **Pills:** `VerdictPill`, `StatePill`, `ScheduleStatePill`, `ComposerAttachmentPill`, `ComposerModelChip`, `SubagentTrackPill`,
  `RichPathChip`, `WorkspaceLabelChip`, `filterChip`, `metadataModeChip`, `terminalChip`, `forgePill`.
- **Diff stats (+N/−N):** six renderers with different opacities.
- **Diff views:** `ClaudeDiffView`, `WorkspaceChangesDiffView`, `WorkspaceCommitDiffView`.
- **Copy buttons:** `ClaudeCopyButton` (2 uses) and about six hand-rolled "copied → checkmark" copies. `UIPasteboard` is called directly in 17 files.
- **Code highlighting** is wired twice (`ClaudeMarkdownView:327`, `WorkspaceFileViewer:754`).
- **Appearance picker:** duplicated in `WelcomeView` and `PaseoSettingsView`.

## 3. Naming and folder mismatches

- **Name prefixes are mixed:** `Claude*`, `Paseo*`, `Chat*`, `Workspace*` and unprefixed names.
- **The design system lives in three places:** `Chat/ClaudeStyle.swift`, `ClaudeSheets.swift` and
  `Paseo/DesignSystem/Haptics.swift`.
- **`Chat/` holds code that belongs elsewhere:**
  - Settings: `PaseoSettingsView`, `PairingFlow`, `SoundCues`, `DefaultSend`.
  - Shell: `PaseoShellView`, `EdgeDrawer`.
  - Sidebar sheets: `AddProjectSheet`, `ClaudeHistoryView`, `ClaudeUsageReportsSheet`, `ImportSessionSheet`.
  - Schedules: `ScheduleWords`.
  - Design system: `ClaudeStyle`, `ClaudeLoader`.
  - Composer pieces, while `ChatComposer` itself is in `Conversation/`.
- **Root-level files that belong in folders:**
  - Onboarding: `ConnectView`, `ConnectionURI`, `WelcomeView`.
  - Design system: `ClaudeSheets`, `ClaudeAppearance`.
- **Names that don't match their contents:**
  - `ClaudeUsageRing.swift` declares `ClaudeMeterRing`, `ClaudeUsageBar` and `ClaudeUsageResets`.
  - `PaseoSettingsKeys` lives in `ClaudeStyle.swift`.
  - The storage key `"paseo.appearance"` is defined twice.

## 4. Dead code

| Item | Confidence | Evidence |
|---|---|---|
| `ClaudeMotion.tick`, `ClaudeMotion.roll` | High | 0 references |
| `ClaudePalette.sidebarBackground` | High | 0 references |
| `ClaudeMediaPlaceholder`, `ClaudeVideoFileCard`, `ClaudeVideoFileViewer` (`ClaudeMediaView.swift:5,70,89`) | High | declaration only |
| `InlineCodeRenderer` (`ClaudeMarkdownView.swift:418`) | High | never applied, so `InlineCodeAttribute` (:356) is set but never rendered: inline code styling may be missing |
| `HostColor`, `HostBadgeDisplay`, `HostAppearance`, `appearance(for:)` / `setAppearance` (`Settings/HostSwitchContext.swift:57-165`) | High | no callers outside the file |
| `PairingConnectOutcome` (`PairingFlow.swift:12`) | High | declaration only |
| `WorkspaceBaseBranchRow` (`WorkspaceBaseBranchSheet.swift:8`) | High | declaration only |
| `ClaudeMediaState` | Medium | used only in tests |

## 5. Sheets and navigation presentation

**Inventory**
- About 50 `.sheet`, 6 `.fullScreenCover`, 1 `.popover`, 31 `.confirmationDialog` and 10 `.alert`.

**Detents**
- `.large`: about 20 sheets.
- `[.medium, .large]`: 10 sheets.
- `.medium`: 1 sheet.
- Fixed heights: 560, 430, 400, 380, 260 and 240.

**Drag indicator, corner radius and background**
- The drag indicator is visible on about 27 sheets, hidden on 8 and unset on 4.
- The corner radius is missing on 8 sheets.
- Share sheets and camera pickers set no presentation modifiers at all.
- `presentationBackground` is never used; there are about 43 ad-hoc background calls instead.
- Detents are sometimes set inside the sheet and sometimes at the call site.

**Navigation**
- `NavigationStack` appears in only 5 places.
- Settings, `DraftControlsSheet` and `ClaudeAgentControlsSheet` page manually.

**Dismiss controls**
- A leading glass xmark.
- A trailing "Done".
- A "Close" text button.
- "Cancel".
