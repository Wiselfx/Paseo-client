# R1: folder moves and dead code

Branch: `r1-moves` (from `foundation`). Read `docs/tickets/_R-common.md` first.
Owns: every file under `Packages/PaseoUI/Sources/PaseoUI/` (moves only) and the deletions below.
Runs alone: everyone else waits for this merge, so keep it mechanical and fast.

## Goal

The folders say what is in them, and dead code is gone. **No logic changes, no type renames, no
formatting changes.** A reviewer must be able to read the diff as "renames + deletions" only.

## 1. Moves (`git mv`, so history follows)

All paths are relative to `Packages/PaseoUI/Sources/PaseoUI/`. Create the folders as needed.

| Destination | Files |
|---|---|
| `DesignSystem/` | `Chat/ClaudeStyle.swift`, `ClaudeSheets.swift`, `ClaudeAppearance.swift`, `ClaudeFontResources.swift`, `Paseo/DesignSystem/Haptics.swift`, `Chat/ClaudeLoader.swift`, `PaseoFormat.swift`, `Chat/ClaudeUsageRing.swift` → rename the file to `DesignSystem/UsageMeters.swift` (it declares `ClaudeMeterRing`, `ClaudeUsageBar`, `ClaudeUsageResets`) |
| `Shell/` | `Chat/PaseoShellView.swift`, `Chat/EdgeDrawer.swift` |
| `Onboarding/` | `ConnectView.swift`, `ConnectionURI.swift`, `WelcomeView.swift` |
| `Pairing/` | `Chat/PairingFlow.swift` |
| `Settings/` | `Chat/PaseoSettingsView.swift` |
| `History/` | `Chat/ClaudeHistoryView.swift` |
| `Sidebar/` | `Chat/AddProjectSheet.swift`, `Chat/ImportSessionSheet.swift`, `Chat/ClaudeUsageReportsSheet.swift` |
| `Schedules/` | `Chat/ScheduleWords.swift` |
| `Notifications/` | `Chat/SoundCues.swift` |
| `Voice/` | `Chat/VoiceAudioEngine.swift`, `Chat/DictationController.swift` |
| `Draft/` | `Conversation/DraftChatView.swift`, `Chat/DraftControlsSheet.swift`, `Chat/ClaudeHomeHero.swift` |
| `Conversation/Screen/` | `Conversation/ClaudeChatView.swift`, `Conversation/ChatHeader.swift`, `Conversation/ChatHeroSeats.swift`, `Conversation/ProviderIconShape.swift`, `Conversation/ChatSheets.swift`, `Chat/ChatDisplay.swift` |
| `Conversation/Composer/` | `Conversation/ChatComposer.swift`, `Conversation/ChatAttachments.swift`, `Conversation/ChatMentions.swift`, `Conversation/ChatSlashCommands.swift`, `Conversation/ChatQueue.swift`, `Chat/ComposerAttachments.swift`, `Chat/ComposerMenu.swift`, `Chat/ComposerQueue.swift`, `Chat/DefaultSend.swift`, `Chat/FullScreenComposer.swift`, `Chat/MentionMenu.swift`, `Chat/SavedDraftStore.swift`, `Chat/CameraCapture.swift`, `Chat/ForgeSearchPicker.swift` |
| `Conversation/Transcript/` | `Conversation/ChatTranscript.swift`, `Conversation/ChatTurns.swift`, `Conversation/ChatTurnRail.swift`, `Conversation/ChatWorkGroup.swift`, `Conversation/ChatFind.swift`, `Chat/ClaudeFindBar.swift` |
| `Conversation/Turn/` | `Chat/ClaudeChatComponents.swift`, `Chat/ClaudeFileCalls.swift`, `Chat/ClaudeToolDetail.swift`, `Chat/ClaudeTurnGlyphs.swift`, `Chat/ClaudeReasoningClause.swift`, `Chat/ClaudeStatusLine.swift`, `Chat/ClaudePermissionCard.swift` |
| `Conversation/Prose/` | `ClaudeMarkdownView.swift`, `MarkdownDocumentModel.swift`, `MarkdownTableMetrics.swift`, `ClaudeCodeHighlighter.swift`, `ClaudeSelectableInlineCode.swift`, `Chat/ClaudeRevealProse.swift`, `Conversation/FilePathLinks.swift`, `ClaudeMediaView.swift`, `MediaState.swift`, and the whole `Rich/` folder → `Conversation/Prose/Rich/` |
| `Conversation/Mascot/` | `Mascot/ClaudeCrabView.swift`, `Conversation/ChatMascot.swift` |
| `Conversation/Sheets/` | `Conversation/ChatSubagents.swift`, `Conversation/ChatBackgroundWork.swift`, `Chat/ClaudeContextSheet.swift`, `Chat/ClaudeAgentControlsSheet.swift`, `Chat/MessageTextSheet.swift` |

After the moves, `Chat/`, `Mascot/`, `Paseo/` and `Rich/` must be empty and deleted. **No `.swift` file stays at
the module root.** If a file isn't in the table, put it in the folder its main type belongs to by the
same logic, and list it in your final message.

`Resources/` stays where it is (`Package.swift` uses `.process("Resources")`). Check that no code uses
`#file` / `#filePath`-relative paths that a move would break (`grep -rn '#file' .`).

## 2. Dead code deletions

Verify each with `grep -rn '<Name>' Packages App` (whole repo) before deleting. Delete only what has
no reference outside its own declaration.

- `ClaudeMotion.tick` and `ClaudeMotion.roll` (`DesignSystem/ClaudeStyle.swift`).
- `ClaudePalette.sidebarBackground`.
- `ClaudeMediaPlaceholder`, `ClaudeVideoFileCard`, `ClaudeVideoFileViewer` (`ClaudeMediaView.swift`). Keep
  `ClaudeMediaState`: `Tests/PaseoUITests/MediaTests.swift` uses it, and tests are never edited.
- `HostColor`, `HostBadgeDisplay`, `HostAppearance`, `HostSwitchContext.appearance(for:)` and
  `setAppearance`, plus their persistence keys (`Settings/HostSwitchContext.swift`). Keep everything else
  in that file.
- `PairingConnectOutcome` (`PairingFlow.swift`).
- `WorkspaceBaseBranchRow` (`Workspace/WorkspaceBaseBranchSheet.swift`).

**Do not delete `InlineCodeRenderer`.** It is unwired, not dead; R2 wires it.

## 3. Proof

- `swiftc -parse` on every moved or edited file (a move doesn't change content, but run it anyway).
- `git diff --stat -M foundation` must show only renames (R100) for moved files, plus the small edits
  for deletions.
- Final message:
  - the list of moved files not in the table, and where they went;
  - each deletion with its grep evidence (0 references).
