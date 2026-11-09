# M8d: @-file mentions and dictation in the composer

Branch `m8d-mentions-dictation`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update
the matching Composer rows in `docs/PARITY.md` in the same commit. You may edit the **composer
section** of `Chat/ClaudeChatView.swift`, `Chat/ClaudeChatComponents.swift`, composer files you or
M8a/M8b/M6a added, and new files. Do **not** edit the transcript or header (M7d owns them now).

1. **@-file mentions**: typing `@` after whitespace or at the start opens a popover in the same
   place and style as the slash menu (reuse it; one component): files from the open workspace
   via the store (`WorkspaceFiles` / T15 `FileEntries`; fuzzy-ish prefix + substring match on the
   relative path, recent/shallow first, max ~6 rows, folders drill in on tap). Tap inserts
   `@relative/path ` replacing the typed token. Debounce lookups ~150 ms; spinner row while
   loading; hidden when nothing matches. Selection haptic on highlight change.
2. **Dictation**: the composer mic button (today it only focuses the field) starts on-device
   speech recognition (`SFSpeechRecognizer` + `AVAudioEngine`, prefer `requiresOnDeviceRecognition`
   when supported), live partial text appended to the draft at the caret, a quiet level/pulse on
   the mic while listening, tap again to stop; stops on send, on background, after ~2 s of
   silence. Permission prompts only on first use; denied → inline note with a Settings link.
   List the Info.plist keys needed (`NSSpeechRecognitionUsageDescription`,
   `NSMicrophoneUsageDescription`) and add them to the app target if the plist is in `App/`.
3. **Placeholder**: confirm "Type / for commands" shows when the agent has commands (M8a); mark the
   PARITY row accordingly.

Keep every Apple-only API inside `#if canImport(UIKit)` like the rest of PaseoUI. Commit "M8d:
mentions and dictation", don't push. Final message: what changed, store gaps, unsure-compile spots.
