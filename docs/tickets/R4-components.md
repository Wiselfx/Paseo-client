# R4: shared components

Branch: `r4-components`, from `foundation` after R2 is merged. Read `docs/tickets/_R-common.md`
first. Plan: `docs/refactor/PLAN.md` §RA2 and §RH; evidence: `docs/refactor/audits/A-design-system.md` §2.

**Owns:**
- new files under `DesignSystem/Components/`;
- adoption in **small leaf files only**: the files listed in §3.

The big screens (Shell, Conversation, Workspace, Settings, Sidebar, Schedules, History) adopt these
components in their own tickets (R5–R10). **Don't edit them here.**

Every component uses only R2 tokens: `Font.paseo`, `Palette`, `Radius`, `Space`, `Motion` and `Haptics`.
Each gets a `#Preview` showing every state in light and dark.

## 1. Components (exact behavior)

### `SheetScaffold`

```swift
struct SheetScaffold<Content: View>: View {
    init(_ title: String,
         detents: SheetDetents = .large,          // .large | .mediumLarge | .medium
         confirm: SheetConfirm? = nil,            // (title or nil, isEnabled, isWorking, action)
         onClose: (() -> Void)? = nil,            // default: dismiss()
         @ViewBuilder content: () -> Content)
}
```

- **Structure:** a `NavigationStack` with `.navigationTitle(title)` and `.toolbarTitleDisplayMode(.inline)`.
- **Toolbar:**
  - `ToolbarItem(placement: .cancellationAction) { Button(role: .close) { onClose ?? dismiss() } }`;
  - when `confirm != nil`, `ToolbarItem(placement: .confirmationAction) { Button(role: .confirm) … }`,
    disabled while `!isEnabled`, showing a `ProgressView` while `isWorking`.
- **Presentation:**

  | Modifier | Value |
  |---|---|
  | `.presentationDetents` | from `detents` |
  | `.presentationDragIndicator` | `.visible` for `.medium` / `.mediumLarge`, `.hidden` for `.large` |
  | `.presentationBackground` | `Palette.background` |
  | `.scrollContentBackground` | `.hidden` |

  No `presentationCornerRadius`: the iOS 26 system shape.
- **Pushed pages** inside the sheet use `navigationDestination`; the system back button and
  swipe-back come for free.
- **Dirty state:** `.sheetDirty(_ isDirty: Bool)` sets `interactiveDismissDisabled(isDirty)`. The close
  button then shows `confirmationDialog("Discard changes?")` with "Discard changes" (destructive) and
  "Keep editing" (cancel). That wording is approved for this round.

### `ShellHeader`

```swift
struct ShellHeader<Title: View, Trailing: View>: View {
    enum Leading { case sidebar(() -> Void), back(() -> Void), none }
    init(leading: Leading, @ViewBuilder title: () -> Title, @ViewBuilder trailing: () -> Trailing)
}
```

- 48 pt tall, horizontal padding `Space.md`.
- Leading: `GlassIconButton` with the `UnequalMenu` shape ("Open sidebar") or `chevron.left` ("Back").
- The title is centered and fills the remaining width.
- Trailing slot: buttons are 44 × 44.

### `GlassIconButton`

`GlassIconButton(systemName:, label:, action:)`:
- a 44 × 44 hit area;
- the symbol at `.glyph(.regular, weight: .medium)`;
- `.glassEffect(in: .circle)`;
- an `accessibilityLabel`.

There is also an initializer taking a custom `Shape` label, for `UnequalMenu`.

### `PrimaryButtonStyle` / `SecondaryButtonStyle`

- **Primary:**
  - an ink capsule, min height 44, horizontal padding `Space.xl`, text `Font.paseo(.callout, weight: .semibold)` in `Palette.background`;
  - pressed: opacity 0.85 with `Motion.feedback`;
  - disabled: opacity 0.4.
- **Secondary:** the same shape with a `Palette.chip` fill and `ink` text.
- **Working state:** `Button { } label: { … }.buttonStyle(.paseoPrimary(isWorking: Bool))`. While
  working, the label is replaced in place by a small `ProgressView` tinted to the text color,
  the width stays the same (overlay the spinner, hide the label with opacity 0), and taps are ignored.

### `PressableRowStyle`

A `ButtonStyle` for full-width rows. Pressed = a `Palette.chip` background over the row's shape,
fading in and out with `Motion.feedback`. It also publishes `\.claudeRowPressed`, absorbing today's
`ClaudePressButtonStyle`.

### `ListRow`

```swift
ListRow(title: String, subtitle: String? = nil, systemImage: String? = nil,
        accessory: ListRow.Accessory = .none)  // .none | .chevron | .checkmark(Bool) | .value(String) | .toggle(Binding<Bool>) | .badge(String) | .progress
```

- min height 44; padding `Space.lg` horizontally, `Space.md` vertically;
- the leading glyph is `.glyph(.regular, weight: .light)` in `tertiaryInk`, in a 24 pt frame;
- the title is `.body`, the subtitle `.footnote` `secondaryInk` (multi-line allowed);
- the checkmark uses `Palette.selection`;
- the toggle uses `.tint(Palette.toggleTint)`;
- it is wrapped in a `Button` with `PressableRowStyle` when given an action.

This replaces `SheetRow`: keep `SheetRow` as a thin wrapper that calls `ListRow`, so unconverted
call sites keep working, and mark it deprecated.

### `RowGroup`

The existing one: a `Palette.panel` fill, `Radius.group`, `RowDivider`s inset by `Space.lg`. Move it to
Components and keep its API.

### `SectionHeader`

`SectionHeader("Title")`: `.footnote` semibold, `secondaryInk`, uppercase **off** (sentence case),
padding `Space.lg` leading, `Space.sm` bottom, `Space.xl` top.

### `EmptyState`

```swift
EmptyState(systemImage: String?, title: String, message: String? = nil, action: (title: String, run: () -> Void)? = nil)
```

- centered in the available space with `maxWidth` 320;
- the glyph is `.glyph(.xlarge, weight: .light)` in `tertiaryInk`;
- the title is `.callout` medium `ink`, the message `.footnote` `secondaryInk`, center-aligned;
- the action is a `SecondaryButtonStyle` button;
- spacing between elements is `Space.md`.

### `LoadingState`

`LoadingState(_ label: String? = nil)`:
- a centered `ProgressView().controlSize(.regular)`, tinted `secondaryInk`;
- the label, when present, is `.footnote` `secondaryInk` below the spinner;
- it fades in after **0.3 s**, so fast loads never flash a spinner.

`InlineProgress()` is the small spinner (`.controlSize(.small)`, `secondaryInk`) for rows and buttons.

### `InlineBanner`

```swift
InlineBanner(_ kind: .info | .warning | .failure, title: String, message: String? = nil,
             systemImage: String? = nil, action: (String, () -> Void)? = nil, onDismiss: (() -> Void)? = nil)
```

- **Fill:**
  - `.info` and `.warning`: `Palette.chip`;
  - `.failure`: `failureInk.opacity(0.10)`.
- **Text and icon color:** `.failure` uses `failureInk`; `.warning` uses `Palette.warning` for the
  icon only; otherwise `secondaryInk`.
- **Layout:** `Radius.md`, min height 44. The title is `.footnote` medium.
- **Action:** a trailing plain button, `.footnote` semibold, `ink`.
- **Dismiss:** a 44 pt xmark hit area.

### `Toast` and `ToastCenter`

```swift
@MainActor @Observable final class ToastCenter {
    func show(_ message: String, systemImage: String? = nil, undo: (() -> Void)? = nil, duration: Duration = .seconds(2.5))
}
// environment: \.toast (ToastCenter); modifier: .toastHost(center) — put once at the shell root
```

- **One toast at a time.** A new one replaces the current one, and the timer belongs to the
  current toast's id, so an old timer never clears a newer toast. That fixes the stale-timer bug.
- **With undo:** the duration is 4 s, plus a trailing "Undo" button. Tapping Undo runs it and hides
  the toast.
- **Look:** a capsule with `.glassEffect()`, text `.footnote` medium, padding `Space.lg` × 10. It sits
  at the **top**, below the safe area and the 48 pt header (`padding(.top, 56)`), enters with
  `Motion.fade` plus 6 pt of downward offset, and is not hit-testable except for Undo.
- **Accessibility:** it posts `AccessibilityNotification.Announcement(message)`.
- **Above sheets:** the host must also show toasts raised while a sheet is open. Implement it with
  an overlay `UIWindow` (`windowLevel = .alert + 1`, `isUserInteractionEnabled` only on the toast's
  rect), hosting a `UIHostingController` that observes the center. The window is created lazily
  from the active `UIWindowScene`.

### `CopyButton`

`CopyButton(text: String, label: String = "Copy")`:
- the `doc.on.doc` symbol swaps to `checkmark` for 2 s with `Motion.feedback`;
- `Haptics.selection()`;
- the hit area is 44 pt;
- it calls the shared `Clipboard.copy(_:)` helper (new, `DesignSystem/Clipboard.swift`, which wraps
  `UIPasteboard.general.string`).

Also add `Clipboard.copy(_:toast:)`, which shows a toast through `ToastCenter` when given one.

### `StatusDot`

```swift
StatusDot(_ state: .running | .attention | .failed | .idle | .unread)
```

- 8 pt;
- `.running`: `ink` with a 1.2 s opacity pulse (0.35 ↔ 1). There is no pulse under Reduce Motion,
  and the pulse pauses when `\.isSurfaceObscured` is true (that environment key is defined here,
  default false);
- `.attention`: `Palette.orange` (the existing attention color);
- `.failed`: `failureInk`;
- `.idle`: clear;
- `.unread`: `Palette.unread`.

Keep `ClaudeStatusDot` and `PaseoStatusDot` as wrappers that map their inputs onto `StatusDot`, and
mark both deprecated.

### `StatePill`

`StatePill(_ text: String, tone: .neutral | .success | .failure | .warning)`:
- a capsule, `.caption2` medium;
- horizontal padding `Space.sm`, vertical 3;
- fill = the tone color at 0.14; the text color is the tone ink (`ink` for `.neutral`).

### `DiffStat`

`DiffStat(added: Int, removed: Int)`:
- mono digits (`.codeSmall`);
- `+N` in `diffAddedInk`, `−N` in `diffRemovedInk` (a U+2212 minus);
- zero counts are hidden;
- numbers go through `PaseoFormat.integer`.

### `AppearancePicker`

Move the appearance picker from `Settings/PaseoSettingsView.swift` into a component, with the same
look as Settings today. `WelcomeView` must render the same component, not its copy.

## 2. Formatting helpers (`DesignSystem/PaseoFormat.swift`)

Add `PaseoFormat.relative(_ date: Date) -> String`. It uses one static `RelativeDateTimeFormatter`
(`.named`, `.abbreviated` units, en_US, matching the existing per-row outputs), plus
`PaseoFormat.dateTime(_:)` and `PaseoFormat.time(_:)` (static `DateFormatter`s in the device locale,
for times per UX-SPEC §0.2). Then replace the per-call formatters listed in audit B N10 **only in the
files this ticket owns**; the screen tickets do the rest.

## 3. Adoption in leaf files (this ticket only)

Convert these to `SheetScaffold`, `ListRow`, `EmptyState`, `LoadingState`, `InlineBanner` and
`CopyButton` as they apply:

- **Sheets:**
  - `Conversation/Sheets/MessageTextSheet.swift`, `ClaudeContextSheet.swift`, `ChatSubagents.swift`
    (also rename "Archive finished" → "Hide finished", not destructive, no confirmation),
    `ChatBackgroundWork.swift`;
  - `Workspace/WorkspaceCreatePRSheet.swift`, `WorkspaceBaseBranchSheet.swift`,
    `WorkspaceBranchSwitcherSheet.swift`, `WorkspaceChangesCommitSheet.swift`,
    `WorkspaceSetupSheet.swift`, `WorkspaceTerminalFileSheet.swift`;
  - `Sidebar/ClaudeNewWorkspaceSheet.swift`, `Sidebar/AddProjectSheet.swift`,
    `Sidebar/ImportSessionSheet.swift`, `Sidebar/ClaudeUsageReportsSheet.swift`;
  - `Settings/HostChooserSheet.swift`, `ProviderDetailSheet.swift`, `SpeechProviderSheet.swift`,
    `AgentProfileEditSheet.swift`;
  - `Pairing/PairingFlow.swift` sheets.
- **Dirty state:** set `sheetDirty` on `WorkspaceChangesCommitSheet` (message non-empty),
  `WorkspaceCreatePRSheet` (title/body edited), `ClaudeNewWorkspaceSheet` (any field edited), and
  `AgentProfileEditSheet` (edited).
- **Detents:**

  | Detent | Sheets |
  |---|---|
  | `.large` | NewWorkspace, AddProject, ImportSession, UsageReports, PR, ProviderDetail, SpeechProvider, AgentProfileEdit, the Pairing sheets |
  | `.mediumLarge` | MessageText, Context, Subagents, BackgroundWork, BaseBranch, BranchSwitcher, CommitSheet, SetupSheet, TerminalFile, HostChooser |

  Remove each sheet's old header and old presentation modifiers.

## Proof

- `swiftc -parse` on every touched file.
- Style lint: still 0 in the files you touched.
- Final message:
  - every component with its file;
  - every adopted sheet with before/after detents;
  - **Unsure:** `Button(role: .close)` / `.confirm` (iOS 26), `toolbarTitleDisplayMode`, the overlay
    `UIWindow` toast host, `AccessibilityNotification.Announcement`.
