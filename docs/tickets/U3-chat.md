# U3: Conversation: history, turn nav, rail, bubbles, mascot, subagents, thinking (DeepSeek)

Branch `u3-chat`. Read `_U-common.md` first. Spec: UX-SPEC §4.2, §4.3, §4.4, §6 (SVG/HTML previews). Audit: B2, B8 (previews part), B9, B10, B11, B12. Upstream for subagents: grep `subagent` in `paseo-reference/packages/app/src` (the `subagents/` folder and its use in the chat).

Avoid `ChatComposer.swift` except for the thinking list in `ClaudeAgentControlsSheet.swift`; U2 and U4 edit the composer.

## Work

1. **History auto-loads** with the scroll anchored, and the "Load earlier" button is gone. You may add a PaseoStore helper `loadAllOlder()` (pages until `hasOlder` is false), with tests.
2. **Turn nav:**
   - The Jump-to-message sheet loads the rest of history and lists every prompt.
   - The turn rail covers the whole loaded conversation, is translucent, and never covers text: reserve its width in the transcript's trailing padding.
3. **Always full messages:** delete the "Show more" collapse.
4. **Bubble long-press:** the preview is shaped to the bubble, plus a "Select text" item that opens a sheet with selectable text. Remove `.textSelection` from bubbles if it causes the rectangle.
5. **Mascot:** seed the baselines after the initial load, and ignore loading-driven changes.
6. **Subagents pill:** visible in the chat while subagents exist (§4.3); find out why it never shows today.
7. **Thinking:** one list control for every provider; delete `EffortLadder` and its use.
8. **Files previews:** SVG via `SandboxedHTMLView` (no scripts); HTML with a Preview/Source segmented control (JS off, no network). Files: `Workspace/WorkspaceFileViewer.swift` and helpers.
