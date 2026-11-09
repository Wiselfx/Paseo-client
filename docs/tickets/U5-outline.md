# U5: Prompt outline the upstream way (DeepSeek, the U3 worker)

Branch `u5-outline` from `foundation`. Read `_U-common.md`.

## User feedback on U3

- The turn rail reserves a permanent right margin in the chat.
- The rail is still visually solid.
- Jump-to-message loads *all* history, which is slow.

**The fix:** port upstream's tested design instead of ours. Upstream:

- `packages/app/src/agent-stream/chat-outline/`: `use-chat-outline.ts`, `model.ts`, `rail.web.tsx`, `hover-intent.ts`;
- `packages/app/src/timeline/timeline-sync-plan.ts` (`planTimelinePromptJump`);
- the protocol `listAgentTimelinePrompts` request/response in `packages/protocol/src/messages.ts`, gated by `features.agentTimelinePromptIndex` (`messages.ts:3912`).

## Work

1. **Protocol + store.**
   - Add the prompt-index request/response types exactly per `messages.ts` (cite lines), with wire tests.
   - Add a store, `PromptOutline` or inside ConversationStore (whichever fits), that fetches the index when the conversation opens and refetches when the latest prompt seq changes, like the `latestPromptSeq` effect.
     - It drops stale responses (request id + `shouldAcceptPromptIndexEpoch`).
     - It resolves the active prompt from the reading position (`resolveActivePromptSeq`).
   - A **jump** to an unloaded prompt fetches the timeline window per `planTimelinePromptJump`, then scrolls to it. Port how upstream turns that fetch into the loaded timeline; check our timeline fetch API supports it, and say so if it doesn't.
   - Unit tests for each of these.
   - **Fallback when the daemon lacks the feature:** the outline covers only the loaded turns. Never load all history.
2. **Delete `loadAllOlder()` and its uses**, including the Jump-to-message sheet's call. The sheet lists the index's prompts. Keep the transcript's one-page-at-a-time auto-load near the top: that part is fine.
3. **Rail, iPhone version of `rail.web.tsx`:**
   - **No reserved width:** remove `reservedWidth` and the transcript's extra trailing padding.
   - **No background plate or material:** only tick marks. Each prompt is a 2 pt high pill, 10 pt wide; the active one is 18 pt wide and in `ink`; the others are in `tertiaryInk`. Port the constants from `rail.web.tsx:13-22`.
   - **Position:** an overlay hugging the trailing edge of the screen, vertically centered on the ticks.
   - **Visibility:** shown while scrolling and for 1.5 s after, then fades out (`revealTurnRail` exists). Hit-testable only while shown, within a 24 pt strip (lead change at merge: a hidden strip stole right-thumb scrolls).
   - **Touching or dragging along the rail** magnifies the slots near the finger (`promptTickMagnification`). A preview bubble shows the prompt text (`PREVIEW_WIDTH` / `HEIGHT` from upstream) on a translucent material, and releasing jumps there.
   - With more prompts than fit, follow upstream's slot math.

## Done

PaseoCore green, `-parse` clean. Commit "U5: prompt outline". Final message per the common rules, plus whether our daemon advertises `agentTimelinePromptIndex`. Check the daemon's version string or the `server_info` features in an existing fixture. Do not call the real daemon.

## Haptics: the rail's signature feel (user request)

Dragging along the rail feels like an iOS picker wheel (the time picker):

- **One crossing, one tick.** Each time the finger crosses into a different prompt slot, fire one selection tick (`UISelectionFeedbackGenerator.selectionChanged()`, or SwiftUI `.sensoryFeedback(.selection, trigger: hoveredIndex)`). Exactly one tick per slot change; never on the same slot. The generator is `prepare()`d when the touch begins, so the first tick has no latency.
- **Releasing to jump:** one `.impact(weight: .light)`. Cancelling (dragging off the rail) gives nothing.
- **Dense rails:** when there are many prompts (slots smaller than ~6 pt of finger travel), throttle to at most one tick per ~35 ms so it stays crisp instead of buzzing.
- Respect the app's existing Haptics setting (`Haptics` helper / the Settings toggle). No haptics while just scrolling the transcript, only for direct touch on the rail.
