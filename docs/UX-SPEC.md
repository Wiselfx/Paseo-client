# UX spec (iPhone first)

The behavior the app must have. Tickets point here; when code and this file disagree, this file
wins. Written by the lead after the first on-device run (2026-11-09). If something here is
impossible or would break a test, stop and say so in your final message instead of improvising.

**Taste rules apply everywhere:**

- Calm, monochrome, content first.
- Every animation is critically damped (no bounce, no overshoot, no wobble).
- One way to do each thing.
- Nothing decorative that isn't doing work.

When in doubt, do what the iOS Claude app or the system apps (Notes, Mail) do.

## 0. Global rules

### 0.1 Color

- The UI is monochrome: ink on canvas, with `secondaryInk` and `tertiaryInk` for hierarchy.
- The clay accent (`ClaudePalette.orange`, #d97757) is allowed only for:
  - the brand mark (§3.1);
  - the crab;
  - the "agent is running" activity glyph, if it already uses it;
  - destructive or failure states (these use `failureInk`, not orange).
- Orange is **never** state on a control: not on chips, the model or thinking label, rings, badges, selection, toggles, or "custom value" highlights.
- **Toggles** use system blue (`.tint(.blue)`) everywhere, matching the other selection controls (checkmarks, selected tiles). No cream or orange toggles.
- **Selection** (a picked option in a list or menu) is a trailing checkmark in ink, or system blue where the screen already uses blue. Don't add colored backgrounds for selection.
- **Status colors** (green/red diff counts, the failure ink) are the only other colors. Rings, meters and progress are ink on a `tertiaryInk` track in light, dark and pure black alike.

### 0.2 Numbers, sizes, dates

- **Numbers:** grouping uses a comma (`119,900`) regardless of the device region, because the UI is English.
  - One helper, `PaseoFormat` (new file `Packages/PaseoUI/Sources/PaseoUI/PaseoFormat.swift`), is the only place numbers are formatted:
    - `PaseoFormat.integer(_:)`
    - `PaseoFormat.compact(_:)`: 1.2k, 3.4M, for tight spots like the context ring.
    - `PaseoFormat.percent(_:)`
    - `PaseoFormat.bytes(_:)`
  - All of them use `Locale(identifier: "en_US")`.
  - Never call `.formatted()` or `NumberFormatter` on a number for display elsewhere, and never interpolate an `Int` into user-visible `Text` without the helper when the number can exceed 999.
- **File sizes:** `ByteCountFormatter` (`.file` style, en_US) fed **bytes**. Verify the unit the daemon sends, from the protocol schema. Folders show no size unless the daemon reports a real recursive size.
- **Times:** shown in the device's time zone and 12/24 h setting (that part *does* follow the region).

### 0.3 Typography and layout

- One line per label. A pill or button whose label can't fit is a design bug: shorten the label (use upstream's shorter wording) or let the pill grow. Never truncate a primary action to "New works…".
- Sheet headers use the shared `SheetHeader`: title leading, close (xmark in a 30 pt circle) trailing, the title never under the button. Any custom header must lay out the same way (the History sheet is the reference).
- SF Symbols must mean what they say:
  - terminal → `apple.terminal` (or `terminal`, whichever exists on iOS 26; check);
  - files → `folder`;
  - changes → `plus.forwardslash.minus`;
  - agents → `bubble.left.and.bubble.right`.
  - Never use `link` or `arrow.up.right` for something that isn't a link.

### 0.4 Motion

- **Drawers, panels and sheets:** one shared animation, `EdgeDrawer.settleAnimation`, set to `.smooth(duration: 0.32)` (critically damped). Reduce Motion: `.easeOut(duration: 0.2)`.
- **No spring with `dampingFraction < 1` on any surface that moves across the screen.** Small "pop" feedback on a button may use `.snappy`.
- **Finger tracking is 1:1** with no animation while dragging. On release, the surface settles by projected position (velocity-aware), the way `EdgeDrawerDrag` already decides.
- **Nothing scales, rotates or changes corner radius during a drawer move.** Only offset and the dim change (see §1).

## 1. The shell: three surfaces, one material

The app is three surfaces:

- **Sidebar** (left, underneath)
- **Conversation** (the main card)
- **Workspace panel** (right, on top)

They must feel like one object: same canvas color family, same corner radius, same shadow, same motion.

### 1.1 Shared material

- **Corner radius:** the device's display corner radius, a constant. Use `EdgeDrawer.cornerRadius`, 55 on Face ID phones, and keep the constant: no `corner * progress` interpolation.
  - A card that covers the screen with display-radius corners is visually identical to the screen, so there is nothing to animate.
  - Shape: `.rect(cornerRadius:, style: .continuous)`.
- **Full bleed:** every surface is laid out **full screen, including safe areas**. The GeometryReader and ZStack use `.ignoresSafeArea()`, and each surface applies the safe-area padding to its *content* inside.
  - The clip shape must cover the whole surface, including the home-indicator area.
  - This fixes the "transparent bottom corner": today the card is clipped to the safe-area frame while its background bleeds under the home indicator.
- **No bezels (seen on device):** the shell currently stops at the safe area, so plain white bands sit above it (behind the status bar) and below it (behind the home indicator), and the drawer cards float inside them. The sidebar canvas, the conversation canvas and the panel canvas must each run under the status bar and the home indicator: no band of any other color, anywhere, at any drawer position.
- **No bezels:** no outer padding, inset frame, border or card-inside-the-screen around any surface's content when it is at rest. At rest the conversation is edge to edge, exactly like a system app. The audit lists the inherited frames; remove them all.
- **Edge, not shadow** (matches the Claude iOS app; screenshots reviewed 2026-11-09): a displaced surface shows a 0.5 pt hairline along its rounded edge (`ink.opacity(0.10)`), faded in with progress. No drop shadow.
- **Dim:** the covered surface gets a scrim of `black.opacity(0.25 * progress)` in light and `0.55 * progress` in dark. In Claude the pushed-aside chat is dimmed almost to the canvas. The scrim lives **inside** the surface's clip shape, so its corners match. Tapping the scrim closes.
- **Canvas:** the sidebar canvas **equals** the conversation canvas (`background`), as in Claude. The hairline edge and the dim separate the two; no color step.

### 1.2 Left sidebar (reveal)

- **Opening:** an edge swipe from the leading edge (24 pt zone), the header's sidebar button, or a two-finger swipe… keep the existing triggers.
- **What moves:** the conversation card slides right to `drawerFraction` (0.82) of the width. The sidebar does not move; it is revealed underneath, at its final position from the start.
- **Closing:** tap the visible strip of the card, swipe it back, or select something in the sidebar.
- **During the move:** only the card's offset, its shadow opacity and the scrim change. Its corners are always display-radius (§1.1).

### 1.3 Right workspace panel (push, full takeover)

The panel is **not** a floating card or pill. It behaves like a navigation push:

- **Open:** swipe from the trailing edge (24 pt zone), or the header's panel button.
- **Open state:** the panel covers **100%** of the width and the full height, including safe areas. It has its own header (see below).
- **Underneath:** the conversation shifts left by 30% of the width (parallax) and dims (§1.1). The panel slides in from the right with its own shadow on its leading edge.
- **Panel header:**
  - leading: a `chevron.left` back button, which closes the panel;
  - center: the workspace name;
  - below the header: the tabs Agents · Files · Changes · Terminal, as they are now.
- **Dismiss:**
  - the back button;
  - an edge swipe from the panel's **leading** edge (24 pt);
  - a horizontal drag on the header;
  - a horizontal drag anywhere on content that does not itself scroll horizontally. Diff and code views, which scroll sideways, are excluded: there only the edge, the header or the back button dismiss.
- **Dragging:** the panel tracks the finger 1:1 and settles with the shared animation.
- **Persistence:** the panel keeps its tab and scroll position when closed and reopened for the same workspace.

### 1.4 Coherent motion

The two drawers share `EdgeDrawerDrag` and `settleAnimation`. While one is open, the other's gesture is disabled. Settling must never overshoot. There must be no double animation (an implicit `.animation` modifier plus a `withAnimation` on the same value) and no layout jumps when a drawer finishes opening (for example, the panel inserted via `if` at the end of the animation).

## 2. Sidebar contents

From top to bottom:

1. The "Paseo" title row, with the display-options menu.
2. *(The pill lives in the footer; see 5.)* A **"New session"** pill: `plus` symbol + "New session" (upstream fallback title `en.ts:292`; the user chose this wording). Full width or hugging the label, but never truncated.
   - It opens a **new draft session in the current workspace** (§3): the workspace of the conversation on screen.
   - With no conversation on screen, it uses the most recently used workspace.
   - With no workspaces at all, the draft shows the hero with an "Add project" call to action instead of a composer.
3. Navigation rows: Search, History, Schedules, and the others as now, then **Import session**, then **Add project** (moved here from the projects list).
4. The projects and workspaces directory.
   - Each workspace row's `+` opens a draft session in that workspace.
   - There is **no** "Add project" row inside the projects list.
5. The footer, as in Claude:
   - the settings avatar circle leading;
   - the **"New session"** pill trailing: an inverted capsule (`ink` fill, `background` text, `plus` + "New session"), sized to its label, never truncated;
   - the host chip is removed from the footer;
   - the usage section, if enabled, sits above the footer.

**Removed from the sidebar:**

- The host badge and the host row/switcher. The host lives in Settings only.
- Delete the Settings → Appearance "Sidebar badge" section (hidden / icon only / colors) and the per-host badge appearance it writes, if nothing else reads it. Keep the host *name* editing that lives in host settings.

## 3. New session: draft → conversation (replaces the New Agent screen)

Upstream model: a draft tab in the workspace, whose composer creates the agent on the first send (`paseo-reference/packages/app/src/screens/workspace/workspace-draft-agent-config.ts` and the `draft` tab kind in `workspace-screen.tsx`).

**`ClaudeNewAgentSheet` is deleted.** Every "New agent" entry point routes to a draft session:

- the sidebar pill and the workspace `+`;
- the panel's Agents tab;
- the composer's + menu;
- the command center;
- deep links and schedules, where they create agents.

### 3.1 The draft screen

- **Placement:** the conversation surface itself (not a sheet). The header shows the workspace name.
- **Body (hero):** the brand mark above a serif greeting, vertically centered in the space above the composer, rising in as it does today.
  - The mark is the **DSH Claude mark** (`dsh-claude-style-reference/packages/assets/src/brand/claude-mark-clay.svg`, color #D97757). Add it as a vector asset (`preserves-vector-representation`) in `PaseoUI/Resources/Assets.xcassets`, about 44 pt tall.
  - **No sun or sparkle symbol.**
- **Composer:** at the bottom, exactly the normal composer. In draft state its control row shows a **model chip that also carries the provider**: provider glyph + model name, grey per §0.1.
  - Tapping the chip opens the controls sheet with Provider (only in draft), Model, Thinking (§4.2) and Mode.
  - Defaults are the last-used provider/model/mode for this host (the existing create-agent preferences).
- **What's not here:** no separate form, no big provider/model/thinking/mode logo tiles.
- **Workspace line:** a quiet line above the composer, `in <workspace name>` in `secondaryInk`. It's a menu for switching to another workspace, grouped by project.

### 3.2 First send

1. On send, create the agent in the draft's workspace with the chosen provider, model, thinking and mode, the prompt text and the attachments (the existing `AgentControlStore.createAgent` path, including attachments).
2. The user's message appears immediately as a pending bubble. The greeting fades out (0.2 s), and the view becomes the normal conversation for the new agent with no navigation jump.
3. If creation fails, the draft comes back with the text intact and the error inline above the composer.
4. **After creation the provider is fixed.** The chip shows only the model (and thinking), and the controls sheet no longer offers Provider, as upstream does once a session is bound to its harness.

## 4. Conversation

### 4.1 Composer: dynamic (Claude iOS reference, screenshots 2026-11-09)

- **At rest** (not focused, empty draft, no attachments): a **single-line pill**. Leading: the `+` circle. Then the placeholder, then the mic and the voice button trailing. No model chip, no context ring and no other chips in this state.
- **Focused, or with text or attachments:** the pill grows smoothly into a **two-row card**:
  - row 1: the text field;
  - row 2: `+`, the model chip ("Model *Thinking*": model in ink, thinking level in `secondaryInk`, grey chip fill), then the remaining chips (fast mode, context ring), with mic and voice/send trailing.
- **Transition:** one `.smooth(duration: 0.25)` (§0.4) on height and chip opacity; the text field never jumps horizontally.
- **Collapse:** it returns to the pill on blur, only when the draft and tray are empty.
- **While a turn runs:** the stop button replaces send, in either state.

### 4.1b Composer chips

- **Model chip:** grey (`chip` fill, `ink` text, `secondaryInk` thinking label). No orange in any state, including "custom thinking".
- **Context ring:** monochrome per §0.1. The ring fills with ink as context fills. At ≥ 90% the stroke gets thicker; no color change. Its label uses `PaseoFormat.compact`.

### 4.2 Thinking selection

Every provider uses the **same list control** Claude uses today: one row per level, the current level with a checkmark, the levels in the order the provider reports them.

Delete the slider (`EffortLadder`) path and its fallback condition.

### 4.3 Transcript

- **History loads itself.** When the top of the transcript comes within ~1 screen of the viewport, older history is fetched automatically, and the scroll position stays anchored on what the user is reading (no jump). While loading, a small spinner sits at the top; there is no "Load earlier" button. Stop when `hasOlder` is false.
- **Every message is shown in full.** No "Show more" or "Show less" collapse on agent or user messages. (Collapsed *tool-call groups* and the "collapse turns" display mode are separate features and stay.)
- **The turn rail never covers text.** The right-side prompt rail (good feature, keep it) is currently solid and eats message text. It must be a thin, translucent strip in the trailing margin. The transcript's trailing padding reserves its width, so no message text ever sits under it. Expanded or hover-labels float over a translucent material, never an opaque block.
- **Subagents are visible.** Running and finished subagents show as a pill in the chat, as upstream does. Port upstream's placement and wording, and cite it. Tapping the pill opens the subagents sheet. If the pill code exists but never shows, find out why (the store never fills `subagents`? a gate?) and fix it.
- **Turn navigation knows every prompt:**
  - The "Jump to message" sheet lists every user prompt of the conversation. When opened while older history is unloaded, it loads the remaining history first: rows appear as they arrive, with a spinner row at the end until `hasOlder` is false.
  - Choosing a prompt scrolls to it.
  - The right-side scroll rail represents the whole conversation. Its ticks are recomputed as history loads.
- **Message long-press:** a context menu whose **preview is the bubble itself**, clipped to the bubble's rounded shape (`.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: <bubble radius>, style: .continuous))`). There is no rectangular highlight and no inset.
  - Text selection is offered as a menu item, "Select text", which opens a sheet with the message as selectable text.
  - Nothing else highlights the bubble.

### 4.4 Mascot

The crab reacts only to **live** events after the conversation has finished its initial load:

- the snapshot;
- the history fetch;
- the turns already present when the conversation opened.

On open it starts idle. Old failed tool calls or a last turn that ended in failure must not play the error animation. Seed all baselines from the loaded state *before* observers start, and ignore changes that arrive as part of loading history.

### 4.5 Voice

- The voice-mode button and dictation must never crash.
- Every closure that AVFoundation, Speech or NotificationCenter may call off the main thread is created in a `nonisolated` context or marked `@Sendable`, and hops to the main actor explicitly.
- Permission denial shows the existing inline note; it is never a crash.

## 5. Sheets and pages

- **Search (command center):** the header follows §0.3. The close button sits trailing and does not overlap "Search". Match the History sheet.
- **Schedules:** the cadence is human readable. Show the time in the device's time zone; the schedule's own time zone appears only in the detail page.

  | Cron | Shows |
  |---|---|
  | `*/N * * * *` | "Every N minutes" |
  | `M * * * *` | "Hourly at :MM" |
  | `M H * * *` | "Daily at 9:30 AM" |
  | `M H * * 1-5` | "Weekdays at 9:30 AM" |
  | `M H * * D` | "Every Monday at 9:30 AM" |
  | `M H d * *` | "Monthly on the 9th at 9:30 AM" |
  | `M H d m *` | "Once a year on Nov 9 at 1:21 AM" (upstream wording if it exists; cite) |

  Anything else shows "Custom schedule" in the list, with the raw expression in the detail page only. If upstream has a describer or wording for this, port it verbatim and cite it. The describer is a pure function in PaseoCore with unit tests.
- **Settings → Providers:**
  - toggles in system blue (§0.1);
  - if upstream lets the user add providers beyond the built-in list, match its flow and wording (the audit cites it).
- **Settings → Appearance:** drop the Sidebar badge section (§2).

## 6. Workspace panel → Files

- **Sizes:** formatted per §0.2. Folders show no size. On device every folder showed "30 B", "498 B" and so on: that is the directory inode size, not its contents. Folder rows show only the modified time.
- **Previews:**
  - Images and markdown stay as they are.
  - **SVG** renders as an image in the sandboxed web view (`SandboxedHTMLView`), with no scripts and fit-to-width.
  - **HTML** gets a Preview / Source segmented control. Preview renders in `SandboxedHTMLView` with JavaScript off and no network.
  - Everything else stays highlighted source.
- The Terminal tab uses the terminal symbol (§0.3).
