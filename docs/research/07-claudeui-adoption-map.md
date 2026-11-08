# 07 — ClaudeUI adoption map

**Date:** 2026-11-08 · **Worktree:** `research-claudeui-map` · **Status:** research only — no code, tests, or other files were changed; this is the only output.

**What this is.** The plan for building Paseo's iOS UI on `Packages/ClaudeUI` (a SwiftUI recreation of the Claude iOS app, ~8.5k lines of Swift + resources): what each file is, what maps to Paseo, what gets deleted, in what order, and where the chat seam is. Sources read: `ARCHITECTURE.md`, `Packages/ClaudeUI/README.md`, `Packages/ClaudeUI/docs/INTEGRATION.md`, `docs/research/01-app-features.md` (the Paseo app's feature inventory; "doc 01" below), the full `Packages/ClaudeUI/Sources` tree, and `Packages/PaseoCore/Sources/PaseoStore` + `PaseoProtocol` (`HostSession.swift`, `ConversationStore`, `Turn.swift`, `TimelineState.swift`, `Presentation.swift`, `Timeline.swift`, `Agents.swift`).

All citations are `path:line` relative to the repository root. Line numbers were read on 2026-11-08.

**Verdict legend (Section 3):** **KEEP** = works for Paseo as-is (maybe re-skinned) · **ADAPT** = maps onto a named Paseo feature; the PaseoStore data it needs is named · **DELETE** = Claude-only, no Paseo equivalent.

---

## 1. File inventory — every file in `Sources/ClaudeUI` and `Sources/ClaudeWidgets`

67 `.swift` files + 14 resource files. "Deps" lists types used that are defined in *another* ClaudeUI/ClaudeWidgets file, with the defining location. "Screen(s)" is where it appears.

### 1a. Core session & chat

| File | Lines | Kind | Screen(s) | Deps (types ← file) |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/SessionState.swift` | 305 | State | All screens (owner) | `ClaudeMediaState`/`ClaudeMedia` ← `MediaState.swift:32,6`; `DictationWaveformMetrics` ← `DictationWaveformMetrics.swift:5`; `ClaudeSettingsState` ← `SettingsState.swift:64`; `DeviceState` ← `DeviceState.swift:51`; `DispatchState` ← `DispatchState.swift:18`; `CodeState` ← `CodeState.swift:43`; `ArtifactsState` ← `ArtifactState.swift:74`; `ProjectState` ← `ProjectState.swift:37`; declares `ChatMessage` `:3`, `ClaudeAppearance` `:17`, `ClaudeVoice` `:18`, `ComposerPhase` `:19`, `Effort` `:20`, `ClaudeModel` `:23`, `FeedbackSubmission` `:34`, `ClaudeAction` `:45`, `SessionState` `:63` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeSessionView.swift` | 805 | View | Chat screen (root), sidebar drawer, voice overlay, dictation | `SessionState`, `ClaudeAction`, `FeedbackSubmission` ← `SessionState.swift:63,45,34`; `ClaudeMarkdownView` ← `ClaudeMarkdownView.swift:36`; sheets ← `ClaudeSheets.swift:80,134,315,369`; `ClaudeMediaViewer`/`ClaudeVideoFileViewer`/`ClaudeVideoFileCard`/`ClaudeMediaPlaceholder`/`ClaudeMediaPresentation` ← `ClaudeMediaView.swift:12,89,70,5,4`; `ClaudeSettingsView` ← `ClaudeSettingsView.swift:5`; `ClaudeDevicesView` ← `ClaudeDevicesView.swift:4`; `ClaudeDispatchView` ← `ClaudeDispatchView.swift:4`; `ClaudeArtifactsView` ← `ClaudeArtifactsView.swift:4`; `ClaudeProjectsView` ← `ClaudeProjectsView.swift:4`; `ClaudeCodeView` ← `ClaudeCodeView.swift:4`; `ClaudeVoiceSettingsSheet` ← `ClaudeVoiceSettingsSheet.swift:4`; `DictationWaveformMetrics` ← `DictationWaveformMetrics.swift:5`; `ClaudeFontResources` ← `ClaudeFontResources.swift:6`; declares `ClaudeTypography` `:5`, `ClaudePalette` `:9`, `ClaudeSheet` `:28`, `UnequalMenu` `:775`, `GhostShape` `:785` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeSheets.swift` | 412 | View | Model sheet, Effort sheet, attachments sheet, feedback sheet, placeholders | Primitive sheet chrome (`SheetHeader` `:4`, `SheetRow` `:27`, `RowGroup` `:73`, `RowDivider` `:79`) used by nearly every sheet; `Effort`/`ClaudeModel`/`SessionState`/`ClaudeAction`/`FeedbackSubmission`/`ClaudeAppearance` ← `SessionState.swift:20,23,63,45,34,17`; `CameraCapture`/`ClaudeCameraView` ← `CameraState.swift:5`, `ClaudeCameraView.swift:6` (`SyntheticCameraPreview` passed at `ClaudeSheets.swift:288`, defined `ClaudeCameraView.swift:121`); declares `ClaudeModelSheet` `:80`, `ClaudeAttachmentSheet` `:134`, `SyntheticPhoto` `:292`, `ClaudePlaceholderSheet` `:315`, `ThemeThumbnail` `:342`, `ClaudeFeedbackSheet` `:369` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeFontResources.swift` | 16 | Helper | All (font registration) | Leaf; registers bundled `Newsreader` resources (`ClaudeFontResources.swift:6-15`) |
| `Packages/ClaudeUI/Sources/ClaudeUI/DictationWaveformMetrics.swift` | 26 | Helper | Dictation | Leaf; consumed at `ClaudeSessionView.swift:557-567` and `SessionState.swift:95` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ScaledFont.swift` | 39 | Helper | Settings notifications page | Leaf; `View.scaledFont` `:32`, used at `ClaudeNotificationSettingsView.swift:20-21` |

### 1b. Markdown rendering stack

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/MarkdownDocumentModel.swift` | 149 | Model (+ action enum) | Assistant prose, artifact doc, memory file, shared link | `swift-markdown` package (`:2`); declares `MarkdownDocumentModel` `:5`, `MarkdownUnsupportedKind` `:17`, `MarkdownImage` `:18`, `MarkdownInline` `:28`, `MarkdownListItem` `:52`, `MarkdownColumnAlignment` `:60`, `MarkdownBlock` `:61`, `MarkdownAction` `:115` |
| `Packages/ClaudeUI/Sources/ClaudeUI/MarkdownTableMetrics.swift` | 64 | Helper | Assistant prose tables | Leaf (`MarkdownTableMetrics` `:5`); contains `ClaudeMarkdownTableLayout` `:23` (SwiftUI `Layout`, UIKit-gated) |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeCodeHighlighter.swift` | 51 | Helper | Assistant prose code blocks | `HighlighterSwift` package (`:2`); declares `ClaudeCodeSyntaxTheme` `:4`, `ClaudeCodeHighlighter` `:8` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeMarkdownView.swift` | 336 | View | Assistant prose, artifacts, memory, shared links, settings | `MarkdownDocumentModel` stack ← `MarkdownDocumentModel.swift:5,61,28,18,115,17,60`; `ClaudeMarkdownTableLayout`/`MarkdownTableMetrics` ← `MarkdownTableMetrics.swift:23,5`; `ClaudeSelectableInlineCode` ← `ClaudeSelectableInlineCode.swift:7`; `ClaudeCodeHighlighter` ← `ClaudeCodeHighlighter.swift:8`; `ClaudePalette` ← `ClaudeSessionView.swift:9`; declares `ClaudeMarkdownTheme` `:5` (`.artifact` preset `:28`), `ClaudeMarkdownView` `:36` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeSelectableInlineCode.swift` | 151 | View (UIViewRepresentable) | Assistant prose inline code | `MarkdownInline`/`MarkdownImage`/`MarkdownAction` ← `MarkdownDocumentModel.swift:28,18,115`; `ClaudeMarkdownTheme` ← `ClaudeMarkdownView.swift:5` |

### 1c. Media, camera

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/MediaState.swift` | 63 | State | Chat bubbles, attachment tray, attachments sheet, viewers | Leaf; declares `ClaudeMediaKind` `:4`, `ClaudeMedia` `:6`, `ClaudeMediaAction` `:26`, `ClaudeMediaState` `:32` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeMediaView.swift` | 129 | View | Chat bubbles, tray, viewer, video viewer | `ClaudeMedia`/`ClaudeMediaAction`/`ClaudeMediaKind` ← `MediaState.swift:6,26,4`; `ClaudePalette` ← `ClaudeSessionView.swift:9`; declares `ClaudeMediaPresentation` `:4`, `ClaudeMediaPlaceholder` `:5`, `ClaudeMediaViewer` `:12`, `ClaudeVideoFileCard` `:70`, `ClaudeVideoFileViewer` `:89` |
| `Packages/ClaudeUI/Sources/ClaudeUI/CameraState.swift` | 50 | State | Camera | Leaf; declares `CameraMode` `:3`, `CameraFlash` `:4`, `CameraCapture` `:5`, `CameraAction` `:15`, `CameraState` `:19` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeCameraView.swift` | 148 | View | Camera (full screen) | `CameraState`/`CameraAction`/`CameraMode`/`CameraCapture` ← `CameraState.swift:19,15,3,5`; declares `ClaudeCameraView` `:6`, `SyntheticCameraPreview` `:121` (demo scene) |

### 1d. Code (Claude Code) surface

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/CodeState.swift` | 82 | State | Code home | `RoutineState` ← `RoutineState.swift:41`; `CodeDraftState` ← `CodeDraftState.swift:41`; declares `CodeFilter` `:3`, `CodeSessionStatus` `:7`, `CodeSessionLocation` `:8`, `CodeSession` `:9`, `CodeDevice` `:28`, `CodeAction` `:38`, `CodeState` `:43` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeCodeView.swift` | 204 | View | Code home (sessions + devices list, remote-setup sheet) | `CodeState`/`CodeSession`/`CodeSessionStatus`/`CodeFilter` ← `CodeState.swift:43,9,7,3`; `ClaudeCodeDraftView` ← `ClaudeCodeDraftView.swift:4`; `ClaudeRoutinesView` ← `ClaudeRoutinesView.swift:4`; `UnequalMenu` ← `ClaudeSessionView.swift:775`; `SheetHeader` ← `ClaudeSheets.swift:4`; `CodeReferenceIcons` ← `CodeReferenceIcons.swift:5`; declares `ClaudeCodeView` `:4`, `ClaudeCodeRemoteSetupSheet` `:163` (private) |
| `Packages/ClaudeUI/Sources/ClaudeUI/CodeDraftState.swift` | 79 | State | Code — new session draft | `ClaudeModel` ← `SessionState.swift:23`; `CodeConnectorState` ← `CodeConnectorState.swift:55`; `CodeEnvironmentFormState`/`CodeEnvironment` ← `CodeEnvironmentState.swift:32,3`; declares `CodeEffort` `:3`, `CodeRepository` `:6`, `CodeBranch` `:18`, `CodePermission` `:28`, `CodeContextAction` `:31`, `CodeDraftAction` `:34`, `CodeDraftState` `:41` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeCodeDraftView.swift` | 209 | View | Code — new session draft; Code model/effort sheet | `CodeDraftState`/`CodeDraftAction`/`CodeEffort` ← `CodeDraftState.swift:41,34,3`; `ClaudeModel` ← `SessionState.swift:23`; `SheetHeader`/`RowGroup`/`SheetRow`/`RowDivider` ← `ClaudeSheets.swift:4,73,27,79`; `CodeReferenceIcons` ← `CodeReferenceIcons.swift:5`; `GitHubLogo.imageset` asset ← `Resources/Assets.xcassets/GitHubLogo.imageset/Contents.json:1`; declares `ClaudeCodeDraftView` `:4`, `ClaudeCodeModelSheet` `:128`, `SleepingCodeMascot` `:182` (private) |
| `Packages/ClaudeUI/Sources/ClaudeUI/CodeEnvironmentState.swift` | 56 | State | Code — create environment | Leaf; declares `CodeEnvironment` `:3`, `CodeNetworkAccess` `:11`, `CodeEnvironmentDraft` `:22`, `CodeEnvironmentAction` `:28`, `CodeEnvironmentFormState` `:32` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeCodeConfigurationSheets.swift` | 204 | View | Code — choose environment, new environment, repositories | `SheetHeader`/`RowGroup`/`SheetRow`/`RowDivider` ← `ClaudeSheets.swift:4,73,27,79`; `CodeDraftState`/`CodeDraftAction`/`CodeRepository` ← `CodeDraftState.swift:41,34,6`; `CodeEnvironmentFormState`/`CodeEnvironmentAction`/`CodeNetworkAccess`/`CodeEnvironmentDraft` ← `CodeEnvironmentState.swift:32,28,11,22`; declares `ClaudeCodeEnvironmentSheet` `:4`, `ClaudeCodeEnvironmentEditor` `:49`, `ClaudeCodeRepositorySheet` `:135` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeCodeContextSheet.swift` | 132 | View | Code — add context, permission, branches | `CodeDraftState`/`CodeDraftAction`/`CodeContextAction`/`CodePermission`/`CodeBranch` ← `CodeDraftState.swift:41,34,31,28,18`; `SheetHeader`/`RowGroup`/`SheetRow`/`RowDivider` ← `ClaudeSheets.swift:4,73,27,79`; `SyntheticPhoto` ← `ClaudeSheets.swift:292`; `ClaudeCodeConnectorsView` ← `ClaudeCodeConnectorsView.swift:4`; `CodeReferenceIcons` ← `CodeReferenceIcons.swift:5`; declares `ClaudeCodeBranchSheet` `:4`, `ClaudeCodeContextSheet` `:38` |
| `Packages/ClaudeUI/Sources/ClaudeUI/CodeConnectorState.swift` | 71 | State | Code — connectors, Settings — connectors | Leaf; declares `CodeToolPermission` `:3`, `CodeConnectorTool` `:20`, `CodeConnector` `:31`, `CodeConnectorAction` `:52`, `CodeConnectorState` `:55` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeCodeConnectorsView.swift` | 122 | View | Code — connectors | `CodeConnectorState`/`CodeConnector`/`CodeConnectorTool`/`CodeToolPermission`/`CodeConnectorAction` ← `CodeConnectorState.swift:55,31,20,3,52`; `SheetHeader`/`RowGroup`/`SheetRow`/`RowDivider` ← `ClaudeSheets.swift:4,73,27,79`; declares `ClaudeCodeConnectorsView` `:4` |
| `Packages/ClaudeUI/Sources/ClaudeUI/CodePreferences.swift` | 48 | State | Settings — Code | Leaf; declares `ClaudeTranscriptFontChoice` `:3`, `ClaudeCodeFontChoice` `:6`, `ClaudeCodePreferenceAction` `:9`, `ClaudeCodePreferences` `:15` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeCodeSettingsView.swift` | 82 | View | Settings — Code | `ClaudeCodePreferences`/`ClaudeCodePreferenceAction`/`ClaudeTranscriptFontChoice`/`ClaudeCodeFontChoice` ← `CodePreferences.swift:15,9,3,6`; `RowGroup` ← `ClaudeSheets.swift:73`; `ClaudeSettingsColors` ← `ClaudeNotificationSettingsView.swift:4`; declares `ClaudeCodeSettingsView` `:4` |
| `Packages/ClaudeUI/Sources/ClaudeUI/CodeReferenceIcons.swift` | 75 | Helper | Code home, Code draft, Routines, Projects | Leaf; declares `CodeReferenceIcons` `:5`, `CodeWorkingIndicator` `:58` (private) |

### 1e. Routines (Claude Code scheduled tasks)

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/RoutineState.swift` | 97 | State | Routines | Leaf; declares `RoutineFilter` `:3`, `RoutineEditor` `:4`, `RoutineField` `:5`, `RoutineOption` `:6`, `RoutineRepeat` `:10`, `RoutineSchedule` `:14`, `RoutineDraft` `:25`, `RoutineAction` `:36`, `RoutineState` `:41` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeRoutinesView.swift` | 292 | View | Routines (list + creator sheet) | `RoutineState`/`RoutineAction`/`RoutineFilter`/`RoutineEditor`/`RoutineField`/`RoutineOption`/`RoutineRepeat`/`RoutineSchedule` ← `RoutineState.swift:41,36,3,4,5,6,10,14`; `RowGroup`/`RowDivider`/`SheetHeader`/`SheetRow` ← `ClaudeSheets.swift:73,79,4,27`; `CodeReferenceIcons` ← `CodeReferenceIcons.swift:5`; declares `ClaudeRoutinesView` `:4`, `ClaudeRoutineEditorView` `:69` |

### 1f. Dispatch

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/DispatchState.swift` | 50 | State | Dispatch | Leaf; declares `DispatchConnection` `:3`, `DispatchMessage` `:4`, `DispatchAction` `:16`, `DispatchState` `:18` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeDispatchView.swift` | 140 | View | Dispatch | `DispatchState`/`DispatchAction`/`DispatchMessage`/`DispatchConnection` ← `DispatchState.swift:18,16,4,3`; `UnequalMenu` ← `ClaudeSessionView.swift:775`; `ClaudePalette` ← `ClaudeSessionView.swift:9`; declares `ClaudeDispatchView` `:4`, `ClaudeDispatchBackground` `:106` |

### 1g. Devices (Claude Desktop)

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/DeviceState.swift` | 90 | State | Devices sheet | Leaf; declares `DeviceConnectionStatus` `:3`, `ClaudeDevice` `:4`, `DeviceAccountTab` `:14`, `DeviceProfileField` `:17`, `DeviceAccountProfile` `:18`, `DeviceAccountLoadState` `:42`, `DeviceAccountOutcome` `:43`, `DeviceAction` `:44`, `DeviceState` `:51` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeDevicesView.swift` | 255 | View | Devices sheet | `DeviceState`/`DeviceAction`/`DeviceAccountTab`/`DeviceProfileField`/`DeviceAccountLoadState` ← `DeviceState.swift:51,44,14,17,42`; `SheetHeader`/`SheetRow`/`RowGroup`/`RowDivider` ← `ClaudeSheets.swift:4,27,73,79`; declares `ClaudeDevicesView` `:4`, `ClaudeManageDevicesView` `:50`, `AccountButtonStyle` `:245` (private) |

### 1h. Projects

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/ProjectState.swift` | 150 | State | Projects list, project editor | Leaf; declares `ClaudeProject` `:3`, `ProjectDraft` `:18`, `ProjectFilter` `:27`, `ProjectEditor` `:28`, `ProjectAction` `:29`, `ProjectState` `:37`, `ProjectIconOption` `:117` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeProjectsView.swift` | 127 | View | Projects list | `ProjectState`/`ProjectAction`/`ProjectFilter` ← `ProjectState.swift:37,29,27`; `ClaudeProjectEditorView` ← `ClaudeProjectEditorView.swift:4`; `ClaudePalette` ← `ClaudeSessionView.swift:9`; declares `ClaudeProjectsView` `:4`, `ProjectOutlineIcon` `:109` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeProjectEditorView.swift` | 314 | View | Project editor (introduction, form, Drive picker) | `ProjectState`/`ProjectAction`/`ProjectDraft` ← `ProjectState.swift:37,29,18`; `ClaudeProjectIconPicker` ← `ClaudeProjectIconPicker.swift:4`; `ProjectOutlineIcon` ← `ClaudeProjectsView.swift:109`; `CodeReferenceIcons` ← `CodeReferenceIcons.swift:5`; declares `ClaudeProjectEditorView` `:4`, `ProjectIntroductionIllustration` `:278` (private) |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeProjectIconPicker.swift` | 102 | View | Project editor — icon picker | `ProjectState` (`iconColors`)/`ProjectIconOption` ← `ProjectState.swift:117,37`; `ProjectOutlineIcon` ← `ClaudeProjectsView.swift:109`; declares `ClaudeProjectIconPicker` `:4`, `ProjectIconColors` `:88` |

### 1i. Artifacts

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/ArtifactState.swift` | 116 | State | Artifacts list, viewer | `MarkdownAction` ← `MarkdownDocumentModel.swift:115`; declares `ArtifactOwnership` `:3`, `ArtifactKind` `:6`, `ArtifactSection` `:10`, `ArtifactDocument` `:21`, `ClaudeArtifact` `:37`, `ArtifactAction` `:67`, `ArtifactsState` `:74` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeArtifactsView.swift` | 234 | View | Artifacts list, viewer | `ArtifactsState`/`ArtifactAction`/`ArtifactKind`/`ArtifactOwnership`/`ClaudeArtifact`/`ArtifactDocument` ← `ArtifactState.swift:74,67,6,3,37,21`; `ClaudeMarkdownView`/`ClaudeMarkdownTheme.artifact` ← `ClaudeMarkdownView.swift:36,28`; `UnequalMenu` ← `ClaudeSessionView.swift:775`; declares `ClaudeArtifactsView` `:4` |

### 1j. Settings — root and pages

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/SettingsState.swift` | 175 | State | Settings root | Feature states: `ClaudeBillingState` ← `BillingState.swift:8`; `ClaudeSharedLinksState` ← `SharedLinksState.swift:30`; `ClaudeSettingsConnectorState` ← `SettingsConnectorState.swift:12`; `ClaudeCapabilitiesState` ← `CapabilitiesState.swift:57`; `ClaudeMemoryFilesState` ← `MemoryFilesState.swift:41`; `ClaudeCodePreferences` ← `CodePreferences.swift:15`; `ClaudeUsageState` ← `UsageState.swift:43`; `ClaudePrivacyState` ← `PrivacyState.swift:18`; `ClaudeTimeFocusState` ← `TimeFocusState.swift:12`; `ClaudeNotificationPreferences` ← `NotificationPreferences.swift:33`; `ClaudeAppearance` ← `SessionState.swift:17`; declares `ClaudeAccountSummary` `:3`, `ClaudeProfile` `:13`, `ClaudeProfileField` `:25`, `ClaudeSettingsDestination` `:26`, `ClaudeProfileSubmission` `:34`, `ClaudeSettingsInfoLink` `:42`, `ClaudeSettingsAction` `:46`, `ClaudeSettingsState` `:64` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeSettingsView.swift` | 426 | View | Settings root (Account/App/Appearance), routes to all pages | `ClaudeSettingsState`/`ClaudeSettingsAction`/`ClaudeSettingsDestination`/`ClaudeSettingsInfoLink`/`ClaudeProfileField` ← `SettingsState.swift:64,46,26,42,25`; `ClaudeAppearance` ← `SessionState.swift:17`; sub-pages ← `ClaudeNotificationSettingsView.swift:8`, `ClaudeBillingSettingsView.swift:4`, `ClaudeSharedLinksView.swift:4`, `ClaudeSettingsConnectorsView.swift:5`, `ClaudeCapabilitiesView.swift:4`, `ClaudeMemoryFilesView.swift:4`, `ClaudeCodeSettingsView.swift:4`, `ClaudeUsageSettingsView.swift:4`, `ClaudePrivacySettingsView.swift:4`, `ClaudeTimeFocusView.swift:5`; `ClaudeConnectorCatalogView` ← `ClaudeConnectorCatalogView.swift:5`; `ClaudeProfileTextField` ← `ClaudeProfileTextField.swift:7`; `ThemeThumbnail`/`RowGroup`/`RowDivider` ← `ClaudeSheets.swift:342,73,79`; declares `ClaudeSettingsView` `:5` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeNotificationSettingsView.swift` | 41 | View | Settings — Notifications | `ClaudeNotificationPreferences`/`ClaudeNotificationPreference` ← `NotificationPreferences.swift:33,3`; `ClaudeSettingsAction` ← `SettingsState.swift:46`; `RowGroup` ← `ClaudeSheets.swift:73`; `View.scaledFont` ← `ScaledFont.swift:32`; declares `ClaudeSettingsColors` `:4` (shared `switchTint`), `ClaudeNotificationSettingsView` `:8` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeBillingSettingsView.swift` | 45 | View | Settings — Billing | `ClaudeBillingState`/`ClaudeBillingAction` ← `BillingState.swift:8,4`; `RowGroup` ← `ClaudeSheets.swift:73`; declares `ClaudeBillingSettingsView` `:4` |
| `Packages/ClaudeUI/Sources/ClaudeUI/BillingState.swift` | 25 | State | Settings — Billing | Leaf; declares `ClaudeSubscriptionOrigin` `:3`, `ClaudeBillingAction` `:4`, `ClaudeBillingState` `:8` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeSharedLinksView.swift` | 68 | View | Settings — Shared links | `ClaudeSharedLinksState`/`ClaudeSharedLinksAction` ← `SharedLinksState.swift:30,27`; `ChatMessage` ← `SessionState.swift:3`; `ClaudeMarkdownView` ← `ClaudeMarkdownView.swift:36`; `RowGroup` ← `ClaudeSheets.swift:73`; declares `ClaudeSharedLinksView` `:4` |
| `Packages/ClaudeUI/Sources/ClaudeUI/SharedLinksState.swift` | 44 | State | Settings — Shared links | `ChatMessage` ← `SessionState.swift:3`; `MarkdownAction` ← `MarkdownDocumentModel.swift:115`; declares `ClaudeSharedSnapshot` `:3`, `ClaudeSharedLinkGroup` `:17`, `ClaudeSharedLinksAction` `:27`, `ClaudeSharedLinksState` `:30` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeCapabilitiesView.swift` | 97 | View | Settings — Capabilities | `ClaudeCapabilitiesState`/`ClaudeCapability`/`ClaudeCapabilityAction`/`ClaudeCapabilityValue` ← `CapabilitiesState.swift:57,3,53,43`; `RowGroup` ← `ClaudeSheets.swift:73`; `ClaudeSettingsColors` ← `ClaudeNotificationSettingsView.swift:4`; declares `ClaudeCapabilitiesView` `:4` |
| `Packages/ClaudeUI/Sources/ClaudeUI/CapabilitiesState.swift` | 65 | State | Settings — Capabilities | Leaf; declares `ClaudeCapability` `:3`, `ClaudeCapabilityValue` `:43`, `ClaudeCapabilityAction` `:53`, `ClaudeCapabilitiesState` `:57` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeMemoryFilesView.swift` | 97 | View | Settings — Memory files | `ClaudeMemoryFilesState`/`ClaudeMemoryFilesAction` ← `MemoryFilesState.swift:41,35`; `ClaudeMemoryDraftEditor` ← `ClaudeMemoryDraftEditor.swift:6`; `ClaudeMarkdownView`/`ClaudeMarkdownTheme` ← `ClaudeMarkdownView.swift:36,5`; `RowGroup` ← `ClaudeSheets.swift:73`; declares `ClaudeMemoryFilesView` `:4` |
| `Packages/ClaudeUI/Sources/ClaudeUI/MemoryFilesState.swift` | 99 | State | Settings — Memory files | `MarkdownAction` ← `MarkdownDocumentModel.swift:115`; declares `ClaudeMemoryFile` `:3`, `ClaudeMemoryFileGroup` `:17`, `ClaudeMemoryDeletionRequest` `:27`, `ClaudeMemoryFilesAction` `:35`, `ClaudeMemoryFilesState` `:41` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeMemoryDraftEditor.swift` | 47 | View (UIViewRepresentable) | Settings — Memory files composer | Leaf; declares `ClaudeMemoryDraftEditor` `:6` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeSettingsConnectorsView.swift` | 177 | View | Settings — Connectors | `ClaudeSettingsConnectorState`/`ClaudeSettingsConnectorAction` ← `SettingsConnectorState.swift:12,3`; `CodeConnector`/`CodeConnectorTool`/`CodeToolPermission` ← `CodeConnectorState.swift:31,20,3`; `RowGroup` ← `ClaudeSheets.swift:73`; `ClaudeSettingsColors` ← `ClaudeNotificationSettingsView.swift:4`; declares `ClaudeSettingsConnectorsView` `:5` |
| `Packages/ClaudeUI/Sources/ClaudeUI/SettingsConnectorState.swift` | 68 | State | Settings — Connectors | `ClaudeConnectorCatalogState`/`ClaudeConnectorPresentation` ← `ConnectorCatalogState.swift:57,48`; `CodeConnector`/`CodeConnectorTool`/`CodeToolPermission` ← `CodeConnectorState.swift:31,20,3`; declares `ClaudeSettingsConnectorAction` `:3`, `ClaudeSettingsConnectorState` `:12` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeConnectorCatalogView.swift` | 163 | View | Settings — Connectors catalog, Add custom connector | `ClaudeConnectorCatalogState`/`ClaudeConnectorCatalogItem`/`ClaudeConnectorCatalogAction`/`ClaudeConnectorPresentation`/`ClaudeConnectorCatalogSort` ← `ConnectorCatalogState.swift:57,6,52,48,3`; `ClaudeProfileTextField` ← `ClaudeProfileTextField.swift:7`; declares `ClaudeConnectorCatalogView` `:5` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ConnectorCatalogState.swift` | 106 | State | Settings — Connectors catalog | Leaf; declares `ClaudeConnectorCatalogSort` `:3`, `ClaudeConnectorCatalogItem` `:6`, `ClaudeCustomConnectorDraft` `:33`, `ClaudeConnectorPresentation` `:48`, `ClaudeConnectorCatalogAction` `:52`, `ClaudeConnectorCatalogState` `:57` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeUsageSettingsView.swift` | 145 | View | Settings — Usage | `ClaudeUsageState`/`ClaudeUsageMeter`/`ClaudeUsageCredit`/`ClaudeUsageAction`/`ClaudeUsageLink` ← `UsageState.swift:43,7,21,37,36`; `RowGroup` ← `ClaudeSheets.swift:73`; `ClaudeSettingsColors` ← `ClaudeNotificationSettingsView.swift:4`; declares `ClaudeUsageSettingsView` `:4`, `UsageBarStyle` `:130` (private) |
| `Packages/ClaudeUI/Sources/ClaudeUI/UsageState.swift` | 64 | State | Settings — Usage | Leaf; declares `ClaudeUsageMeter` `:7`, `ClaudeUsageCredit` `:21`, `ClaudeUsageLink` `:36`, `ClaudeUsageAction` `:37`, `ClaudeUsageState` `:43` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudePrivacySettingsView.swift` | 63 | View | Settings — Privacy | `ClaudePrivacyState`/`ClaudePrivacyAction`/`ClaudePrivacyLink` ← `PrivacyState.swift:18,13,3`; `ClaudeSettingsColors` ← `ClaudeNotificationSettingsView.swift:4`; declares `ClaudePrivacySettingsView` `:4` |
| `Packages/ClaudeUI/Sources/ClaudeUI/PrivacyState.swift` | 25 | State | Settings — Privacy | Leaf; declares `ClaudePrivacyLink` `:3`, `ClaudePrivacyAction` `:13`, `ClaudePrivacyState` `:18` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeTimeFocusView.swift` | 101 | View | Settings — Time & focus | `ClaudeTimeFocusState`/`ClaudeTimeFocusAction`/`ClaudeWeekday`/`ClaudeBreakUnit` ← `TimeFocusState.swift:12,8,4,3`; declares `ClaudeTimeFocusView` `:5` |
| `Packages/ClaudeUI/Sources/ClaudeUI/TimeFocusState.swift` | 37 | State | Settings — Time & focus | Leaf; declares `ClaudeBreakUnit` `:3`, `ClaudeWeekday` `:4`, `ClaudeTimeFocusAction` `:8`, `ClaudeTimeFocusState` `:12` |
| `Packages/ClaudeUI/Sources/ClaudeUI/NotificationPreferences.swift` | 40 | State | Settings — Notifications | Leaf; declares `ClaudeNotificationPreference` `:3`, `ClaudeNotificationPreferences` `:33` |
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeProfileTextField.swift` | 40 | View (UIViewRepresentable) | Settings profile, catalog, instructions | Leaf; declares `ClaudeProfileTextField` `:7` |

### 1k. Voice settings

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeVoiceSettingsSheet.swift` | 98 | View | Voice settings sheet | `SessionState`/`ClaudeVoice`/`ClaudeAction` ← `SessionState.swift:63,18,45`; `ClaudeModelSheet` ← `ClaudeSheets.swift:80`; `SheetHeader`/`RowGroup`/`SheetRow` ← `ClaudeSheets.swift:4,73,27`; declares `ClaudeVoiceSettingsSheet` `:4` |

### 1l. Announcement (Claude-only)

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/ClaudeWorkAnnouncementView.swift` | 106 | View | Feature announcement | `ClaudeTypography` ← `ClaudeSessionView.swift:5`; `ClaudeFontResources` ← `ClaudeFontResources.swift:6`; declares `ClaudeWorkAnnouncementView` `:6`, `ClaudeWorkAnnouncementStill` `:91` |

### 1m. Widgets (`ClaudeWidgets` target)

| File | Lines | Kind | Screen(s) | Deps |
|---|---|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeWidgets/WidgetPresentation.swift` | 40 | State/model | Home Screen widgets | Leaf; declares `ClaudeWidgetDestination` `:3`, `ClaudeWidgetLayout` `:26`, `ClaudeWidgetPresentation` `:29` |
| `Packages/ClaudeUI/Sources/ClaudeWidgets/WidgetViews.swift` | 87 | View (WidgetKit) | Home Screen widgets | `ClaudeWidgetPresentation`/`ClaudeWidgetDestination`/`ClaudeWidgetLayout` ← `WidgetPresentation.swift:29,3,26`; `ClaudeLogo.imageset` asset ← `ClaudeWidgets/Resources/WidgetAssets.xcassets/ClaudeLogo.imageset/Contents.json:1`; declares `ClaudeWidgetContent` `:6`, `ClaudeWidgetView` `:37`, `ClaudeWidgetBackground` `:46`, `WidgetGlyph` `:52` (private) |

### 1n. Resources (not code) — every remaining file, verbatim

| Path | Size | What |
|---|---|---|
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Newsreader.ttf` | 4635 lines (≈5.4 MB, binary) | Bundled serif for `ClaudeTypography.serifName` (default `Newsreader16pt-Regular`) — `ClaudeSessionView.swift:5-8`, `SessionState`/`ClaudeMarkdownView.swift:14-26`, artifact theme `:28`; OFL license included |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Newsreader-Italic.ttf` | 4929 lines (binary) | Italic face of the above |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Newsreader-OFL.txt` | 92 lines | SIL Open Font License for Newsreader |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Swift-CMark-COPYING.txt` | 170 lines | swift-cmark license (via swift-markdown) — `MarkdownDocumentModel.swift:1-3` |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Swift-Markdown-LICENSE.txt` | 211 lines | swift-markdown license |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/HighlightJS-LICENSE.txt` | 29 lines | highlight.js license — `ClaudeCodeHighlighter.swift:1-51` |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/HighlighterSwift-LICENSE.txt` | 29 lines | HighlighterSwift license |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Simple-Icons-CC0.md` | 30 lines | Simple Icons CC0 note (icons are original tracings — `CodeReferenceIcons.swift:1-4`) |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Assets.xcassets/ClaudeLogo.imageset/Claude_AI_symbol.svg` | 7 lines / 4 KB | Claude brand mark — header empty state `ClaudeSessionView.swift:177`, streaming pulse `:367` |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Assets.xcassets/ClaudeLogo.imageset/Contents.json` | 15 lines | imageset metadata |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Assets.xcassets/GitHubLogo.imageset/Contents.json` | 15 lines | imageset metadata |
| `Packages/ClaudeUI/Sources/ClaudeUI/Resources/Assets.xcassets/GitHubLogo.imageset/github.svg` | 0 lines / 822 B | GitHub brand mark (placeholder content) — code draft repo chips `ClaudeCodeDraftView.swift:58,63-64` |
| `Packages/ClaudeUI/Sources/ClaudeWidgets/Resources/WidgetAssets.xcassets/ClaudeLogo.imageset/Claude_AI_symbol.svg` | 7 lines / 4 KB | Widget mark — `WidgetViews.swift:15` |
| `Packages/ClaudeUI/Sources/ClaudeWidgets/Resources/WidgetAssets.xcassets/ClaudeLogo.imageset/Contents.json` | 15 lines | imageset metadata |

### 1o. Files outside both target roots (for completeness)

`Packages/ClaudeUI/Tests/ClaudeUITests/` — 9 suites: `ArtifactStateTests`, `CodeHighlighterTests`, `MarkdownTableTests`, `MarkdownTests`, `MediaTests`, `ProjectStateTests`, `SessionStateTests`, `SettingsStateTests`, `WidgetPresentationTests`. `Examples/ClaudeUIDemo` references nearly every public view (e.g. `Demo/DemoScreens.swift`, `Demo/ClaudeDemoApp.swift`, `Demo/DemoFixtures.swift`, `SnapshotTests/`, `UITests/`). The demo and the integration guide document every screen; both must move with any deletion (see Section 4).

---

## 2. `SessionState` inventory — every property and every action

All line references are `Packages/ClaudeUI/Sources/ClaudeUI/SessionState.swift` unless noted. `SessionState` is a plain value reduced by `reduce(_:)` (`:120-289`); `appendResponse` (`:291-298`) and `finishResponse` (`:299-304`) are the streaming entry points.

### 2.1 Properties (`:63-102`, computed at `:103-113`)

| Property | Line | Type | Read by | Emits via |
|---|---|---|---|---|
| `settings` | 64 | `ClaudeSettingsState` | `ClaudeSessionView.swift:123,736` (avatar initials), `SettingsState.swift:64` | `.settings(...)` |
| `appearance` | 65 | `ClaudeAppearance` | `ClaudeSessionView.swift:114,123`, `ClaudeSettingsView.swift:12,57`; `ThemeThumbnail` | `.settings(.setAppearance)` (`.settings` reducer mirrors it back, `:234`) |
| `draft` | 66 | `String` | `ClaudeSessionView.swift:442-445,483` (`TextField`/`send`), `canSend` `:103-107` | direct `$state.draft` binding (`ClaudeSessionView.swift:443`); `.attach/.removeAttachment/.beginEditing/.cancelEditing/.commitDictation` |
| `messages` | 67 | `[ChatMessage]` | `ClaudeSessionView.swift:174,213,373,444,754`; `SessionState.swift:108-113`; `ClaudeSharedLinksState` mirrors the shape `SharedLinksState.swift:8` | `.send` (`:140`), `.retry` (`:274`); demo writes it directly `ClaudeSessionView.swift:754` |
| `phase` | 68 | `ComposerPhase` | `ClaudeSessionView.swift:314,366,450,454,476,477,480,571`; `ClaudeSessionView.swift:299`; `SessionState.swift:103,105,122,148,177,183,194,200,272,278` | set by `.send` (`:146`), `.stop` (`:174`), dictation cases (`:182,192,199,205`), `.retry` (`:275`) |
| `responseID` (private(set)) | 69 | `UUID?` | `SessionState` internally (`:292,300`); host reads after `.send`/`.retry` to key chunks (README example) | `.send`/`.retry` create it; `.stop` nils it |
| `model` | 70 | `ClaudeModel` | `ClaudeSessionView.swift:127,467,527`; `ClaudeSheets.swift:125`; `ClaudeCodeDraftView.swift:91,163`; `ClaudeVoiceSettingsSheet.swift:69` | `.selectModel` (`:265`) |
| `effort` | 71 | `Effort` | `ClaudeSessionView.swift:468`; `ClaudeSheets.swift:98,125` | `.selectEffort` (`:266`) |
| `automaticApproval` | 72 | `Bool` | `ClaudeSheets.swift:154,163,246` | `.setAutomaticApproval` (`:267`) |
| `deviceEnabled` | 73 | `Bool` | `ClaudeSheets.swift:174,251` | `.setDeviceEnabled` (`:268`) |
| `devices` | 74 | `DeviceState` | `ClaudeSessionView.swift:120` | `.devices(...)` (`:236`) |
| `dispatch` | 75 | `DispatchState` | `ClaudeSessionView.swift:83-85,100,108-110` | `.openDispatch` / `.dispatch(...)` (`:257-264`) |
| `code` | 76 | `CodeState` | `ClaudeSessionView.swift:73,95` | `.openCode` / `.code(...)` (`:251-257`) |
| `artifacts` | 77 | `ArtifactsState` | `ClaudeSessionView.swift:87-89` | `.openArtifacts` / `.artifacts(...)` (`:237-243`) |
| `showingArtifacts` (private(set)) | 78 | `Bool` | `ClaudeSessionView.swift:73,86-89` | `.openArtifacts` (`:237-243`), `.openProjects` (`:245`), `.openCode` (`:252`), `.openDispatch` (`:259`) |
| `projects` | 79 | `ProjectState` | `ClaudeSessionView.swift:92-94` | `.openProjects` / `.projects(...)` (`:244-250`) |
| `showingProjects` (private(set)) | 80 | `Bool` | `ClaudeSessionView.swift:73,90` | mirrors the open cases |
| `showingCode` (private(set)) | 81 | `Bool` | `ClaudeSessionView.swift:73,94` | mirrors the open cases |
| `showingDispatch` (private(set)) | 82 | `Bool` | `ClaudeSessionView.swift:79,82,100,109` | mirrors the open cases |
| `temporary` | 83 | `Bool` | `ClaudeSessionView.swift:178,215,222-223`; `.toggleTemporary` (`:269`) resets via `.newSession` | `.toggleTemporary` (`:269`) |
| `voiceActive` (private(set)) | 84 | `Bool` | `ClaudeSessionView.swift:155,188,206,316,352,358,502-551`; `ClaudeSessionView.body` (`:155-160`); `SessionState.swift:148,278` | `.startVoice` (`:278`), `.endVoice` (`:280`) |
| `voiceInputEnabled` (private(set)) | 85 | `Bool` | `ClaudeSessionView.swift:509,512` | `.toggleVoiceInput` (`:283`), `.endVoice` (`:281`) |
| `voiceOutputMuted` (private(set)) | 86 | `Bool` | `ClaudeSessionView.swift:536,540` | `.toggleVoiceOutput` (`:284`), `.endVoice` (`:282`) |
| `voice` | 87 | `ClaudeVoice` | `ClaudeVoiceSettingsSheet.swift:19,31,48,55,58-63` | `.selectVoice` (`:285`) |
| `voiceLanguage` | 88 | `String` | `ClaudeVoiceSettingsSheet.swift:81-86` | `.selectVoiceLanguage` (`:286`) |
| `attachments` | 89 | `[String]` | `ClaudeSessionView.swift:425-441`; `canSend` | `.attach` (`:270`), `.removeAttachment` (`:271`), `.send` (`:143`), `.beginEditing` (`:159`), `.cancelEditing` (`:164`) |
| `media` | 90 | `ClaudeMediaState` | `ClaudeSessionView.swift:134-148` (full-screen/sheet viewers), `:397-423` (tray); `ClaudeSheets.swift:215,223,231,259,271`; `canSend` | `.media(...)` (`:235`) |
| `transcript` | 91 | `String` | `ClaudeSessionView.swift` indirectly via `dictationControls`; `SessionState.swift:186,197,202` | dictation reducer cases (`:177-205`) |
| `dictationLevels` | 94 | `[Double]` | `ClaudeSessionView.swift:557,567` | host-supplied; clamped by didSet via `DictationWaveformMetrics.normalized` (`:95`) |
| `editingMessageID` (private(set)) | 97 | `UUID?` | `ClaudeSessionView.swift:302,382`; `SessionState.swift:108-113,129,149,161,272,278` | `.beginEditing` (`:157`), `.cancelEditing` (`clearEditing` `:171`), `.send` (`:137-138`) |
| `draftBeforeEditing` (private) | 98 | `String` | internal (`:163`) | `.beginEditing` (`:153`), `.cancelEditing` (`:163`) |
| `attachmentsBeforeEditing` (private) | 99 | `[String]` | internal (`:164`) | `.beginEditing` (`:154`), `.cancelEditing` (`:164`) |
| `mediaBeforeEditing` (private) | 100 | `[ClaudeMedia]` | internal (`:165`) | `.beginEditing` (`:155`), `.cancelEditing` (`:165`) |
| `draftBeforeDictation` (private(set)) | 101 | `String` | internal (`:179,187,196,202`) | `.startDictation` (`:179`) |
| `canSend` (computed) | 103-107 | `Bool` | `ClaudeSessionView.swift:480` | — |
| `visibleMessages` (computed) | 108-113 | `[ChatMessage]` | `ClaudeSessionView.swift:253` | — |

\* `state.phase != .idle` guards the dictation button at `ClaudeSessionView.swift:476`; `state.phase != .streaming` gates the response footer buttons at `ClaudeSessionView.swift:314-358`.

### 2.2 `ClaudeAction` cases (`SessionState.swift:45-61`) — reducer arm + emitters

| Case | Reducer | Emitted by (file:line) |
|---|---|---|
| `.send(String)` | `:122-147` (creates user message, `phase = .streaming`, `responseID = UUID()`) | `ClaudeSessionView.swift:483` |
| `.stop` | `:172-176` | `ClaudeSessionView.swift:478` |
| `.startDictation` | `:177-182` | `ClaudeSessionView.swift:475` |
| `.stopDictation` | `:183-193` | `ClaudeSessionView.swift:572` |
| `.cancelDictation` | `:194-199` | `ClaudeSessionView.swift:554` |
| `.commitDictation` | `:200-205` | `ClaudeSessionView.swift:576` |
| `.newSession` | `:206-231` (preserves feature states, resets transcript) | `ClaudeSessionView.swift:232` (header), `:241` (Menu "Delete"), `:742` (sidebar), `:753` (session row) |
| `.selectModel(ClaudeModel)` | `:265` | `ClaudeSheets.swift:118` (model sheet, also voice-context), `ClaudeVoiceSettingsSheet.swift:69` (via `ClaudeModelSheet`) |
| `.selectEffort(Effort)` | `:266` | `ClaudeSheets.swift:101` |
| `.setAutomaticApproval(Bool)` | `:267` | `ClaudeSheets.swift:156` (manual), `:165` (automatic) |
| `.setDeviceEnabled(Bool)` | `:268` | `ClaudeSheets.swift:175` |
| `.toggleTemporary` | `:269` | `ClaudeSessionView.swift:215` |
| `.startVoice` | `:278` | `ClaudeSessionView.swift:492` |
| `.attach(String)` | `:270` | `ClaudeSheets.swift:185` (Add to project), `:199` (sample), `:276` (camera capture) |
| `.removeAttachment(String)` | `:271` | `ClaudeSessionView.swift:430` |
| `.beginEditing(UUID)` | `:148-160` | `ClaudeSessionView.swift:297` |
| `.cancelEditing` | `:161-171` | `ClaudeSessionView.swift:388` |
| `.devices(DeviceAction)` | `:236` | `ClaudeSessionView.swift:120` (`onAction(.devices($0))`) |
| `.openDispatch` | `:257-264` | `ClaudeSessionView.swift:668` (`openDestination("Dispatch")`) |
| `.dispatch(DispatchAction)` | `:264` | `ClaudeSessionView.swift:85` |
| `.openCode` | `:251-256` | `ClaudeSessionView.swift:676` (`openDestination("Code")`) |
| `.code(CodeAction)` | `:257` | `ClaudeSessionView.swift:95` |
| `.openArtifacts` | `:237-243` | `ClaudeSessionView.swift:671` (`openDestination("Artifacts")`) |
| `.artifacts(ArtifactAction)` | `:243` | `ClaudeSessionView.swift:88` |
| `.openProjects` | `:244-250` | `ClaudeSessionView.swift:674` (`openDestination("Projects")`) |
| `.projects(ProjectAction)` | `:250` | `ClaudeSessionView.swift:93` |
| `.settings(ClaudeSettingsAction)` | `:232-235` (also writes `appearance`) | `ClaudeSessionView.swift:125` |
| `.media(ClaudeMediaAction)` | `:235` | `ClaudeSessionView.swift:258,273,403,413` (`open`, `copyFileName`, `open`, `removeDraft`); media viewer `:139`; `ClaudeSheets.swift:147,217,261,271` (`requestPhotos`, `toggleRecent`, `attachSelected`, `begin/cancelSelection`) |
| `.markdown(UUID, MarkdownAction)` | `:287` (no-op reducer) | `ClaudeSessionView.swift:312` |
| `.voiceFeedback(Bool)` | `:287` (no-op) | `ClaudeSessionView.swift:638` |
| `.endVoice` | `:279-283` | `ClaudeSessionView.swift:613` (`endVoice()`) |
| `.toggleVoiceInput` | `:283-284` | `ClaudeSessionView.swift:507` |
| `.toggleVoiceOutput` | `:284` | `ClaudeSessionView.swift:534` |
| `.selectVoice(ClaudeVoice)` | `:285` | `ClaudeVoiceSettingsSheet.swift:21`, `:59` (`scrollPosition` binding) |
| `.selectVoiceLanguage(String)` | `:286` | `ClaudeVoiceSettingsSheet.swift:81` |
| `.copy(UUID)` | `:287` (no-op) | `ClaudeSessionView.swift:287`, `:321` |
| `.share(UUID)` | `:287` (no-op) | `ClaudeSessionView.swift:332` |
| `.readAloud(UUID)` | `:287` (no-op) | `ClaudeSessionView.swift:339` |
| `.feedback(UUID, FeedbackSubmission)` | `:287` (no-op) | `ClaudeSessionView.swift:152` (feedback sheet submit) |
| `.retry` | `:272-277` | `ClaudeSessionView.swift:353` |

Views that **read** the composer/stream surface: the composer block `ClaudeSessionView.swift:380-503`, dictation `:552-579`, voice overlay `:504-551`, `header` `:195-248`, transcript `:249-379`, root switch `:81-99`. Details and the streaming path are Section 5.

### 2.3 Nested action enums — cases and emitters

All nested enums are `@nonexhaustive`. Emitter lines point at the `action(...)`/`onAction(...)` call sites.

**`DeviceAction`** (`DeviceState.swift:44-48`) ← `ClaudeDevicesView.swift`
| Case | Emitter |
|---|---|
| `.openManage` | `ClaudeDevicesView.swift:36` and `:76` ("Try again") |
| `.closeManage` | `ClaudeDevicesView.swift:44` (dismiss), `:63` |
| `.requestTab(DeviceAccountTab)` | `ClaudeDevicesView.swift:89` |
| `.editProfile(DeviceProfileField, String)` | `ClaudeDevicesView.swift:179` |
| `.openAPIDashboard` | `ClaudeDevicesView.swift:104` |
| `.chooseProfilePhoto` | `ClaudeDevicesView.swift:163` |
| `.openGuidelines` / `.learnAboutInstructions` | `ClaudeDevicesView.swift:211` (guidelines/instructions links) |
| `.logOutAllDevices` | `ClaudeDevicesView.swift:133` |
| `.requestDeleteAccount` | `ClaudeDevicesView.swift:141` |
| `.copyOrganizationID` | `ClaudeDevicesView.swift:234` |

**`DispatchAction`** (`DispatchState.swift:16`) ← `ClaudeDispatchView.swift`
| Case | Emitter |
|---|---|
| `.reload` | `ClaudeDispatchView.swift:31` |
| `.close` | not emitted by a view; SessionState emits `.dispatch(.close)` internally on open of another surface (`SessionState.swift:242,248,255,261`) |
| `.attach` | `ClaudeDispatchView.swift:87` |
| `.submit(String)` | `ClaudeDispatchView.swift:96` |

**`CodeAction`** (`CodeState.swift:38-41`) ← `ClaudeSessionView.swift:95` → `ClaudeCodeView.swift`
| Case | Emitter |
|---|---|
| `.selectFilter(CodeFilter)` | `ClaudeCodeView.swift:86` |
| `.openSession(String)` | `ClaudeCodeView.swift:105` |
| `.openDevice(String)` | `ClaudeCodeView.swift:34` |
| `.addDevice` | `ClaudeCodeView.swift:50` |
| `.copyRemoteCommand` | `ClaudeCodeView.swift:63` (via remote-setup sheet `:174`) |
| `.newSession` | `ClaudeCodeView.swift:153` |
| `.closeNewSession` | `ClaudeCodeView.swift:18` |
| `.editor(CodeDraftAction)` | `ClaudeCodeView.swift:18` |
| `.search` | `ClaudeCodeView.swift:146` |
| `.openRoutines` | `ClaudeCodeView.swift:78` |
| `.closeRoutines` | `ClaudeCodeView.swift:20` |
| `.routines(RoutineAction)` | `ClaudeCodeView.swift:20` |

**`CodeDraftAction`** (`CodeDraftState.swift:34-40`) ← `ClaudeCodeDraftView.swift`, `ClaudeCodeConfigurationSheets.swift`, `ClaudeCodeContextSheet.swift`, `ClaudeCodeConnectorsView` (via `CodeContextAction`)
| Case | Emitter |
|---|---|
| `.connectors(CodeConnectorAction)` | `ClaudeCodeContextSheet.swift:49` → `ClaudeCodeConnectorsView.swift:51,83,33,94` |
| `.context(CodeContextAction)` | `ClaudeCodeContextSheet.swift:55 (photos),93 (camera),103 (samplePhoto),112 (files),60 (selectPermission),120 (connectors)` |
| `.selectBranch(String)` | `ClaudeCodeContextSheet.swift:20` (branch sheet) |
| `.environment(CodeEnvironmentAction)` | `ClaudeCodeConfigurationSheets.swift:13 (help),36 (begin),44 (cancel),60 (editName),73 (selectNetwork),97 (editVariables),107 (formatHelp),117 (create)` |
| `.selectEnvironment(String)` | `ClaudeCodeConfigurationSheets.swift:29` |
| `.selectRepository(String)` | `ClaudeCodeConfigurationSheets.swift:189` |
| `.changeBranch` | `ClaudeCodeDraftView.swift:43` |
| `.searchRepositories` | `ClaudeCodeConfigurationSheets.swift:168` |
| `.connectRepositories` | `ClaudeCodeConfigurationSheets.swift:177` |
| `.edit(String)` | `ClaudeCodeDraftView.swift:73` |
| `.selectModel(ClaudeModel)` | `ClaudeCodeDraftView.swift:163` (`ClaudeCodeModelSheet`) |
| `.selectEffort(CodeEffort)` | `ClaudeCodeDraftView.swift:147` |
| `.chooseEnvironment` | `ClaudeCodeDraftView.swift:33` |
| `.chooseRepository` | `ClaudeCodeDraftView.swift:54` |
| `.attach` | `ClaudeCodeDraftView.swift:79` |
| `.dictate` | `ClaudeCodeDraftView.swift:97` |
| `.submit(CodeDraftState)` | `ClaudeCodeDraftView.swift:104` |

**`CodeContextAction`** (`CodeDraftState.swift:31-33`) ← `ClaudeCodeContextSheet.swift`
`.photos` (trailing `:55`), `.camera` (`:93`), `.files` (`:112`), `.connectors` (`:120`), `.samplePhoto(Int)` (`:102`), `.selectPermission(CodePermission)` (`:60`).

**`CodeConnectorAction`** (`CodeConnectorState.swift:52-54`) ← `ClaudeCodeConnectorsView.swift`
`.discovery(Bool)` (`:83`), `.add` (`:33`), `.connect(String)` (`:94`), `.permission(connector:tool:value:)` (`:51`).

**`CodeEnvironmentAction`** (`CodeEnvironmentState.swift:28-31`) ← `ClaudeCodeConfigurationSheets.swift`
`.begin` (`:36`), `.cancel` (`:44,55`), `.editName(String)` (`:60`), `.editVariables(String)` (`:97`), `.selectNetwork(CodeNetworkAccess)` (`:73`), `.create(CodeEnvironmentDraft)` (`:117`), `.formatHelp` (`:107`), `.help` (`:13`).

**`RoutineAction`** (`RoutineState.swift:36-40`) ← `ClaudeRoutinesView.swift`
`.newRoutine` (`:57`), `.cancel` (`:64,76`), `.manualSetup` (`:101`), `.backToDescription` (`:76`), `.edit(RoutineField, String)` (`:248`), `.draftRoutine(String)` (`:91`), `.openOption(RoutineOption)` (`:125,142,165`), `.selectFilter(RoutineFilter)` (`:21`), `.create(RoutineDraft)` (`:169`), `.addSchedule` (`:162`), `.removeSchedule` (`:195`), `.toggleSchedule` (`:181`), `.setRepeat(RoutineRepeat)` (`:208`), `.setTime(hour:minute:)` (`:224`).

**`ClaudeSettingsAction`** (`SettingsState.swift:46-62`) ← `ClaudeSettingsView.swift`, `ClaudeNotificationSettingsView.swift`
| Case | Emitter |
|---|---|
| `.open(ClaudeSettingsDestination)` | `ClaudeSettingsView.swift:410`, `:191` (`.account`), `:209 (.gift)`, `:207 (.addAccount)` |
| `.back` | `ClaudeSettingsView.swift:107` |
| `.close` | `ClaudeSettingsView.swift:98` (close), `:59` (`onDisappear`) |
| `.infoLink(ClaudeSettingsInfoLink)` | `ClaudeSettingsView.swift:171` |
| `.editProfile(ClaudeProfileField, String)` | `ClaudeSettingsView.swift:359` |
| `.submitProfile` | `ClaudeSettingsView.swift:143` |
| `.chooseAvatar` / `.requestPhotoLibrary` / `.requestCamera` | `ClaudeSettingsView.swift:284,291,296` |
| `.openInstructions` | `ClaudeSettingsView.swift:317` |
| `.editInstructions(String)` | `ClaudeSettingsView.swift:391` |
| `.cancelInstructions` / `.applyInstructions` | `ClaudeSettingsView.swift:367,376` |
| `.billing(ClaudeBillingAction)` | `ClaudeSettingsView.swift:31` |
| `.sharedLinks(ClaudeSharedLinksAction)` | `ClaudeSettingsView.swift:33` |
| `.connector(ClaudeSettingsConnectorAction)` | `ClaudeSettingsView.swift:35,62,66,101,124,119` |
| `.capability(ClaudeCapabilityAction)` | `ClaudeSettingsView.swift:37` |
| `.memory(ClaudeMemoryFilesAction)` | `ClaudeSettingsView.swift:39,103,135` |
| `.codePreference(ClaudeCodePreferenceAction)` | `ClaudeSettingsView.swift:41` |
| `.usage(ClaudeUsageAction)` | `ClaudeSettingsView.swift:43,151,157` |
| `.privacy(ClaudePrivacyAction)` | `ClaudeSettingsView.swift:45` |
| `.timeFocus(ClaudeTimeFocusAction)` | `ClaudeSettingsView.swift:47` |
| `.setNotification(ClaudeNotificationPreference, Bool)` | `ClaudeNotificationSettingsView.swift:28` |
| `.setHaptics(Bool)` | `ClaudeSettingsView.swift:237` |
| `.setAppearance(ClaudeAppearance)` | `ClaudeSettingsView.swift:247` |
| `.requestDeleteAccount` | `ClaudeSettingsView.swift:341` |
| `.requestLogOut` | `ClaudeSettingsView.swift:264` |
| `.openGuidelines` | `ClaudeSettingsView.swift:336-339` (openURL interceptor) |
| `.editPhoto` | not emitted by any view (reserved) |

**`ClaudeBillingAction`** (`BillingState.swift:4-6`) ← `ClaudeBillingSettingsView.swift`
`.requestManage` (`:19`), `.requestRestore` (`:21`), `.requestWebsiteManagement(URL?)` (`:28`), `.dismissNotice` (`:26`, `:29`).

**`ClaudeSharedLinksAction`** (`SharedLinksState.swift:27-29`) ← `ClaudeSharedLinksView.swift`, `ClaudeSettingsView.swift:104`
`.open(String)` (`ClaudeSharedLinksView.swift:20`), `.back` (`ClaudeSettingsView.swift:104`), `.markdown` (`ClaudeSharedLinksView.swift:51`).

**`ClaudeSettingsConnectorAction`** (`SettingsConnectorState.swift:3-9`) ← `ClaudeSettingsConnectorsView.swift`, `ClaudeSettingsView.swift`
`.openConnector(String)`/`.requestConnect(String)` (`:58`), `.openTool(String)` (`:101`), `.openAllTools` (`:86`), `.openCatalog` (`ClaudeSettingsView.swift:119`), `.openCustom` (`:124`), `.back` (`ClaudeSettingsView.swift:101`), `.catalog(ClaudeConnectorCatalogAction)` (`ClaudeSettingsView.swift:62,66`), `.requestAllPermissions(connector:permission:)` (`ClaudeSettingsConnectorsView.swift:139`), `.requestDiscovery(Bool)` (`:50`), `.requestCatalog` (no emitter found), `.requestAllTools(String)` (no emitter found), `.requestPermission(connector:tool:permission:)` (`:136-137`).

**`ClaudeConnectorCatalogAction`** (`ConnectorCatalogState.swift:52-56`) ← `ClaudeConnectorCatalogView.swift`
`.search(String)` (`:108`), `.sort(ClaudeConnectorCatalogSort)` (`:45`), `.category(String?)` (`:48`), `.requestConnect(String)` (`:87`), `.editName(String)` (`:118`), `.editURL(String)` (`:123`), `.requestCustom(name:url:)` (`:136`), `.dismiss` (`:28`).

**`ClaudeCapabilityAction`** (`CapabilitiesState.swift:53-55`) ← `ClaudeCapabilitiesView.swift`
`.requestEnabled(ClaudeCapability, Bool)` (`:79`), `.openHelp(ClaudeCapability, URL?)` (`:50`), `.openMemoryFiles` (`:26`).

**`ClaudeMemoryFilesAction`** (`MemoryFilesState.swift:35-40`) ← `ClaudeMemoryFilesView.swift`, `ClaudeSettingsView.swift`
`.open(String)` (`UIView :35`), `.back` (`ClaudeSettingsView.swift:103`), `.close` (none — reserved), `.editDraft(String)` (`:79`), `.replaceDraft(String)` (none — reducer-internal via `reduce(.editDraft)`), `.submitInstruction(fileID:text:)` (`:85`), `.askDelete` (`ClaudeSettingsView.swift:135`), `.cancelDelete` (`UIView :60,61`), `.confirmDelete` (`UIView :62`), `.markdown` (`UIView :23`).

**`ClaudeCodePreferenceAction`** (`CodePreferences.swift:9-12`) ← `ClaudeCodeSettingsView.swift`
`.transcriptSizePosition(Double)` (`:15`), `.transcriptFont(ClaudeTranscriptFontChoice)` (`:36`), `.codeFont(ClaudeCodeFontChoice)` (`:53`), `.wrapLongLines(Bool)` (`:63`).

**`ClaudeUsageAction`** (`UsageState.swift:37-40`) ← `ClaudeUsageSettingsView.swift`, `ClaudeSettingsView.swift:151,157`
`.refresh` (`ClaudeSettingsView.swift:151`), `.requestCreditsEnabled(Bool)` (`:33`), `.requestPurchase` (`:55`), `.openLink(ClaudeUsageLink, URL?)` (`ClaudeUsageSettingsView.swift:69`, `ClaudeSettingsView.swift:157`).

**`ClaudePrivacyAction`** (`PrivacyState.swift:13-16`) ← `ClaudePrivacySettingsView.swift`
`.requestModelImprovement(Bool)` (`:27`), `.openLink(ClaudePrivacyLink, URL?)` (`:41`).

**`ClaudeTimeFocusAction`** (`TimeFocusState.swift:8-10`) ← `ClaudeTimeFocusView.swift`
`.selectHours(Int?)` (`:81`), `.selectMinutes(Int?)` (`:81`), `.quietDayTapped(ClaudeWeekday)` (`:39`).

**`ClaudeNotificationPreference` / `.setNotification(_, _)`** — toggles rendered from `ClaudeNotificationPreference.groups` (`NotificationPreferences.swift:27-31`) at `ClaudeNotificationSettingsView.swift:13-37`.

**`ProjectAction`** (`ProjectState.swift:29-35`) ← `ClaudeProjectsView.swift`, `ClaudeProjectEditorView.swift`
`.begin` (`:89`), `.continueIntroduction` (`:63`), `.cancel` (`:80`, via sheet binding `:96`), `.selectFilter(ProjectFilter)` (`:35`), `.openArchived` (`:41`), `.editName(String)` (`:126`), `.editGoal(String)` (`:142`), `.selectIcon(String)`/`.selectIconColor(String)` (`:18-21`), `.addContext(String)` (`:192`, `:244`), `.removeContext(String)` (`:183`), `.selectEnvironment(String)` (`:211`), `.openIconPicker` (`:111`), `.openContext` (no direct emitter; menu gates `openContextSource`), `.openContextSource(String)` (`:151,162`), `.openEnvironment` (menu is bound directly to `selectEnvironment`), `.openFilter` (no emitter; the filter menu in `ClaudeProjectsView.swift:34` emits `selectFilter`), `.openProject(UUID)` (`:73`), `.create(ProjectDraft)` (`:94`).

**`ArtifactAction`** (`ArtifactState.swift:67-72`) ← `ClaudeArtifactsView.swift`
`.ownership(ArtifactOwnership)` (`:39`), `.kind(ArtifactKind)` (`:45`), `.search(String)` (`:85`), `.open(String)` (`:60`), `.close` (`:118`), `.toggleTitle` (`:160`), `.toggleSection(String)` (`:182`), `.markdown` (`:192`), `.share(String)` (`:135`), `.comments(String)` (`:132`), `.tabs(String)` (`:141`), `.undo(String)` (`:126`), `.redo(String)` (`:129`).

**`ClaudeMediaAction`** (`MediaState.swift:26-31`) ← `ClaudeSessionView.swift`, `ClaudeSheets.swift`, `ClaudeMediaView.swift`
`.beginSelection`/`.cancelSelection` (`ClaudeSheets.swift:271`), `.toggleRecent(String)` (`ClaudeSheets.swift:217`), `.attachSelected` (`ClaudeSheets.swift:261`), `.removeDraft(String)` (`ClaudeSessionView.swift:413`), `.open(ClaudeMedia)` (`ClaudeSessionView.swift:258,403`), `.close` (`ClaudeMediaView.swift:33,107` and the binding setters `ClaudeSessionView.swift:137,145`), `.toggleControls` (`ClaudeMediaView.swift:62`), `.requestPhotos` (`ClaudeSheets.swift:147`), `.copyFileName(ClaudeMedia)` (`ClaudeSessionView.swift:273`), `.edit(ClaudeMedia)` (`ClaudeMediaView.swift:43`), `.share(ClaudeMedia)` (`ClaudeMediaView.swift:48`), `.download(ClaudeMedia)` (`ClaudeMediaView.swift:116`), `.videoViewerAppeared(ClaudeMedia)`/`.videoViewerDisappeared(ClaudeMedia)` (`ClaudeMediaView.swift:124`).

**`MarkdownAction`** (`MarkdownDocumentModel.swift:115-118`) ← `ClaudeMarkdownView.swift`, `ClaudeSelectableInlineCode.swift`, emitted through `.markdown(...)` / `.markdown($0)` in artifacts/memory/shared links
`.openLink(URL)` (`ClaudeMarkdownView.swift:101`), `.copyCode(String)` (`:169`), `.expandCode(language:content:)` (`:174`), `.image(MarkdownImage)` (encoded in presentation URLs `:124-128,302-304`), `.unsupported(kind:source:)` (`:221`).

**`CameraAction`** (`CameraState.swift:15-17`) ← `ClaudeCameraView.swift`
`.selectMode(CameraMode)` (`:79`), `.selectZoom(Double)` (`:108`), `.cycleFlash` (`:33`), `.flip` (`:92`), `.shutter` (`:49`), `.cancel` (`:68`).

---

## 3. The decision table

Verdicts: **KEEP** (works for Paseo as-is/re-skinned), **ADAPT** (maps to the named Paseo feature; needs the named PaseoStore data), **DELETE** (Claude-only). Paseo UI labels are quoted from `docs/research/01-app-features.md` ("doc 01") section titles/labels as it shows them in the app. "PaseoStore data" names the existing source (`HostSession.swift`, `ConversationStore` = `HostSession.swift:209-424`) or what must be added (\* = store/protocol work still pending, noted in the research docs).

| # | Screen / feature (ClaudeUI) | Verdict | Paseo feature + UI labels (doc 01) | PaseoStore data needed |
|---|---|---|---|---|
| 1 | Chat transcript — `ClaudeSessionView.swift:249-379` | ADAPT | **Agents & chat** — the streamed timeline (`agent-stream/view.tsx`); agents open as workspace tabs | `ConversationStore.turns` (`HostSession.swift:223`), `activeTurnId` (`:226`), `agent.status` (`Agents.swift:36`), `TimelineRow`/`TimelineItem` (`Timeline.swift:10`) |
| 2 | User bubble + media row — `ClaudeSessionView.swift:254-308` | ADAPT | **Agents & chat** — user message; attachments render in-line | `turn.userMessage` (`Turn.swift:14`), `TimelineItem.userMessage(UserMessage)` (`Timeline.swift:11,22-29`); row id stability for pending echo (`TimelineState.swift:59-72,131-139`); attachments \*see §3 note |
| 3 | Assistant prose — `ClaudeMarkdownView.swift:36-314` + `MarkdownDocumentModel.swift:5-149` + `ClaudeCodeHighlighter.swift:8-51` + `ClaudeSelectableInlineCode.swift:7-151` + `MarkdownTableMetrics.swift:5-64` | KEEP | **Agents & chat** — assistant message body (Markdown) | `turn.segments[.prose(row)]` (`Turn.swift:35`); nothing store-side |
| 4 | Work segment (reasoning + tool calls, collapsible) — `Turn.work` shape; **no ClaudeUI counterpart** | ADAPT (build new, ClaudeUI style) | **Tool calls** — "edited N files / ran N commands / read N files / Thought", collapsible Input/Output; **Turn collapse**, **Chat display** setting (Full / Collapse tool calls / Collapse turns); **Worked for {{duration}}** | `Turn.WorkGroup` (`Turn.swift:48-57`), `summary` (`Presentation.swift:69-76`), `ToolCallPresentation` (`Presentation.swift:6-67`) |
| 5 | Composer input — `ClaudeSessionView.swift:442-453,380-503` | ADAPT | **Composer & attachments** — placeholder "Message the agent, tag @files…"; hardware-keyboard send | `ConversationStore.draft` (`HostSession.swift:231`), `.send(_:)` (`:287-313`), `.isRunning` (`:237`) |
| 6 | Composer attachment tray — `ClaudeSessionView.swift:425-441`; attachments sheet — `ClaudeSheets.swift:134-291` | ADAPT | **Composer & attachments** — "Attachment tray", "Add attachment" ("Add image", "Paste image", "Upload file", "Add issue or PR"), "Attachment actions" | Media protocol \* — `SendAgentMessageRequest` has no attachment field yet (`Agents.swift:119-127`); `file.upload.request` + inline images researched (04 §10); store work pending |
| 7 | Send / Stop / queue — `ClaudeSessionView.swift:477-484`, `SessionState.swift:146-147,172-176` | ADAPT | **Composer** — "**Send message**", "**Stop**" ("Interrupt agent"), "**Queue message**", "**Send and steer** / **Send and interrupt**" | `ConversationStore.send` (steer when running — already implemented `HostSession.swift:299-304`), `.cancel()` (`:316-328`), `activeTurnBehavior` (`Agents.swift:122`) |
| 8 | Dictation — `ClaudeSessionView.swift:552-579`, `DictationWaveformMetrics` | ADAPT | **Voice & dictation** — "**Dictation**" mic overlay: timer, volume meter, "Cancel dictation / Insert transcription / Insert transcription and send" | Dictation host service + `session.dictationLevels` equivalent \* (host-supplied levels; no audio in package by design — `SessionState.swift:92-96`) |
| 9 | Voice mode overlay — `ClaudeSessionView.swift:504-551`, `voiceControls`, `voiceEndedToast` | ADAPT | **Voice mode** — realtime overlay (volume meter, mute, interrupt **Square**), "**Mute Voice mode** / **Unmute Voice mode**" | Realtime voice runtime \* (`voice/voice-runtime.ts` in reference); settings host → **Voice** page (doc 01); no Paseo voice store yet |
| 10 | Edit sent message — `SessionState.swift:148-171`, `ClaudeSessionView.swift:382-396,296-307` ("Editing this message…"), `visibleMessages` truncation (`SessionState.swift:108-113`) | DELETE | Paseo has **no** edit-of-sent-user-message; nearest: "**Edit queued message**" (not built yet) and "**Rewind conversation**" (`Rewind`) | — |
| 11 | Temporary session — `SessionState.swift:83,269`, `ClaudeSessionView.swift:178,214-223`, `GhostShape` `:785-804` | DELETE | No Paseo equivalent (Claude/ChatGPT-only affordance) | — |
| 12 | Model picker — `ClaudeSheets.swift:80-133` | ADAPT | **Providers, models & modes** — model chip → model browser ("Search models…", **Profiles** section); composer agent controls (provider badge → **Select agent provider**) | `AgentSnapshot.provider`/`.model`, `.availableModes`, `.currentModeId` (`Agents.swift:31,34,41-42`); `list_provider_models/providers_snapshot` \* (04 §8); `set_agent_model_request`, `agent.config.apply.request` \* (04 §3.2, §3.5) |
| 13 | Effort picker — `ClaudeSheets.swift:93-110` | ADAPT | **Providers, models & modes** — thinking chip → **Thinking** combobox ("Select thinking option ({{value}})") | `set_agent_thinking_request` \* (04 §3.3); thinking options per provider from provider snapshot \* |
| 14 | Approval / mode chips — `ClaudeSheets.swift:243-247,150-167` ("Permission / Select mode / Manually/Automatically approve"); `CodePermission` (`CodeDraftState.swift:28-30`), `ClaudeCodeContextSheet.swift:57-89` | ADAPT | **Providers, models & modes** — mode chip → **Mode** sheet ("Search modes…"), icon-only chips, "Cycle agent mode" shortcut, **Plan mode** | `AgentSnapshot.availableModes`/`.currentModeId` (`Agents.swift:33-42`); `set_agent_mode_request` \* (04 §3.1); modes are provider-defined, not Claude's Auto/Accept edits/Plan verbatim — render via `AgentMode.label/icon` |
| 15 | Sidebar drawer — `ClaudeSessionView.swift:683-750` (`UnequalMenu` `:775-784`), static groups + pinned/recents rows `:700-730` | ADAPT | **Workspaces & projects → Left sidebar** — "Navigation rows" (**New workspace**, **History**, **Search**, **Schedules**), "**Pinned**", "Projects & workspaces list", "**Display preferences**" | `HostSession.agents` (`HostSession.swift:17`), `projects` placements (`:19,93-97`), `AgentSnapshot.title/cwd/status/attentionReason` (`Agents.swift:29-50`); needs sidebar-pin store \* and workspace stores \* (coming, per task brief) |
| 16 | Workspace rows in sidebar (static "Weekend reading list" etc.) — `ClaudeSessionView.swift:711-730`, `sessionRow` `:751-764` | ADAPT | **Workspace row** — name (**Title** / branch), status bucket dot (**Needs input**/**Failed**/**Ready to review**/**Working**/**Done**), service health, pin toggle | `AgentSnapshot.title`/`.cwd`/`.status`/`.lastUserMessageAt`/`.requiresAttention`/`.attentionReason` (`Agents.swift:32,35-36,39,46,48`); pin/reorder is device-local \*; worktree/branch/diff-stat/PR meta need workspace+git stores \* |
| 17 | Header "new session" button — `ClaudeSessionView.swift:230-237` | ADAPT | **New workspace** — the **Create** flow; or quick **New agent** tab | `CreateAgentRequest` path \* (04 §1) or seed a draft in a new workspace; new-workspace isolation/branch fields per doc 01 §New workspace |
| 18 | Devices (header laptop button) — `ClaudeSessionView.swift:224-229` | ADAPT | **Hosts & pairing** — "**Switch host**" picker; "**Pair device**"; sidebar footer **Hosts** picker ("All hosts") | `HostSession.connection`, `.serverInfo` (`HostSession.swift:14-15`); host list comes from app-level host store \* (not in PaseoStore yet) |
| 19 | Devices screen (rows/manage/account) — `ClaudeDevicesView.swift:4-255`, `DeviceState.swift:51-90` | DELETE | No Paseo equivalent (Claude Desktop app management + account). Paseo's per-host pages are **Settings → host** sections; "Connected hosts" lives in **About** | — |
| 20 | Dispatch — `ClaudeDispatchView.swift:4-140`, `DispatchState.swift:18-50` | DELETE | No Paseo equivalent (Claude's mobile→desktop task relay). Closest Paseo concepts: **Schedules** (agents on cadence), **Import session**, attention notifications — none is Dispatch | — |
| 21 | Code sessions list ("Sessions" w/ filter) — `ClaudeCodeView.swift:25-165`, `CodeState.swift:43-82` | ADAPT | **Agents & chat → Agent list / History** — "**History**" screen ("Search history", date sections Recent/Today/Yesterday…) + **Pinned** filter; **Archived** badge | `HostSession.agents` (`HostSession.swift:17,83-102`); statuses map `AgentStatus` (`Agents.swift:6-17`) onto Code's All/Needs input/Ready for review/Working/Completed buckets; `archivedAt` filter (`:88-90`) |
| 22 | Code session detail / new session draft — `ClaudeCodeDraftView.swift:4-127` | ADAPT | **New workspace** — "Project" picker, "**Host**" picker, "**Isolation** (**Local** — reuse checkout — or **New worktree**)", "**Branch / Starting ref** picker (\"Start from…\")", "**Title (optional)**", "**What to launch**: **Chat** or **Terminal**" ("Prompt {{name}}"), "**Create**" | Project picker needs projects store \*; branch list needs git store \* (02); agent creation needs `create_agent_request` \* (04 §1); launch target via terminal \* (03) |
| 23 | Code — cloud environments — `CodeEnvironmentState.swift:3-56`, `ClaudeCodeConfigurationSheets.swift:4-134` | DELETE | No Paseo equivalent. Paseo runs on your hosts/worktrees; environment setup is `paseo.json` "Worktree lifecycle hooks" **Setup/Teardown** (doc 01 **Projects → project settings**) | — |
| 24 | Code — repositories + branches — `ClaudeCodeConfigurationSheets.swift:135-204` (repos), `ClaudeCodeContextSheet.swift:4-37` (branches), `CodeDraftState.swift:6-27` | ADAPT | **New workspace** — "**Branch / Starting ref**" picker ("Search branches and PRs"); **Git → Branch switcher**; **Projects** list per host | Branch list \* git store (protocol 02); repositories ≈ host projects (`ProjectPlacement.projectKey/projectName` — `Agents.swift:59-63`, `HostSession.swift:19`) |
| 25 | Code — connectors / tool permissions — `ClaudeCodeConnectorsView.swift:4-122`, `CodeConnectorState.swift:55-71` | ADAPT | Nearest: **Plugins** ("Settings → host → Plugins"; no per-tool permission UI exists today) and **Host → Agents** ("**Enable Paseo tools**", "**Browser tools**"). Paseo has no per-tool MCP approval UI today | Provider features via `set_agent_feature_request` / `agent.config.apply.request` \* (04 §3.4-3.5); plugins list \* plugin store (not in PaseoStore) |
| 26 | Connector catalog / add custom — `ClaudeConnectorCatalogView.swift:5-163`, `ConnectorCatalogState.swift:52-106`, `SettingsConnectorState.swift` | ADAPT (with care) | Same as #25 — closest is **Plugins** ("**Install plugin**", "**Plugin source** input"), not MCP-in-app | Plugin install/list \* (04-adjacent; daemon `plugin_catalog_changed` noted in 01 **Plugins**); the store does not exist yet |
| 27 | Routines — `ClaudeRoutinesView.swift:4-292`, `RoutineState.swift:36-97` | ADAPT | **Schedules** — "New schedule" sheet ("**Name** (optional)", "**Prompt**", "**Max runs**", "**Host**", "**Project**", "**Model**", "**Thinking**", "**Mode**", "**Archive on finish**", **Local/Worktree** isolation, **Cadence** editor), **Heartbeats** | Schedules store \* (not in PaseoStore); protocol research pending (heartbeats in `paseo-create_heartbeat` at the tooling layer, but app-side store is unbuilt); form chrome (`RoutineDraft`) adapts directly |
| 28 | Settings — root — `ClaudeSettingsView.swift:5-426` (root list + section pruning) | ADAPT | **Settings** — App group (**General**, **Appearance**, **Sidebar**, **Chat**, **Terminal**, **Browser**, **Editor**, **Files**, **Shortcuts**, **Integrations**, **Notifications**, **Permissions**, **Diagnostics**, **About**) and Host group (**Overview**, **Projects**, **Connections**, **Pair device**, **Agents**, **Metadata**, **Voice**, **Workspaces**, **Providers**, **Usage**, **Terminals**, **Plugins**); split view wide / list compact | `HostSession.serverInfo` (`HostSession.swift:15,109-114`) for the host group; settings persistence store \* (local values: chat display mode, sidebar, haptics; host values via `get_daemon_config_request`/`set_daemon_config_request` \* — 04 §12.1-12.2) |
| 29 | Settings — Account/Profile/Gift/Add account/Delete/Log out (rows in `ClaudeSettingsView.swift:189-209,264-272`, profile page `:276-351`) | DELETE | Paseo has no app account. Nearest: "**Return protocol**" none — Paseo **About** has "**Connected hosts**" + "**What's new**" and community links; **Help and support** | — (Instructions editor maps below, #30) |
| 30 | Settings — Instructions ("How you'd like Claude to respond…") — `ClaudeSettingsView.swift:315-339` | ADAPT | **Host → Agents** — "**System prompt** (**Edit**; append-system-prompt; **Reset**/**Save**)"; **Resume agents after restart** resume prompt | Host config `set_daemon_config_request` \* (04 §12.2); needs settings store \* |
| 31 | Settings — **Appearance** (Theme Light/Dark/System + `ThemeThumbnail`) — `ClaudeSettingsView.swift:244-262`, `ClaudeSheets.swift:342-368` | ADAPT | **Appearance** — **Theme**: Light, Dark, Zinc, Midnight, Claude, Ghostty, Pure black, System; per-host **Color** and **Sidebar badge**; **Fonts**, **Syntax** | Appearance store \* (device-local); host appearance via host page \* |
| 32 | Settings — **Billing** — `ClaudeBillingSettingsView.swift:4-45`, `BillingState.swift:3-25` | DELETE | No Paseo equivalent (subscription). Paseo shows usage meters (**Plan usage**) only | — |
| 33 | Settings — **Usage** — `ClaudeUsageSettingsView.swift:4-145`, `UsageState.swift:7-64` | ADAPT | **Usage** — **Plan usage**, **Summary in sidebar**, **Percentages (Used/Remaining)**, **Report cards**, **Refresh all**, **Pinned windows** in sidebar footer | `provider.usage.list.request`/`usage.list_reports.request` \* (04 §8.4); usage store \*; "**Summary in sidebar**" pinned meters \* |
| 34 | Settings — **Notifications** — `ClaudeNotificationSettingsView.swift:8-41`, `NotificationPreferences.swift:3-40` | ADAPT | **Notifications** — "**Agent attention notifications**", "**Terminal attention**", Expo push; host **Voice** unaffected | Notification preferences (device-local \*); `agent_attention_required` events \* (04 §7.1); `register_push_token` \* (04 §7.4) |
| 35 | Settings — **Time & focus** — `ClaudeTimeFocusView.swift:5-101`, `TimeFocusState.swift:3-37` | DELETE | No Paseo equivalent (Claude wellbeing) | — |
| 36 | Settings — **Privacy** — `ClaudePrivacySettingsView.swift:4-63`, `PrivacyState.swift:3-25` | DELETE | No Paseo equivalent (Anthropic training consent) | — |
| 37 | Settings — **Shared links** — `ClaudeSharedLinksView.swift:4-68`, `SharedLinksState.swift:3-44` | DELETE | No Paseo equivalent (chat sharing service) | — |
| 38 | Settings — **Capabilities** (artifacts, memory, code exec, flagged model, search chats) — `ClaudeCapabilitiesView.swift:4-97`, `CapabilitiesState.swift:3-65` | DELETE | No per-capability toggles in Paseo. The nearest home for "tools" is **Host → Agents** ("**Enable Paseo tools**", "**Browser tools**", "**Orchestration skills** (… **All skills** …)") — build that page; keep the `RowGroup + Toggle` chrome | Host agents config via `get_daemon_config_request`/`set_daemon_config_request` \* (04 §12.1-12.2) |
| 39 | Settings — **Memory files** — `ClaudeMemoryFilesView.swift:4-97`, `MemoryFilesState.swift:3-99`, `ClaudeMemoryDraftEditor.swift:6-47` | DELETE | No Paseo equivalent. Nearest: "**Orchestration skills**" install/uninstall in **Host → Agents** (host-side, not editable memory files) | — |
| 40 | Settings — **Claude Code** appearance (transcript size/font/wrap) — `ClaudeCodeSettingsView.swift:4-82`, `CodePreferences.swift:3-48` | ADAPT | **Appearance** — "**Code font**", "**Code size** (px)", "**Content size**", "**Interface size**", plus **Chat** → "**Chat display**"; wrap matches the diff options "**Wrap long lines**" | Appearance settings (device-local \*); terminal scrollback → **Terminal** ("**Terminal scrollback** (lines)") if reused there |
| 41 | Settings — **Voice** — `ClaudeVoiceSettingsSheet.swift:4-98`; Voice in root list `ClaudeSettingsView.swift:236` | ADAPT | **Host → Voice** — "**Dictation** (**Dictation** switch + **Speech-to-text** row)", "**Voice mode** (**Voice mode** switch, **Listening**, **Speaking**)", "**Speech provider sheet**" (Local/OpenAI) | Voice provider settings on host \* (daemon `daemon_config`); STT/TTS rows; per-provider keys/URLs — store work pending |
| 42 | Settings — **Connectors** (MCP permissions, discovery) — `ClaudeSettingsConnectorsView.swift:5-177` (same subtree as #25) | ADAPT | **Host → Plugins** — "**Install plugin**", "**Enable plugins**"; **Paseo tools** toggles. Paseo has **no** per-tool permission UI today — this page is a superset | `set_agent_feature_request` \* (04 §3.4); plugins \* |
| 43 | Settings — **Permissions** — dead row in `ClaudeSettingsView.swift:234` (placeholder) | DELETE | Paseo desktop-only **Permissions** (Microphone) doesn't apply to iOS; agent permission requests are **chat cards** (see §6) | — |
| 44 | Settings — **About** — no ClaudeUI destination today; the "ⓘ" info menu in the settings header (`ClaudeSettingsView.swift:163-182`) fans out `infoLink(...)` actions | ADAPT | **About** — "**App version**", "**What's new**", "**Connected hosts**" sub-section (version match/"Version differs"), community links | Device build info + `HostSession.serverInfo` (`HostSession.swift:15,109-114`) |
| 45 | Feedback (thumbs up/down + sheet) — `ClaudeSheets.swift:369-411`, `ClaudeSessionView.swift:314-357,149-154` | DELETE | **Help and support → Report an issue** (**Discord** / **Create GitHub issue**) exists as a menu; per-response rating has no Paseo meaning | — |
| 46 | Copy response/message — `ClaudeSessionView.swift:286-291,317-331` | KEEP | **Agents & chat** — "**Copy turn / Copy message**" buttons | Turn/row identity (`Turn.id`, `row.id`) — `Turn.swift:9`, `TimelineState.swift:6-21` |
| 47 | Share response — `ClaudeSessionView.swift:331-334` | DELETE | No share service. (A host MAY surface the iOS share sheet as a host intent; it is not a Paseo feature.) | — |
| 48 | Read aloud — `ClaudeSessionView.swift:335-340` | DELETE | No Paseo equivalent (voice runtime has playback, but no per-message read-aloud affordance in the reference app) | — |
| 49 | Retry response — `ClaudeSessionView.swift:352-356`, `SessionState.swift:272-277` | DELETE | No Paseo equivalent; nearest is **"Rewind conversation"** (different semantics) and "**Reload agent**" (skills/MCP/login refresh) | — |
| 50 | Voice exit feedback ("voice chat ended" + thumbs) — `ClaudeSessionView.swift:626-656`, `.voiceFeedback` (`SessionState.swift:287,45-59`) | DELETE (rating part); ADAPT (duration toast) | **Voice mode** — the exit summary is captured-only in the reference; Paseo has no rating | Remaining `voiceEndedDuration` toast shell is reusable chrome |
| 51 | Camera capture — `ClaudeCameraView.swift:6-148`, `CameraState.swift:3-50`, `SyntheticCameraPreview` `:121-147`, `ClaudeAttachmentSheet` camera page `:271-289` | DELETE | No Paseo custom camera UI. Attachments on iOS use the system camera/`UIImagePickerController`/PHPicker; "**Add image**" opens the picker | Media attachment protocol \* (04 §10); system picker is host-owned |
| 52 | Photo recents picker — `ClaudeAttachmentSheet` Photos page `ClaudeSheets.swift:191-234` | ADAPT | **Composer & attachments** — "**Add image** / **Paste image**", recent selection | `PHAsset`/PHPicker host-owned \*; `ClaudeMediaState.recent` (`MediaState.swift:33,36`) is the display shape |
| 53 | Attachment "Permission/Devices/Add to project" rows — `ClaudeSheets.swift:236-253,150-190` | ADAPT (Permission, Devices) / DELETE (project row) | Permission → **Providers, models & modes** (**Mode**) as in #14; Devices → **Hosts & pairing** as in #18; **Add to project** has no Paseo meaning in a chat | Per #14/#18; project row DELETE |
| 54 | Dispatch / artifacts / routines / code entries in sidebar — `ClaudeSessionView.swift:700-714` | Dispatch DELETE (#20) · Artifacts DELETE (#63) · **Scheduled** → **Schedules** ADAPT (#27) · **Code** → **History** ADAPT (#21) · **Projects** ADAPT (#61) | — | — |
| 55 | Home Screen widgets — `Sources/ClaudeWidgets/*` | DELETE | No Paseo widget feature or deep-link scheme yet (doc 01's Home-screen tiles are open-project, desktop). Revisit when Paseo iOS defines `paseo://` deep links | — |
| 56 | Feature announcement — `ClaudeWorkAnnouncementView.swift:6-106` | DELETE | No Paseo equivalent (Claude marketing still) | — |
| 57 | Model effort "voice" context + voice settings — `ClaudeVoiceSettingsSheet.swift:4-98`, `ClaudeSheets.swift:110-133` | ADAPT | Covered in #41 — **Listening**/**Speaking** provider rows | Same as #41 |
| 58 | Markdown + code highlighting — keep stack (`ClaudeMarkdownView`, `MarkdownDocumentModel`, `ClaudeCodeHighlighter`, `ClaudeSelectableInlineCode`, `MarkdownTableMetrics`) | KEEP | **Agents & chat** — assistant Markdown; **Tables**, code blocks with copy/expand | Row `text` from `AssistantMessage.text` (`Timeline.swift:31-36`); unsupported → unsupported-block rendering |
| 59 | Sheet chrome (`SheetHeader`, `SheetRow`, `RowGroup`, `RowDivider`, `ClaudePlaceholderSheet`, `ThemeThumbnail`) — `ClaudeSheets.swift:4-79,315-368` | KEEP (chrome) / DELETE (placeholder) / ADAPT (thumbnail) | Used by every Paseo settings page; placeholder is demo-only; ThemeThumbnail feeds **Appearance → Theme** (#31) | Nothing |
| 60 | Sidebar icon `UnequalMenu` (`ClaudeSessionView.swift:775-784`) | KEEP | Generic drawer affordance | Paseo decides its own sidebar glyph; the shape can stay |
| 61 | Projects — list + create flow — `ClaudeProjectsView.swift:4-127`, `ClaudeProjectEditorView.swift:4-314`, `ProjectState.swift:3-150` | ADAPT (list/form) / DELETE (introduction, Drive) | **Projects** — "Projects list per host" (**Settings → host → Projects**); create → "**Add project**" (open-project flow). The introduction interstitial is Claude marketing — drop it. **Suggested repository** dashed row ≈ open-project suggestions | Projects store \* (host RPC `read_project_config_request` exists for config — 04 §12.4; list/create via host Projects UI flows \*); project icon via Project settings **Icon** |
| 62 | Project icon picker — `ClaudeProjectIconPicker.swift:4-102` | ADAPT | **Projects** — "**Edit project** (Name, **Icon**)" in project settings | Project edit RPC \*; the SF-Symbol lattice is directly reusable |
| 63 | Artifacts — `ClaudeArtifactsView.swift:4-234`, `ArtifactState.swift:3-116` | DELETE | No Paseo equivalent (Claude Artifacts). Rendering assistant Markdown (`ClaudeMarkdownView`) stays via #3 | — |
| 64 | Sizing/palette/typography tokens — `ClaudePalette` (`ClaudeSessionView.swift:9-27`), `ClaudeTypography` (`:5-8`), Newsreader assets | KEEP (palette/type as Paseo DesignSystem tokens; strip "Claude" names) | Paseo DesignSystem owns final tokens (ARCHITECTURE.md "DesignSystem") | — |

**Attachment field note (for #2, #6).** The Paseo wire protocol send path is `SendAgentMessageRequest(agentId:text:messageId:activeTurnBehavior:)` — no attachments yet (`Packages/PaseoCore/Sources/PaseoProtocol/Agents.swift:119-127`). The chat can send text today; attachment chips and image bubbles below the composer are build-on-protocol-change (04 §10 `file.upload.request` + inline image schema, plus `AgentAttachmentSchema`). ClaudeUI's tray/bubble rendering is still the right target UX once the wire lands.

**RowGroup/SheetRow are the house style.** KEEP/ADAPT rows assume new Paseo pages (Settings sections, schedule form, new-workspace form) are built from `SheetHeader` + `RowGroup` + `SheetRow` (`ClaudeSheets.swift:4-79`), not from stock `List`/`Form`, to match ClaudeUI's look — with Paseo tokens.

**"Build new in ClaudeUI style"** marks rows where Paseo has a feature but ClaudeUI has nothing (all gaps are consolidated in Section 6).

---

## 4. Deletion safety — what breaks, and in what order

`DELETE` rows from Section 3 map to a concrete set of files and in-place edits. Rules that keep this mechanical:

1. Delete the **view** before the **state** it binds; delete the **`SessionState`/`SettingsState` action case and arms** in the same step as the state file; delete the **demo/test/snapshot references** in the same change or the package won't build (ClaudeUI is Apple-only — nothing in it can compile on this Linux box; CI/Xcode is the only real check).
2. `Examples/ClaudeUIDemo` references nearly all of these (`Demo/DemoScreens.swift` 7 hits, `Demo/ClaudeDemoApp.swift` 6, `SnapshotTests/ScreenSnapshotTests.swift`, `UITests/DevicesDispatchUITests.swift`, `Demo/DemoFixtures.swift`, `Demo/DemoScreenPreviews.swift`, `Demo/WidgetPreview.swift`). The demo must drop the deleted screens in the same change (or be deleted from the app target). Out of scope here; flagged for the implementing ticket.
3. Package SwiftPM target for widgets disappears with `Package.swift` (`Packages/ClaudeUI/Package.swift:5-18`).
4. This section does not edit anything — it is the checklist for whoever executes.
5. **Renames happen over deletes.** The ADAPT surfaces that survive (`ClaudeCodeView`/`ClaudeCodeDraftView`/`ClaudeRoutinesView` → Paseo History/New workspace/Schedules screens) are adapted and renamed in-place; they are **not** deleted in this adoption, even though the dedicated "Code" surface as designed goes away — its pieces live on inside Paseo's screens. Whole-file deletion is listed per phase below, and only for Claude-only surfaces.

### 4.1 Whole-file deletions and their references

| Target (delete) | Referenced by (must be edited/deleted first or with it) | Notes |
|---|---|---|
| `ClaudeWorkAnnouncementView.swift` (whole) | *no references inside the package* (grep: self only); `Examples` demo `DemoScreens.swift` | Leaf; safe anywhere in Phase 1 |
| `Sources/ClaudeWidgets/` (`WidgetPresentation.swift`, `WidgetViews.swift`) | `Examples/ClaudeUIDemo/WidgetDemo/ClaudeDemoWidgets.swift`, `Demo/WidgetPreview.swift`, `Demo/ClaudeDemoApp.swift`, `Tests/WidgetPresentationTests.swift` | Also remove widget target + product from `Package.swift:6,12-18` and the widget extension in the demo project; `WidgetPresentationTests.swift` dies with it |
| `ClaudeCameraView.swift` + `CameraState.swift` | `ClaudeSheets.swift:138-142 (@State camera/pendingCapture), 271-289 (fullScreenCover)` | In-place edit inside `ClaudeAttachmentSheet` in the same change |
| `ClaudeDispatchView.swift` + `DispatchState.swift` | Code in `SessionState.swift:75,82,242,248,255,261` and the `.openDispatch`/`.dispatch` arms `:257-264`; `ClaudeSessionView.swift:75,79,82-85,100,108-113` (surfaceBackground, root switch, background); `SessionStateTests.swift` (DispatchState) | Phase 4 |
| `ClaudeCodeConfigurationSheets.swift` → split | `ClaudeCodeDraftView.swift:118-125` (environment/repository sheet bindings); uses `ClaudeCodeModelSheet` too. Keep `ClaudeCodeRepositorySheet` (ADAPT); delete `ClaudeCodeEnvironmentSheet` + `ClaudeCodeEnvironmentEditor` inside the file, or split the file first | Phase 5 |
| `CodeEnvironmentState.swift` | `CodeDraftState.swift:32,34,36,53` (`CodeEnvironmentAction` cases inside `CodeDraftAction`, `environmentForm`); `ClaudeCodeConfigurationSheets.swift` (edit arms) | Edit `CodeDraftState` in the same change; `CodeDraftAction.environment` case is removed (its `environmentForm` is the only state) |
| `ClaudeBillingSettingsView.swift` + `BillingState.swift` | `ClaudeSettingsView.swift:30-31` (destination case), `SettingsState.swift:26-33 (destination enum),67,130-132 (billing arms in `.open`/`.back,.close`),158-160 (default arm)`, `SettingsStateTests.swift` | Phase 3 |
| `ClaudePrivacySettingsView.swift` + `PrivacyState.swift` | `ClaudeSettingsView.swift:44-45`, `SettingsState.swift:74,158-160`, `SettingsStateTests.swift` | Phase 3 |
| `ClaudeTimeFocusView.swift` + `TimeFocusState.swift` | `ClaudeSettingsView.swift:46-48`, `SettingsState.swift:75,154-155`, `SettingsStateTests.swift` | Phase 3 |
| `ClaudeSharedLinksView.swift` + `SharedLinksState.swift` | `ClaudeSettingsView.swift:32-33,104`, `SettingsState.swift:68,87,97 (sharedLinks.reduce(.back) in `.open`/`.back,.close`)`, `SettingsStateTests.swift`; it renders `ChatMessage` rows (`SharedLinksState.swift:8`) and calls `ClaudeMarkdownView(…{ action(.markdown($0)) })` (`ClaudeSharedLinksView.swift:51`) | Phase 3 |
| `ClaudeMemoryFilesView.swift` + `ClaudeMemoryDraftEditor.swift` + `MemoryFilesState.swift` | `ClaudeSettingsView.swift:38-39,102-104 (header memory button),133-140` (destination case, back/delete header button), `SettingsState.swift:71,146-153 (`.memory(...)` routing, `.capability(.openMemoryFiles)` jump)`, `ClaudeCapabilitiesView.swift:26,137-141` (Memory files row — deleted with Capabilities, Phase 3 before memory) | Memory must go **after** Capabilities' row or at least in the same change |
| `ClaudeCapabilitiesView.swift` + `CapabilitiesState.swift` | `ClaudeSettingsView.swift:36-37`, `SettingsState.swift:70,144-145` (`.capability(...)` routing; the `.openMemoryFiles` jump), `SettingsStateTests.swift` | Phase 3 |
| `ClaudeArtifactsView.swift` + `ArtifactState.swift` | `SessionState.swift:77-78,237-243` (artifacts arms), `ClaudeSessionView.swift:73,86-89,100`, `SessionStateTests.swift` (`ArtifactStateTests`), demo | Phase 4 |
| `ClaudeDevicesView.swift` (whole, incl. `ClaudeManageDevicesView`) + `DeviceState.swift` | Header rows in `ClaudeSessionView.swift:120 (.sheet .devices)`, `:225-229 (header laptop button, ADAPT → hosts)`; `SessionState.swift:74 (property),207-229 (`.newSession` copies `devices`)`; `ClaudeSheets.swift:169-179,249-252` (attachment "Devices" page — that page rebinds to hosts, not deleted); `SessionStateTests.swift` (DeviceState) | Phase 6 |
| `Sources/ClaudeUI/Resources/Assets.xcassets/ClaudeLogo.imageset/` + `GitHubLogo.imageset/` (Resources) | `ClaudeSessionView.swift:177,367` (logo), `ClaudeCodeDraftView.swift:58,63-64` (GitHubLogo) | Swap for the Paseo mark in Phase 7 |

### 4.2 In-place edits inside kept files (not whole-file deletions)

| File (kept) | Edit | Driven by |
|---|---|---|
| `SessionState.swift` | Remove now: properties `dispatch`/`artifacts`/`devices`/`showingArtifacts`/`showingDispatch`/`temporary`; actions `.share`, `.readAloud`, `.retry`, `.feedback`, `.voiceFeedback`, `.toggleTemporary`, `.beginEditing`, `.cancelEditing`, `.openDispatch`, `.dispatch`, `.openArtifacts`, `.artifacts`, `.devices`, `.beginEditing`/`visibleMessages` editing truncation (`:108-113`); `.newSession` arms copying deleted states (`artifacts`/`dispatch`/`devices`) at `:207-229` — keep the `model`/`effort`/`voiceLanguage`/`settings` copy. Keep initially (retire as Paseo screens land, do **not** delete prematurely): `code`/`showingCode`/`.openCode`/`.code` (ADAPT #21-22), `projects`/`showingProjects`/`.openProjects`/`.projects` (ADAPT #61), `media`/`attachments` (ADAPT #6, #52), all voice cases (ADAPT #9, #41), dictation (ADAPT #8), `settings` | `.newSession` arm copies deleted states; `SettingsState` pruned separately (row below) |
| `ClaudeSessionView.swift` | Remove: `.showingDispatch` branches and `ClaudeDispatchBackground` (`:75,79,82-85,108-113`), `showingArtifacts` branch (`:86-89`), "Temporary session" button (`:213-223`), editing banner (`:382-396`) and its state (`.beginEditing` call sites `:297`, the "Editing this message…" note `:302-307`, "Edit" in the bubble context menu `:296-300`), feedback thumbs (`:342-351`), share/readAloud (`:331-341`), retry arrow (`:352-356`), voice-rating buttons (`:635-647`), `sessionRow` demo fixture injection (`:751-764` — replace with real agent list), `state.messages =` write at `:754` (illegal — view mutates state through actions only) | ADAPT rows #1-17, #45-50; #10 |
| `ClaudeSettingsView.swift` | Remove destination cases and root rows: profile/gift/account/add account/billing/shared links/capabilities/memory/time & focus/privacy/permissions log-out/delete-account (keep structure); `.about` menu retained for About page (ADAPT) | Section 3 #19, #29, #31-39, #43, #44 |
| `SettingsState.swift` | Same pruning: `ClaudeSettingsDestination` cases (`:26-33`), `ClaudeSettingsAction` cases (`:46-62`), `ClaudeSettingsState` properties + reducer arms (`:64-175`); `ClaudeSettingsInfoLink` keep (About menu) | Sections 3-4 |
| `ClaudeSheets.swift` | Delete `SyntheticPhoto` (`:292-314`), `ClaudePlaceholderSheet` (`:315-341`), `ClaudeFeedbackSheet` (`:369-411`), camera branch of `ClaudeAttachmentSheet` (`:138-142,271-289`), attachment-sheet "Add to project"/"Devices"/"Select mode" pages rebind to Paseo's agent controls + hosts; keep `SheetHeader`/`SheetRow`/`RowGroup`/`RowDivider`/`ClaudeModelSheet` (ADAPT)/`ThemeThumbnail` (ADAPT) | Section 3 #51-53, #59 |
| `CodeDraftState.swift` | Remove now (pairs with Phase 5): `environmentForm` (`:53`), `CodeEnvironment` fields `environments`/`selectedEnvironmentID` (`:51-53`), `CodeDraftAction.environment` (`:36`), plus its `CodeEnvironmentAction`/`CodeEnvironmentFormState` references | Phase 5 will break these lines anyway; removing early avoids a compile-broken intermediate state |
| `ClaudeProjectEditorView.swift` | Remove (pairs with #61): the `ProjectIntroductionIllustration` introduction page (`:277-313` + `state.editor == .introduction` branch `:25`), the Google Drive `drivePicker` (`:232-266`) and its `validFolderLink` (`:267-273`); keep the form (adapts to project settings), icon picker, icon color grid | ADAPT #61 with DELETE sub-parts; `.continueIntroduction` and the `hasSeenIntroduction` state in `ProjectState.swift:46,70-73` go with it |
| `RoutineState.swift` | Keep — ADAPT to Schedules; delete nothing yet (rename to `ScheduleDraft` later, optional) | — |
| `MarkdownTableMetrics`/`ClaudeCodeHighlighter` | Keep | — |
| `Package.swift` | Drop `ClaudeWidgets` target/product + `Examples` widget extension reference | Phase 1 |
| `Tests/` | Delete `SessionStateTests.swift` (Dispatch/Device/CodeEnvironment coverage), `SettingsStateTests.swift` (deleted states), `ArtifactStateTests.swift`, `WidgetPresentationTests.swift`. Keep `MediaTests`, `ProjectStateTests`, `MarkdownTests`, `MarkdownTableTests`, `CodeHighlighterTests` | same change |
| `Examples/ClaudeUIDemo/` | Delete demo screens for all deleted surfaces (`Demo/DemoScreens.swift` announcement/dispatch/artifacts entries — connectors stay, ADAPT), UI tests `UITests/DevicesDispatchUITests.swift`, widget preview, snapshots | same change |

### 4.3 Suggested deletion order

For each phase: remove screens/views first, then rewire call sites in kept files, then remove the state files, then tests/demo/assets. After each phase, `rg` for the deleted type names across `Packages/ClaudeUI` must return zero hits (except intended renames), and CI/macOS must show a clean build — SwiftUI cannot compile on this Linux worktree.

1. **Phase 1 — leaves:** `ClaudeWorkAnnouncementView.swift` (F1); `Sources/ClaudeWidgets/` + `Package.swift` (F13); `CameraState.swift` + `ClaudeCameraView.swift` + attachment-sheet camera page (F5). *Verify:* no references to `ClaudeWorkAnnouncementView|ClaudeCameraView|CameraState|ClaudeWidgetPresentation`.
2. **Phase 2 — chat-adjacent no-ops:** action cases `.share`,`.readAloud`,`.retry`,`.feedback`,`.voiceFeedback`,`.toggleTemporary` (+`GhostShape`),`.beginEditing`,`.cancelEditing` in `SessionState` + their buttons/state in `ClaudeSessionView.swift`/`ClaudeSheets.swift`. *Verify:* `rg '\.retry|\.share\(|\.readAloud\(|\.copy\(' SessionState` — copy must remain (`#46`).
3. **Phase 3 — settings pages (child → parent):** 3a Capabilities (`ClaudeCapabilitiesView` → `CapabilitiesState` → `ClaudeSettingsView` cases/rows → `SettingsState.swift` `:70,144-145`); 3b Memory files (`ClaudeMemoryFilesView` → `ClaudeMemoryDraftEditor` → `MemoryFilesState` → `ClaudeSettingsView` (`:38-39,102-104,133-140`) → `SettingsState.swift` `:71,146-153`); 3c Shared links (view → state → `ClaudeSettingsView`/`SettingsState`); 3d Privacy; 3e Time & focus; 3f Billing. *Verify per sub-phase:* `rg 'Capabilit|MemoryFiles|SharedLinks|Privacy|TimeFocus|Billing' Packages/ClaudeUI` → zero hits.
4. **Phase 4 — top-level surfaces:** Artifacts (`ClaudeArtifactsView` → `ArtifactState` → `SessionState` arms `:237-243` → root case `ClaudeSessionView.swift:86-89` → sidebar row `:703`); Dispatch (`ClaudeDispatchView`+`ClaudeDispatchBackground` → `DispatchState` → `ClaudeSessionView.swift` branches/background/sidebar row → `SessionState` arms `:257-264` + `SessionStateTests.swift`). *Verify:* same for `Dispatch|Artifact`.
5. **Phase 5 — environments:** `ClaudeCodeEnvironmentSheet`/`ClaudeCodeEnvironmentEditor` (extract from `ClaudeCodeConfigurationSheets.swift`) → `CodeEnvironmentState.swift` → `CodeDraftState.swift` in-place fields/cases. *Verify:* `rg 'CodeEnvironment|environmentForm|CodeNetworkAccess'` → zero.
6. **Phase 6 — devices account:** `ClaudeDevicesView.swift` → `DeviceState.swift` → `SessionState.swift` (`:74`, `.newSession` copy arms `:207-229` — remove the `devices` copy) → header button repoint to host picker (ADAPT, not delete) → attachment-sheet "Devices" page rebinds to adapter over host list (ADAPT). *Verify:* `rg 'DeviceState|DeviceAction|ClaudeDevicesView|ManageDevices'` → zero.
7. **Phase 7 — placeholders & assets:** `ClaudePlaceholderSheet` + `NamedDestination` call-sites rewired to real flows or deleted; `SyntheticPhoto`; `ClaudeLogo`/`GitHubLogo` assets replaced with the Paseo mark; `ClaudeFontResources` kept (font stays).
8. **Phase 8 — settings pruning sweep:** `ClaudeSettingsDestination` case removal (`SettingsState.swift:26-33`), `ClaudeSettingsView` root + header references, `.about` retained; `ClaudeSettingsInfoLink`/About path checked; full `rg` pass for every deleted type; then demo + tests + `Package.swift` consistency pass on a mac (UIKit code can't be checked on Linux).

### 4.4 Reference graph summary (who points at the `ClaudePalette`/sheet chrome — i.e. why kept files stay compiling)

`RowGroup`/`SheetRow`/`RowDivider`/`SheetHeader` are referenced by ~20 files (`ClaudeBillingSettingsView`, `ClaudeCapabilitiesView`, `ClaudeCodeConfigurationSheets`, `ClaudeCodeConnectorsView`, `ClaudeCodeContextSheet`, `ClaudeCodeDraftView`, `ClaudeCodeSettingsView`, `ClaudeDevicesView`, `ClaudeRoutinesView`, `ClaudeSettingsView`, `ClaudeSettingsConnectorsView`, `ClaudeMemoryFilesView`, `ClaudeNotificationSettingsView`, `ClaudeUsageSettingsView`, `ClaudeVoiceSettingsSheet`, `ClaudeSheets.swift`). Deleting any sheet file above does not orphan these primitives — they are used by survivors (Usage/Notifications/Connectors/Code). Do not delete the primitives in this adoption.

---

## 5. The chat seam — exactly where ClaudeUI renders messages, and how to swap in Paseo `Turn`s

`ClaudeSessionView` (`Packages/ClaudeUI/Sources/ClaudeUI/ClaudeSessionView.swift`) is a single 805-line file; the chat seam is its `transcript` computed property and `ChatMessage`. Nothing about the seam is hidden — the work is removing `SessionState.messages` and routing renders to `ConversationStore.turns` while keeping composer/sheets/motion.

### 5.1 Where messages render today

| What | path:line | Notes |
|---|---|---|
| Message list | `ClaudeSessionView.swift:253` — `ForEach(state.visibleMessages)` | `visibleMessages` is the editing-truncated view (`SessionState.swift:108-113`) — it hides future messages while editing an earlier one; for Paseo this whole concept goes (Section 3 #10) |
| List container / scroll | `ClaudeSessionView.swift:249-372` (`ScrollViewReader` + `ScrollView` + `VStack(spacing: 27)`) | auto-scroll on `state.messages.last?.text` change: `:373-377` with `reduceMotion` guard |
| Bottom anchor | `ClaudeSessionView.swift:370` — `Color.clear.frame(height: 1).id("bottom")` | must become "scroll to last turn" |
| User bubble | `ClaudeSessionView.swift:254-308` — `if message.role == .user` branch; bubble text `:277-284` (18pt, adaptive background, 28pt radius); media row above text `:255-276`; context menu (Copy/Send to/Select text/Edit) `:285-301`; editing note `:302-307` | bubble background via `ClaudePalette.adaptive(...)` |
| Assistant branch | `ClaudeSessionView.swift:309-365` — `VStack(alignment: .leading, spacing: 18)` | no bubble background, plain markdown |
| Assistant markdown | `ClaudeSessionView.swift:311-313` — `ClaudeMarkdownView(message.text, theme: .init(serifName: typography.serifName)) { onAction(.markdown(message.id, $0)) }` | the only place ClaudeMarkdownView is fed chat text |
| Response footer | `ClaudeSessionView.swift:314-361` — `if state.phase != .streaming`: copy/share/readAloud thumbs/retry; Claude disclaimer line `:358-361` | footer belongs to a completed turn; in Paseo it keys off `turn.phase == .completed/.failed` |
| Streaming indicator | `ClaudeSessionView.swift:366-369` — `if state.phase == .streaming` pulse logo; streaming text itself is *appended to the in-memory assistant message* by `appendResponse` | no separate "turn row" concept; the assistant message grows in place |
| Message identity | `ChatMessage.id: UUID` (`SessionState.swift:5,9`) | `ForEach` identity = message id |

### 5.2 Composer & streaming state today

| What | path:line |
|---|---|
| Composer container | `ClaudeSessionView.swift:380-503` — bg/radius/stroke `:497-502` |
| Editing banner | `ClaudeSessionView.swift:382-396` (remove with #10) |
| Media draft tray | `ClaudeSessionView.swift:397-424` (adapt with #6) |
| Attachment pill row | `ClaudeSessionView.swift:425-441` (adapt with #6) |
| Text field | `ClaudeSessionView.swift:442-453` — `$state.draft`, `.disabled(recording)`; placeholder switches on `state.messages.isEmpty` |
| Dictation phase swap | `ClaudeSessionView.swift:454-456` — `recording/recordingPaused` → `dictationControls` else controls row |
| Controls row | `ClaudeSessionView.swift:457-495` — attach (`:458-461`), model chip (`:462-471`), dictate (`:473-476`), stop (`:477-479`) / send (`:480-484`) / voice waveform (`:485-494`) |
| Dictation controls | `ClaudeSessionView.swift:552-579` |
| Voice overlay | `ClaudeSessionView.swift:504-551` (replaces composer when `state.voiceActive`) |
| Send reducer | `SessionState.swift:122-147` — sets `.streaming`, mints `responseID` (`:146-147`) |
| Streaming append | `SessionState.swift:291-298` — `appendResponse` appends to last assistant message or creates one (`:293-297`); drops late chunks after Stop via `responseID` guard (`:292`) |
| Finish | `SessionState.swift:299-304` — `finishResponse` → `.idle`, clears `responseID` |
| Cancel/stop | `SessionState.swift:172-176` |
| Retry | `SessionState.swift:272-277` |
| Phase consumers (grep) | `.streaming` at `:146,293,300,366,476,477`; `.idle` at `:103-105,122,148,173,272-277`; `.recording`/`.recordingPaused` at `:166-170,182,192,199-205,454,571-574` |
| Sidebar session write | `ClaudeSessionView.swift:754-757` — demo writes `state.messages =` directly (the bug to remove) |

### 5.3 The Paseo data shapes on the other side of the seam

| Type | path:line | Key facts for the swap |
|---|---|---|
| `ConversationStore` | `Packages/PaseoCore/Sources/PaseoStore/HostSession.swift:209-424` | `@Observable`; `turns` on `:223`; `activeTurnId` `:226`; `phase: LoadPhase` `:219`; `isRunning` `:237`; `agent: AgentSnapshot?` `:220`; `draft` `:231`; `send` `:287-313` (steers when running — `:299-304`); `cancel` `:316-328`; `loadOlder` `:269-282` (`isLoadingOlder` `:227`); `actionError` `:229` |
| `Turn` | `Packages/PaseoCore/Sources/PaseoStore/Turn.swift:6-64` | `id` = first row's id (`:9`, stable across pending→confirmed); `turnId` `:12`; `userMessage: TimelineRow?` `:14`; `segments: [Segment]` `:16`; `phase` `:17` — `.running/.completed/.failed(String)` (`:23-28`) |
| `Turn.Segment` | `Turn.swift:30-46` | `.work(WorkGroup)` `:33`, `.prose(TimelineRow)` `:35`, `.todo(TimelineRow)` `:36`, `.notice(TimelineRow)` `:38`; `Segment.id` `:40-45` |
| `Turn.WorkGroup` | `Turn.swift:48-57` | `rows` reasoning+tool calls only (`:50`), `thoughtCount`/`toolCallCount` `:51-52`, `isActive` (any running tool call) `:54-56` |
| WorkGroup summary | `Packages/PaseoCore/Sources/PaseoStore/Presentation.swift:69-76` | `"2 thoughts, 1 tool call"` (`Extension Turn.WorkGroup.summary`) — exact string for the collapsible header |
| Tool-call presentation | `Presentation.swift:6-67` | `ToolCallPresentation` (`status`, `title`, `subtitle`, `symbol`) — `Bash · ls -la`, `Edit · foo.swift`, etc. — builds the "ran N commands / edited N files" rows and detail expansion (doc 01 **Tool calls**) |
| `TimelineRow` | `Packages/PaseoCore/Sources/PaseoStore/TimelineState.swift:6-21` | `id` stable (`tool:<callId>` / `local:<clientMessageId>` / `seq:<start>`), `turnId` (`:11`), `item` (`:12`), `timestamp` (`:14`), `isPending` (`:18` — pending user echo) |
| `TimelineItem` | `Packages/PaseoCore/Sources/PaseoProtocol/Timeline.swift:10-20` | `.userMessage` / `.assistantMessage` / `.reasoning` / `.toolCall` / `.todo` / `.error` / `.notification` / `.compaction` / `.unknown` (forward-compat `.unknown` — ARCHITECTURE.md:46-48); payload structs `:22-29` (UserMessage), `:31-36` (AssistantMessage), `:37-41` (Reasoning), `:42-55` (TodoList), `:77-101` (ToolCall/Status), `:103-173` (ToolCallDetail: shell/read/edit/write/search/fetch/subAgent/plainText/plan/worktreeSetup/unknown) |
| `AgentSnapshot` | `Packages/PaseoCore/Sources/PaseoProtocol/Agents.swift:28-54` | `title`, `cwd`, `model`, `status` (`.initializing/.idle/.running/.error/.closed`), `activeTurn`, `availableModes`/`currentModeId` (mode chips), `requiresAttention`/`attentionReason`, `labels` |
| Pending user message | `TimelineState.swift:131-139` (`addPendingUserMessage`); confirmed echo reuse — `:59-72` (`applyPage` swaps in the page row id) | Bubble identity across pending→confirmed — same invariant ClaudeUI relies on at `ChatMessage.id` |

### 5.4 The concrete replacement — message loop

**Render loop** (`ClaudeSessionView.swift:253`): replace `state.visibleMessages` with a `ForEach(store.turns)`. Per turn:

1. **User bubble** — if `turn.userMessage != nil`, render today's bubble branch (`ClaudeSessionView.swift:254-308`) keyed off `row.id` (stable; `TimelineState.swift:8-21`) and the text at `row.item .userMessage(let m) → m.text` (`Timeline.swift:22-29`). Delete the `.userMessage` row from `segments` (it is not in `segments` by construction — `TurnDraft.add` returns early, `Turn.swift:129-132`). Delete the editing context menu entirely (Section 3 #10); media tray/bubbles stay as the attachment UI once the wire lands (Section 3 note). `isPending` (`TimelineRow.isPending`, `TimelineState.swift:18`) renders the queued/pending affordance (doc 01: queued rows, "**Edit queued message**", "**Send queued message now**") — new buttons here.
2. **Segments** — `ForEach(turn.segments)`:
   - `.work(let group)` → **new** `WorkGroupView` in ClaudeUI style (collapsible `RowGroup`-like cell): header `group.summary` (`Presentation.swift:69-76`) when collapsed; detail = ForEach `group.rows` → each row is `.reasoning` ("Thought" — doc 01 "**Thought**") or `.toolCall` → a tool-call row built from `ToolCallPresentation(call)` (`Presentation.swift:6-67`) with status tint; expansion = **Input**/**Output** detail block (Input/Output labels — doc 01 "Input/Output detail expansion"); error state for `call.status == .failed` / `.error(message:)`. Auto behavior: while `group.isActive` (`Turn.swift:54-56`) show it expanded with a progress line (doc 01: in-flight turn shows elapsed timer + loader — **"Worked for {{duration}}"** completed footer is `Turn.duration` — `Turn.swift:59-63`).
   - `.prose(let row)` → `ClaudeMarkdownView(row text)` — same call as `ClaudeSessionView.swift:311-313` but text from `(row.item .assistantMessage(let m)) → m.text` (`Timeline.swift:31-36`); `message.id` in the `MarkdownAction` callback becomes `row.id` (`.markdown(row.id, $0)`).
   - `.todo(let row)` → **new** Tasks track row (doc 01 **Tasks track**: "Created/Added/Started/Completed", "{{completed}}/{{total}} tasks") — pinned above the composer or inline; ClaudeUI has nothing — see Section 6.
   - `.notice(let row)` → render as lightweight chips: `.error(message:)` (doc 01 "**Error**" state), `.notification(level:message:)`, `.compaction(status:)` (a divider line, "Context compacted"), `.unknown` (render nothing or the raw type name).
3. **Turn footer** — when `turn.phase` is `.completed`/`.failed`, render today's footer button row (`ClaudeSessionView.swift:314-361`) minus Share/ReadAloud/Retry (deleted), keyed by `turn.id` instead of `message.id`; "**Worked for {{duration}}**" line uses `turn.duration` (`Turn.swift:59-63`, seconds → "Completed in 4s" per ARCHITECTURE.md:66). `.failed` shows the error and no copy check? — doc 01: failed turns show error text; keep Copy. Feedback thumbs are deleted (Section 3 #45).
4. **Running indicator** — replace `state.phase == .streaming` pulse (`ClaudeSessionView.swift:366-369`) with `turn.phase == .running` per-turn; the global composer Stop stays for the active turn (`turn.turnId == store.activeTurnId`, `Turn.swift:156`). Auto-scroll key becomes `store.turns.last?.segments` (hash of last row's content) instead of `state.messages.last?.text`.
5. **Empty state** — `state.messages.isEmpty` (`ClaudeSessionView.swift:174-184`, placeholder "Evening, how are things?") becomes `store.turns.isEmpty` with the Paseo empty-state copy (doc 01: "Start chatting with this agent…"). Keep the Claude-free layout (centered logo → Paseo mark).
6. **Scroll anchor** — `Color.clear...id("bottom")` + `.onChange(of: ...)` (`:370-377`) keys off the last turn's prose text length; keep `ScrollViewReader`.

### 5.5 Keeping composer, sheets, and motion

- **Composer shell** (`ClaudeSessionView.swift:380-503`) is untouched structurally. Only swaps: `state.draft` → `$store.draft`; `state.phase == .streaming` → `store.isRunning` (`HostSession.swift:237`); `state.canSend` → `!store.draft.trimmed.isEmpty && !store.isRunning` (and drop the attachments precondition or keep `!tray.isEmpty` once attachments land); `onAction(.send(store.draft))` → `Task { await store.send(text) }`; `onAction(.stop)` → `Task { await store.cancel() }` — the existing `ClaudeAction` enum disappears; the host wires ConversationStore calls directly through an adapter the way the README example wires `--screen` handlers (README:68-102).
- **Steer vs queue** — `store.send` already sends with `activeTurnBehavior: "steer"` when running (`HostSession.swift:294,299-304`); Stop maps to `.cancel()`; the queue lane (doc 01 **Queue track**, "**Edit queued message** / **Send queued message now**") is a new component fed by the pending-message concept (`TimelineRow.isPending`, `TimelineState.swift:18`) — not in ClaudeUI today.
- **Sheets** — `ClaudeModelSheet` (model + effort pages) stays but is fed `AgentSnapshot.availableModes`-style provider data instead of `ClaudeModel.allCases` (Section 3 #12-14); the attachment sheet stays with host-driven photo recents (#52) minus camera page (#51) and minus "Add to project" (#56-delete); `ClaudePlaceholderSheet` dies (#59).
- **Editing** — the editing banner, `.beginEditing` flow, and `visibleMessages` truncation are removed wholesale (#10); the Composer becomes simpler by ~60 lines.
- **Motion** — `.spring` on sidebar toggle (`:604-607`), `.pulse` symbol effect (`:368`), `reduceMotion` guards on auto-scroll (`:373-377`), dictation interpolation animation (`:567`), `toggleSidebar` offset/shadow (`:100-105`), sheet drag indicator/detents/corner radius (e.g. `ClaudeSheets.swift:130-131`) — all unchanged. `withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.88))` is preserved.
- **Haptics** — doc 01 has none in-app; Paseo DesignSystem owns haptics (ARCHITECTURE.md:81-83); ClaudeUI emits no haptics today either, so nothing to port.
- **Deletion within file** — the `sessionRow` fixture (`:751-764`) with its hardcoded `state.messages = ...` is removed; the sidebar becomes a real list bound to `HostSession.agents` (#15-16) with `AgentSnapshot.title/cwd/status` and `projects` placements.
- **Session/agent plumbing** — the Paseo conversation view is created per agent id: `HostSession.conversation(for:)` (`HostSession.swift:62-74`) returns a stable `ConversationStore`; `closeConversation` (`:77-80`) drops it — call both from the same place ClaudeSessionView's sidebar handles new/switch. `conversations` keyed by id (`:24`). Subscribe before presenting; the first `.load()` is fired in `conversation(for:)` (`:72`).
- **Reload-after-reconnect** — `HostSession.resync()` calls `catchUp()` on open conversations (`:123-130`); the renderer handles `turns` changing wholesale; no special "refreshing" UI is wired in ClaudeUI — add a subtle "Reconnecting to host" line bound to `HostSession.connection` (`:14,106-120`) (doc 01: "**Reconnecting to host**", "**Updating messages**", "**Scroll to bottom**", "Couldn't load agent history" — `i18n/resources/en.ts:234-281` conceptually; exact Apple labels to come from Paseo strings).
- **Older history** — pull-to-load at the top uses `loadOlder()`/`timeline.hasOlder`/`isLoadingOlder` (`HostSession.swift:227,269-282`, `TimelineState.swift:37-38`). In ClaudeUI the transcript simply ends at the top today; a "Load earlier" row or pull gesture is new.

### 5.6 What about `ChatMessage`/`appendResponse`?

- `ChatMessage` (`SessionState.swift:3-15`) disappears with the swap; `SharedLinksState`-style read-only snapshots are gone too (#37).
- `appendResponse`/`finishResponse` (`SessionState.swift:291-304`) disappear; consumers in doc/README examples move to "feed `TimelineState` via the daemon events" — already implemented in `ConversationStore.handleStream` (`HostSession.swift:339-363`) and `TimelineState.applyStream` (`TimelineState.swift:103-129`).
- `ComposerPhase`/`ResponseID` bookkeeping (`SessionState.swift:19,69`) disappears; the daemon's seq machinery (`TimelineState.nextSeq`, `:32`, `seq` gaps → fetch `.after`) replaces the UUID-token method.
- **Untested platform branches**: `MarkdownTableMetrics.swift:20-64` (`#if canImport(UIKit)` Layout) and everything under `#if canImport(UIKit)` in views are never built on Linux; CI builds them on macOS. Any edit there needs the mac check — same for `ClaudeSelectableInlineCode`'s TextKit layout manager.

---

## 6. Gaps — Paseo features from doc 01 with no ClaudeUI counterpart

ClaudeUI recreates one app's UI, not Paseo's. Anything below must be **built new in ClaudeUI's style** (`SheetHeader`/`RowGroup`/`SheetRow`, `ClaudePalette` tokens, `ClaudeMarkdownView`, `.glassEffect` chrome, `reduceMotion` guards) — there is nothing to adapt, or what exists is a different feature wearing the same clothes.

### 6.1 Chat surface gaps (build to render Paseo `Turn`s)

| Gap | Paseo UI labels (doc 01) | Notes / starting point |
|---|---|---|
| **Work group cell** (collapsible reasoning + tool calls) | **Tool calls** — "edited N files / ran N commands / read N files / Thought", **Input**/**Output** detail expansion, **Error** state; **Turn collapse** — "**Show more**/**Show less**", "**View turn details** (**Sent by {{name}}**)"; **Chat display** setting (Full / Collapse tool calls / Collapse turns) | Data: `Turn.WorkGroup` + `Presentation.swift:69-76` (summary string) and `ToolCallPresentation` (`Presentation.swift:6-67`) — the presentation layer exists; the cell does not |
| **Permission request card** | **Permission requests in chat** — "**Plan** / **Permission Required**" title, **Deny** / **Accept** (or **Implement**), **Input**/**Output** block, "**Approved plan** / **Rejected plan** / **Canceled plan**" | Protocol research: `agent_permission_request` event + `agent_permission_response` RPC, snapshots carry `pendingPermissions` (04 §6.1-6.4); `AgentSnapshot.pendingPermissions` (`Agents.swift:44`, kept raw — type it when building the card) |
| **Question form card** | Question-kind requests render an inline form ("**How would you like to proceed?**"), per-question options + free-text "other" | Same permission plumbing (04 §6.1); ClaudeUI has zero form-card machinery |
| **Plan card (proposed plans)** | **Plan card** — "**Proposed plan**" with approve/reject; tool detail `.plan(text:)` exists (`Timeline.swift:112`) | Build from `ToolCallPresentation`'s `plan` arm (`Presentation.swift:41-42`) |
| **Subagents track** | **Subagents track** — pill above composer ("**1 subagent**", "**{{count}} working**", "**{{count}} needs input**"), panel, rows **Detach …**/**Archive …**, "**Archive finished subagents**", "**Back to parent** / **Open parent**" | `.subAgent(childSessionId:)` tool calls (`Timeline.swift:110`) + `agent.provider_subagents.list/timeline.get/update` RPCs (04 §11.2); store work pending |
| **Tasks track** | **Tasks track** — "**Tasks**" panel, "**{{completed}}/{{total}} tasks**", "Created/Added/Started/Completed {{count}}" | `.todo(TodoList)` rows exist in protocol (`Timeline.swift:15,42-55`); no UI |
| **Queue track** | **Queue message** — "**Edit queued message**" / "**Send queued message now**" | Pending rows (`TimelineRow.isPending`) — UI only; agent is running → Send becomes Queue (§5.5) |
| **Context window meter** | **Context window meter** — ring in composer/panel; **Context window** details: "**{{percentage}}% used**", "**{{used}} / {{max}} tokens**", "**Session cost**"; agent Usage report card | No token-count fields in `AgentSnapshot` yet; daemon supplies via agent update/config \*; ClaudeUI effort badge is the right anchor position |
| **Fork from here** | **Fork chat from here** — "**Fork in a new tab** / **Fork in a new workspace**" (assistant-turn footer, hidden for read-only panes) | Hook exists (04 §4.7 detach / §11.5 fork context); protocol `agent.rewind/fork` research in 04 §4.8-11.5; no Paseo fork UI |
| **Rewind menu** | **Rewind** — "**Rewind conversation** / **Rewind files** / **Rewind conversation and files**" + can't-undo warning | Protocol 04 §4.8 (`agent.rewind.request`) |
| **Slash commands & @-mentions** | **Slash commands** — provider commands + "**/exit**", "**/clear**"; **Skills**; **@-files and /commands autocomplete** (popovers), "`Skill`" tag | `list_commands_request` / `agent-commands/use-query` (04 §9.1); keyboard-scope popover infrastructure absent |
| **Find in pane** | **Find in pane** — "**Find**" box ("Find in pane", **Previous/Next match**, "**{{n}} of {{N}}**", **Replace all** in editors) | Editor surface doesn't exist yet; build with `UITextField`/TextKit or `UIViewRepresentable` |
| **Chat outline rail** | **Chat outline** — prompt rail (web/desktop wide screens only) | Desktop-only; defer |
| **Archived callout** | **Archived agents** — "**Archived**" badge + **Unarchive** callout | `archived_agent_request` (04 §4.3); `list` filter exists for non-archived (`HostSession.swift:88-90`) — archived listing is a fetch-with-filter \* |
| **Agent stream errors** | "**Couldn't load agent history**", "**This message was capped**", "**Scroll to bottom**", "**Reconnecting to host**", "**Updating messages**" | `LoadPhase.failed`, `actionError` (`HostSession.swift:219,229`) — surface copy needed; nothing in ClaudeUI |
| **Notification tap → route** | **Notifications** — tap routes to the agent (pinned) or workspace; attention-tagged dock badge | Push/attention RPCs (04 §7.4, §7.5); host-side wiring \* |
| **Background work UI** | **Background work** — background shells/monitors surface here (`background-work/`) | `agent.background_work.list/stop/update` (04 §11.3) |

### 6.2 Workspace surface (nothing close to this in ClaudeUI)

| Gap | Paseo UI labels (doc 01) | Notes |
|---|---|---|
| **Workspace screen** (tabs/panes deck) | **Tabs** — agents/terminals/files/diffs/PR/setup/browser; rename/close/**Close to the left|right**/**Move to main panel**; **Tab switcher** ("**Switch tabs ({{count}} open)**"); **New tab menu** (**New agent**, **New terminal**, **Files**, **Changes**, **Pull request**); **Workspace header menu** ("**Workspace actions**": **Import session**, **Copy workspace path**…); **Splits** (**Split pane right/down**, drag tabs) | ClaudeUI's "sidebar + one surface" is far below this; this is the biggest build in PaseoUI (`Packages/PaseoUI/Sources/` already stubs `Workspace*Feature`) |
| **Sidebar with workspaces** (pinned, status buckets, display preferences) | **Sidebar nav rows**, **Pinned**, "Status", "Project", "Labels" grouping, **Display preferences** popover (**Sort**/**Grouping**/**Title**/**Show**/**Host**/**Project** filters, **Background** agents toggle), **Workspace actions** menu (rename/pin/archive/hide), **Status buckets** (**Needs input**/**Failed**/**Ready to review**/**Working**/**Done**) | ClaudeUI sidebar is static with fake session names — see Section 4 Phase 8 |
| **Explorer sidebar (Files + Changes trees)** | **Explorer sidebar** — "**Files**" and "**Changes**" trees, "**Open/Close/Toggle Explorer sidebar**", sheet on compact | Protocol 02 (files: `list_directory`-style RPCs; git: status/diff) — build after stores |
| **File browser & viewer/editor** | **Files** — Browse/Sort (Name/Modified/Size), hidden-files toggle, New file/folder, context menu ("**Open to the side**", "**Copy relative path**", "**Download**", "**Add to chat**", "**Rename**", "**Delete**"), "Loading files…"/"No files"/"Failed to list directory" states; Built-in viewers (Markdown/HTML/Image/Source editor + vim + autosave + conflict handling) | Also gap for `.worktreeSetup` log rendering (setup tab **Running/Completed/Failed/Blocked**) |
| **Changes/diff viewer** | **Changes** — changed-files tree, **All changes**/**Uncommitted**/**Committed**, unified vs side-by-side toggles, **Inline diff**, **Hide whitespace**, **Scroll/Wrap long lines**, **Collapse/Expand all files**, **Commits** list, "**Working tree diff** / **Commit diff**" tooltips, "Jump to file", "Change base", forge setup callout ("**Install the {{cli}} CLI**"), "**Discard changes**" | Largest single surface; the tool-call `.edit(unifiedDiff:)` rendering inside chat is related but separate |
| **Git actions** | **Git actions** split button — **Commit**, **Pull/Push**, **Create PR/MR**, **View PR/MR**, **Merge locally**, **Update from {{baseRef}}**, **Merge PR (squash\|merge\|rebase)**, **Auto merge…**, **Archive workspace** | Direct daemon RPCs (02); precision/disabled states per doc 01 |
| **PR/MR pane** | **PR/MR pane** — "**Activity**" timeline: approvals ("**{{given}} of {{required}} approvals**"), review threads ("**Discussion thread**"/"**Resolved**"/"**Outdated**"), **Add to chat**, "**Open on {{brand}}**", checks list ("**Checks passed/running/failed**"), "**Add to chat** / **Add all to chat**" | Forge integration host-side; UI is a full panel |
| **Review comments** | **Review** — gutter "+" → "**Leave a comment**" inline in diff, drafts persist, **Send feedback ({{count}})** sends accumulated comments to a chosen agent | New |
| **Branch switcher** | **Branch switcher** — "**Switch branch…**" combobox, "**Stash & Switch**", "**Restore**/**Later**" | Also needed by **New workspace** branch field |
| **Terminal** | **Terminals** — New terminal, tab chips (title/status/rename/**Copy terminal id**/close confirm), **Find in terminal**, paste/drop files ("**Uploading file…**", 50 MB cap), local links→main pane, **Virtual keys** bar, native renderer, **Terminal profiles**, **Terminal scrollback** (in settings), **Terminal agent hooks** | Full feature; needs pty/attach protocol (03) |
| **Scripts & services** | **Scripts** — header **Scripts** split button (Run/Stop/Restart, **View terminal**, **View service**, **Reverse proxy**/**Memorable**/**Direct** routes, **Choose URL**, **Copy URL**), status dots (blue running/green healthy/red unhealthy), sidebar service summary | paseo.json **Scripts** group in project settings |
| **Sessions / History screen** | "**History**" — all sessions across hosts/workspaces, date-bucketed (Recent/Today/…/Older), "**Search history**", "**Load more**", archived badge, "No sessions yet"/"No sessions match" | ClaudeUI's sidebar Recents are the visual seed only |
| **Command center** | "**Search commands, files, workspaces, and agents…**" — sections **Actions**/**Files**/**Workspaces**/**Agents** + **Model**/**Thinking**/**Mode**/**Plan mode**/**Fast** agent-control groups, keyboard-driven, shortcut badges | Global overlay; nothing in ClaudeUI |
| **New workspace screen** | "New workspace" — Project/Host/Isolation/Branch/Starting ref pickers, **What to launch** (**Chat**/**Terminal**), **Create**; "**Set up worktree scripts**" callout | Partial analogues: Code draft (#22) provides repository/environment/model chrome |
| **Import session** | "**Import session**" — import CLI sessions from a host (search, scope **This workspace**/"Sessions on {{host}}") | Protocol 04 §4.5 `import_agent_request`; nothing UI-side |
| **Open-project / Home tiles** | "**Add a project**", "**Import session**", "**Setup providers**", "**Pair device**" Home tiles | Desktop-era patterns; iOS version undecided |
| **Workspace deck retention / sheet tabs / side panes** | **Workspace deck retention** (mounted hidden entries), **Sheet tabs** ("**Open as tab**"), **Side pane** (files/diffs/subagents "On the side") | Split/pane model — Core/deck work first |
| **Labels** | **Labels** — user-defined on workspaces; filter sidebar | Labels UI in menus; store \* |

### 6.3 Settings / account / host (partial ClaudeUI counterparts already exist; listed for completeness)

| Gap | Paseo UI labels (doc 01) | Status vs ClaudeUI |
|---|---|---|
| **Providers page** | **Providers** — per-provider rows (icon, **Available/Not installed/Error/Disabled**, "· N models", **switch**, **Remove provider** overflow), **Add provider** (**Install**), **Provider diagnostic sheet** (diagnostic text, discovered models, **Add custom model…**) | No ClaudeUI counterpart; build using RowGroup/SheetRow |
| **Host sections** | Overview (**Appearance** card — **Name**, **Color**, **Sidebar badge** + preview, **Manage built-in daemon** n/a on iOS, **Restart daemon**, "**Danger zone**: **Remove host**"), **Connections** (rows with live latency: "**{{n}} ms**"/**Timeout**, **Remove**), **Pair device** (QR + "Enable relay" upsell), **Agents** (**Enable Paseo tools**, **Browser tools** + trust warning, **System prompt** Edit/Reset/Save, **Resume agents after restart**, **Release idle agents**, **Orchestration skills** (**All skills** toggle + picker), **Agent profiles** (add/edit/reorder; **Name**/**Icon**/**Provider**/**Model**/**Mode**/**Thinking**/**Features**)), **Metadata** (**Metadata generation**, **Automatic/Manual** + model), **Workspaces** ("**Archive merged PR workspaces**"), **Terminals** (**Enable terminal agent hooks**, **Terminal profiles**), **Plugins** ("**Plugins are trusted code**", **Enable plugins**, **Plugin source** + **Install plugin**, plugin rows with **Logs**/**Reload**) | Row chrome reuses ClaudeUI's; none of the content exists |
| **Welcome / onboarding** | "**Welcome to Paseo**" + connection tiles (**Scan QR code** / **Direct connection** / **Paste pairing link**); onboarding steps | New |
| **Add host / pair device flows** | **Add connection** sheet — **Direct connection** ("**Local network or VPN.**", Host/Port/Password/**Use SSL** + **Advanced** URI), **Remote SSH** (desktop), **Scan QR code**, **Paste pairing link** ("**Encrypted relay connection.**"); **Connect**/"**Connecting…**"; host confirmation sheet ("**Connect to this host?**", **Key fingerprint**, **Relay**) | Nothing in ClaudeUI; all iOS-relevant paths |
| **Usage modal + pinned sidebar meters** | **Usage** (modal) — host filter, **Refresh all**, cog (**Check usage**, **Summary in sidebar**, **Percentages Used/Remaining**); **Report cards** (per-window meter rows "**Session** / **Weekly** / **Monthly** / **Code review** / **Credits**", "**resets in {{duration}}**" countdown, **Pin**/**Unpin** per window) | ClaudeUI's `UsageState` covers a static slice; pinned windows/refresh-all/multi-host are new |
| **Shortcuts dialog** | **Shortcuts** — "**Shortcuts**" dialog grouped **General**/**Projects & Workspaces**/**Tabs & Panes**/**Layout**/**Agent Input** (hardware keyboards only) | n/a on iOS keyboards mostly; skip for v1 |
| **Diagnostics** | "**App diagnostic**" (**Run** — client/hosts/desktop/log details, copyable), "**Test audio**" | New page, mostly host-RPC wiring |
| **Keyboard focus / Focus mode** | **Focus mode** (hide chrome) | Defer (desktop/tablet) |
| **Plugins surface/pages** | **Plugin settings screens**, **Plugin surfaces** (`PluginSurfaceScreen`), **Sidebar views** picker | Defer until plugin store lands |
| **Notifications settings (host)** | **Desktop notifications** (**Notification permission**, **Play sound**, **Test notification** **Send**), **Permissions** (**Microphone**) — iOS has OS notification permission + no mic-permission settings row (mic used by Voice) | Adapt from `NotificationPreferences` pattern + `register_push_token` (04 §7.4) |

### 6.4 What the PaseoStore is missing (blockers for the UI work)

The UI cannot be finished until these stores exist — they are named in this task's brief as "coming" and tracked as **not built**: **workspaces list** (pin/archive/status), **git/diff** (status, diff hunks, commits, actions, branch ops), **files/editor** (tree, contents, watch/conflict), **schedules/heartbeats**, **settings** (app appearance; host daemon config get/set), **usage reports**, **agent profiles**, **notification routing/push**, **attachments on send** (no attachment field in `SendAgentMessageRequest`), **queued-message semantics** beyond "steer" (Paseo queues client-side per doc 01 — client may hold the queue), **subagents/tasks** read RPCs, **content-type rendering registry** (ARCHITECTURE.md:73-77 requires one registry — ClaudeUI's markdown is close but not a registry).

### 6.5 ARCHITECTURE.md contradiction to resolve before executing

`ARCHITECTURE.md:24-26` currently says ClaudeUI is "**frozen. Copy pieces into DesignSystem; never depend on it from Core.**" This adoption plan instead edits ClaudeUI **in place** as the basis of the app UI (per the user's decision in the driving ticket) while PaseoKit/PaseoCore stay untouched underneath. Executing Section 4 requires updating `ARCHITECTURE.md`'s ClaudeUI paragraph and PaseoUI's role (it currently assumes "copy pieces into DesignSystem" + PaseoUI Features), or deleting PaseoUI on adoption. Not editable in this ticket — flagged for the owner.

---

## 7. Verification status, open questions, how to re-check

**Verified on this machine (Linux):** line counts (`wc -l`), file list completeness (`find` — 67 Swift + 14 resources), type cross-references (`grep -rln`), no code compile (SwiftUI/UIKit never builds here). **Not verified:** any UI behavior, colors, or motion; Xcode build; the demo; doc/01's Apple vs desktop distinctions applied to iOS.

**Open questions for the owner (do not block the map):**
1. Where do deleted demo screens live — trimmed demo or removed demo? (Blocks Section 4 Phases 1/8.)
2. Does the adoption keep the SwiftPM `Examples/ClaudeUIDemo` as the snapshot harness, or does Paseo dismantle it? (Same answer drives `Package.swift` edits.)
3. `ARCHITECTURE.md` contradiction (§6.5) — who edits it?
4. Voice (§3 #9): does Paseo iOS ship realtime voice in v1? If not, `voiceActive`/`voiceControls` can be deleted with voiceLanguage etc.
5. Widgets (§3 #55): keep `ClaudeWidgets` as a future deep-link opt-in, or delete outright?
6. Are Paseo's UI label strings owned (i18n story?) or literal English as captured in doc 01?

**Quick re-check commands (macOS):** `rg -n "<DeletedType>" Packages/ClaudeUI` after each Section-4 phase; `swift package describe` in `Packages/ClaudeUI`; CI workflow `.github/workflows/ci.yml` (format, project sync, unit tests, iOS 26 SDK build) — see `Packages/ClaudeUI/README.md:5,37` and `docs/TESTING.md`.

**Doc cross-links:** Paseo feature inventory — `docs/research/01-app-features.md` (labels used throughout Section 3/6); protocol research — `docs/research/02-protocol-workspaces-git-files.md`, `docs/research/03-protocol-terminals-scripts.md`, `docs/research/04-protocol-agents-permissions-settings.md`, `docs/research/05-rich-media-spec.md`, `docs/research/06-dsh-ux-spec.md`; PaseoStore implementation — `Packages/PaseoCore/Sources/PaseoStore/` (`Turn.swift`, `TimelineState.swift`, `HostSession.swift`, `Presentation.swift`); ARCHITECTURE.md "The turn" — `ARCHITECTURE.md:54-71`.
