# R11: final sweep: launch, states, copy, accessibility

Branch: `r11-sweep`, from `foundation` after R5–R10 are merged. Read `docs/tickets/_R-common.md`,
PLAN §RF and §RH, and all three audits. Runs alone. **Owns every file**, for the changes listed here only.

## 1. Launch (audit B J)

- `AppModel.init` does only cheap synchronous work. Move these into a `func start() async`, called
  from `RootView`'s `.task`:
  - the Keychain read;
  - the legacy-host migration;
  - the host refresh;
  - the first connect.
- **First frame:** if a saved host exists, `RootView` shows the shell skeleton (`ShellView` canvas +
  an empty main with the header) while connecting, **not** the connect form. The connect form
  shows only when there's no saved host, or when the connect fails (today's failure path).
- **Fonts:** `ClaudeFontResources.register()` runs in `App.init` (synchronous, once). Remove the
  calls from view `init`s.

## 2. State matrix (audit C §3)

Every screen in this table gets the R4 components:
- loading = `LoadingState` (the 0.3 s delayed fade);
- empty = `EmptyState`;
- error = `InlineBanner(.failure)` with "Try again";
- offline = the shell banner only (nothing per screen).

| Screen | Loading | Empty | Error | Offline |
|---|---|---|---|---|
| Transcript | | | | |
| Sidebar | | | | |
| History | | | | |
| Schedules | | | | |
| Files | | | | |
| Changes | | | | |
| Terminals | | | | |
| Settings host pages | | | | |
| Search | | | | |
| Panel Agents | | | | |

Fill gaps only; the screen tickets did most of it. Report the final matrix.

## 3. Copy (audit C #20, #21 and §5)

- **Sentence case** for every user-facing label that is ours: Title Case strays like "Background
  Work" and "Photo Library" become sentence case **unless the string is upstream verbatim** (check
  `en.ts`).
- **"host" vs "daemon":** "host" is the user-facing noun. "Daemon" stays only in troubleshooting
  sentences (for example "Check that the daemon is running").
- **Jargon:**
  - "Server ID", "Protocol version", "Terminal agent hooks" (Settings → Overview): move them under
    a collapsed "Advanced" disclosure;
  - "agentProfiles feature" → the upstream wording, or a plain sentence;
  - list each replacement in your final message for the lead to check.
- **Rename labels:** "Rename…" in menus and "Rename" in alerts. The alert titles say what is being
  renamed: "Rename agent", "Rename workspace", "Rename terminal", "Rename project".

## 4. Accessibility (audit C #15, #16, §6)

- **Tap targets:** every remaining control under 44 pt gets a 44 pt hit area without changing its
  visuals.
- **Dynamic Type:** run the app's fixed `.frame(height:)` on text containers through the R2 rule
  (`minHeight`).
- **VoiceOver:**
  - every icon-only control has a label;
  - toasts announce (R4);
  - the drawers hide the covered surface (R5).

  Verify, and fix any gaps.
- **Reduce Motion:** all motion goes through `Motion.resolved` (R2). Verify that no literal
  animation is left.

## 5. Haptics audit (PLAN §RH)

`grep -rn 'Haptics\.' Packages/PaseoUI`, and check each call against the RH table: one per user
intent, none on appearance. Remove the doubles. List what you removed.

## 6. Lint to zero, and the docs

- Style lint total = 0 outside `DesignSystem/` and `Conversation/Prose/` (prose is allowed only its
  `ProseFonts` sizes).
- Update `ARCHITECTURE.md`'s PaseoUI section to the new folders, and add the R-1…R-6 rules from
  PLAN §1 to `AGENTS.md` under "UI rules".
- Remove the deprecated wrappers (`SheetRow`, `ClaudeStatusDot`, `PaseoStatusDot`,
  `ClaudeTypography` outside prose, `typealias ClaudePalette`) once nothing uses them.

## Proof

- `swiftc -parse`.
- Lint 0.
- PaseoCore tests green, if touched.
- The final message has the state matrix, the copy list and the haptics list.
