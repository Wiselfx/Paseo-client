# U2: New session: the draft replaces the New Agent sheet (DeepSeek)

Branch `u2-new-session`. Read `_U-common.md` first. Spec: UX-SPEC §3 (all), §0.1, §4.1. Upstream to read first:

- `paseo-reference/packages/app/src/screens/workspace/workspace-draft-agent-config.ts`
- the `draft` tab kind in `workspace-screen.tsx`
- `composer/agent-controls/model-sheet.tsx`, especially the folded model control with its provider glyph

Audit: A6, A11.

U1 runs in parallel and adds `onNewSession(workspaceId: String?)` from the sidebar to the shell. In the shell, touch only `openNewAgent` / the `newAgentRequest` sheet and what `main` shows, so merges stay small.

## Work

1. **Draft state:**
   - A draft is a workspace plus pending agent settings (provider, model, thinking, mode, features), seeded from the existing create-agent preferences.
   - Put the logic in PaseoStore as a small `@MainActor @Observable` type, with tests: seeding, provider switch resets model/thinking/mode to that provider's defaults, building the `createAgent` arguments, and the failure path keeping the text.
   - Reuse `AgentControlStore.createAgent` (with attachments, if the API has them; otherwise say so).
2. **UI:**
   - `main` shows the draft when there's no selected agent, or after `onNewSession`/`openNewAgent`. The draft is the conversation surface in hero state: the brand mark (the vector asset from the DSH SVG; delete `ClaudeAsteriskMark`), the greeting, the workspace line menu and the normal composer.
   - The composer's model chip carries the provider glyph in draft. The controls sheet shows Provider only in draft.
   - The thinking control is the list (U3 deletes the slider; if both land, the list wins).
3. **First send:** create the agent, show the pending bubble and fade the greeting, then switch to the live conversation without a navigation jump. On failure, restore the text and show the error inline.
4. **Dynamic composer** (UX-SPEC §4.1): a single-line pill at rest, a two-row card when focused or non-empty, in both the draft and live conversations. You own `ChatComposer.swift` this round; U4 only touches the chip color and context-ring color there, so expect tiny conflicts.
5. **Delete `ClaudeNewAgentSheet.swift`.** Route every "New agent" entry point to the draft: the panel's Agents tab, the composer + menu, the command center, the sidebar, and deep links. Grep for `openNewAgent`, `NewAgentRequest`, `ClaudeNewAgentSheet`, `onNewAgent`.

## Acceptance

PaseoCore tests green. Describe frame by frame:

- New session → the greeting screen with the workspace line;
- pick another provider;
- type and send;
- the conversation appears;
- the chip now shows the model only.
