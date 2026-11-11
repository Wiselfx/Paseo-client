# E2: the front card, the accent theme, launch, connect, files canvas

Branch `e2-look`, from `foundation`. Read `_E-common.md` first.

**Owns:**
- `DesignSystem/Palette.swift`
- `DesignSystem/ClaudeAppearance.swift`
- `DesignSystem/SettingsKeys.swift`
- `Shell/` (all files)
- `Conversation/Composer/ComposerPrimaryButton.swift`
- `Conversation/Composer/FullScreenComposer.swift` (the accent only)
- `Workspace/PaseoTerminalKeyBar.swift` (the latch tint only)
- `Workspace/WorkspaceFilesView.swift`, `Workspace/WorkspacePanel.swift` (canvas colours only)
- `Onboarding/ConnectView.swift`
- `Settings/GeneralPage.swift` (the accent picker)
- `Conversation/Transcript/ChatTranscript.swift` and `ChatTurnRail.swift` (the rail switch only)
- `App/Sources/RootView.swift` (environment wiring only)

## 1. The open sidebar: the chat stays in front, it doesn't fade into the background

Compare the user's screenshots, outside the repo (private, never commit them): `/home/paseo/dev/e-round-shots/claude-sidebar-open.jpg` vs `ours-sidebar-open.jpg`.
- **Claude:** with the sidebar open, the chat card keeps its own colour, white in light. It sits in
  front, with a soft shadow on its leading edge and its big rounded corner, so the sidebar reads as
  a layer *behind* the window.
- **Ours:** we lay a black scrim over the card (`EdgeDrawer.scrimOpacity`: 0.25 light, 0.55 dark,
  `ShellContainer.swift:180`), so the chat turns grey and looks like a disabled background item.

**Build (`ShellContainerController` / `EdgeDrawer`):**
1. **No dimming.**
   - `scrimOpacity` returns 0 in both themes.
   - Keep `dimView` as the transparent tap-to-close and VoiceOver "Close" target. It keeps its
     interaction rules and its accessibility. Only its alpha stays 0.
2. **Depth through a shadow, not a scrim.**
   - The conversation card gets a layer shadow:
     - light: black at opacity 0.10, radius 24, offset (−2, 0);
     - dark: black at opacity 0.45, radius 24.
   - Add the values as tokens in `EdgeDrawer` (`DesignSystem`-style constants).
   - **Always set `layer.shadowPath`**: a continuous rounded rect with the card's corner radius,
     updated only in `viewDidLayoutSubviews`. Without a path the shadow is computed offscreen every
     frame of the drag, which is exactly the jank we must never ship.
   - Shadow opacity follows the drawer progress (0 closed → full at open). Set it in the same place
     `dimView.alpha` is set today: `layer.shadowOpacity`, no animation blocks of its own, so it
     tracks the finger and the spring.
   - Turn off `masksToBounds` on the shadow-carrying layer. If the card clips its content, put the
     shadow on a container layer behind the clipping view. Don't lose the existing hairline.
3. **Sidebar colour, one step below the card,** so the separation reads in light:
   - light `Palette.sidebar` → `#F4F3EF` (Claude's sidebar);
   - dark stays `#0B0B0B` (card `#151515`); pure black stays.
   - Check that the sidebar's selected-row fill and its footer pill still read on the new colour.
     Adjust them only via tokens.
4. The card's corner radius while open stays `EdgeDrawer.cornerRadius` (the display radius).
5. The right panel (workspace panel) uses the same treatment: no scrim, the same shadow on the
   card's trailing edge.

## 2. Accent: a "Paseo" theme option, green instead of Claude orange

The user wants to *try* Paseo green next to Claude orange. **It's an option, not a replacement.**
Dark, light and pure black all stay. Only the accent changes.

1. **The model.**
   - `enum ClaudeAccent: String, CaseIterable { case claude = "Claude", paseo = "Paseo" }` in
     `ClaudeAppearance.swift`, with `storageKey = "paseo.accent"`, default `.claude`.
2. **The palette.**
   - `Palette.accent`: the fill for the send button and active voice.
     - Claude: `Palette.orange` (#D97757), both themes.
     - Paseo: `#20744A` light, `#2E8A5C` dark (upstream `theme.ts` accent `#20744A`; one step
       lighter in dark so it keeps contrast on #151515).
   - `Palette.accentInk`: accent-coloured glyphs and text.
     - Claude: #D97757.
     - Paseo: `#20744A` light, `#7CCBA0` dark (upstream `accentBright`).
   - `Palette.onAccent`: the glyph on an accent fill. White in both themes, for both accents.
   - Implement it like `PureBlackTrait`: an `AccentTrait` (`UITraitDefinition`) plus an
     `EnvironmentKey` that is `UITraitBridgedEnvironmentKey`.
     - The colours are dynamic `UIColor` providers that read the trait, so a switch redraws live,
       with no rebuild and no `@AppStorage` read in any leaf body.
     - `RootView` sets `.environment(\.accent, …)` once, next to `\.pureBlack`.
3. **Where the accent applies.** Only these; `Palette.orange` stays for the brand marks.
   - The send button fill, state `.send`. This matches Claude: their send is the accent circle,
     their idle voice button is the dark ink circle.
     - `.send`: `Palette.accent` fill, `Palette.onAccent` arrow.
     - `.voice` (idle) and `.stop`: stay ink.
     - `.voiceActive`: `Palette.accent`.
     - `.unavailable`: unchanged.
   - The fill change between `.voice` → `.send` animates with the existing morph (one
     `Motion.feedback` crossfade of colour + symbol), never a snap.
   - The `FullScreenComposer` send glyph and its tint.
   - The terminal key bar's latched Ctrl/Alt tint (`PaseoTerminalKeyBar.swift:197`).
   - The running state in `ChatSubagents` (E3 owns that file; leave it. The lead will switch it
     after merge).
   - **Not** the crab, the loader, `StatusDot.attention` (semantic warning), diff colours or links.
4. **Settings → General → Appearance.**
   - Under the appearance picker, add an "Accent" row with a two-option segmented control:
     "Claude", "Paseo".
   - These three strings are approved new copy: "Accent", "Claude", "Paseo".
   - The switch animates the send button colour live (it's on screen behind Settings? No: Settings
     is a page. A live switch is enough).

## 3. Launch: one screen, not two, and no stray sidebar button

The user sees:
1. a splash with the greeting (`LaunchSkeleton` → `ClaudeHomeHero`);
2. then **another** greeting screen, with the sidebar button floating in the vertical middle of
   the left edge (screenshot 2);
3. then the real screen.

**Root cause of the floating button (found by the lead; confirm it):**
- `EmptyMain` (`ShellView.swift:546`) is a `VStack { ShellHeader; ZStack { ClaudeHomeHero … } }`
  with no `maxHeight: .infinity`.
- The stack hugs its content and is centred, so the header lands mid-screen.

**Build:**
1. `EmptyMain` fills the screen: the header is pinned top, the hero is centred in the remaining
   space, exactly like `LaunchSkeleton`.
2. **One continuous launch.**
   - The skeleton and every screen that can follow it (`EmptyMain`, the draft home in
     `DraftChatView`) draw the hero at the **same position and size**, with the same header
     geometry.
   - The hand-off is then invisible: no second greeting "arriving", no jump, no fade of identical
     content.
   - Measure where each one puts the hero; make them share one layout (a shared container
     view in `Shell/`, e.g. `HomeHeroLayout`) instead of three copies.
3. If the shell lands in `EmptyMain` only for a frame before it decides to show the draft, it
   must go straight to the final screen: decide before the first frame, or keep the skeleton up
   until the decision is made. Find which case it is and say so.
4. The skeleton's header shows the sidebar button in its **final** position, non-interactive, so
   the button doesn't appear late either.

## 4. Connect screen: one host must not scroll

`ConnectView.savedHostsList` (`ConnectView.swift:152`) is a `List` in a box of fixed height
`min(60 * (hosts + 1) + 8, 380)`. The rows are taller than 60 pt (title + subtitle), so with a
single host the box already scrolls, and its bottom edge cuts "Add host" (the user's screenshot).

**Build:**
- Replace the `List` with a non-scrolling card: a `VStack` of `ListRow`s with the existing
  separators, `Palette.panel` fill and `Radius` corner, sized by its content.
- Keep:
  - swipe-to-delete on a host: use a context menu "Remove" with the same action if the swipe was
    only possible because of `List`; say which you did;
  - the progress accessory;
  - the tap actions;
  - the accessibility identifiers.
- If many hosts don't fit, the **whole page** scrolls (one outer `ScrollView` with
  `.scrollBounceBehavior(.basedOnSize)`), never a box inside it.
- The card keeps its horizontal margins; the footer hint stays pinned at the bottom when
  everything fits.

## 5. The Files tab is pitch black in dark

`WorkspaceFilesView` draws no canvas, so the window's black shows through. The Agents and
Changes tabs paint `Palette.panel` (#1A1A19 dark).
- Give the Files tab (the tree, the empty state, the loading state, and the viewer's container
  where it is pushed inside the panel) the same canvas as its siblings.
- Then check every panel tab and every pushed page inside the panel in dark and pure black. List
  each, with the canvas it now uses. One canvas for the whole panel; no tab differs.

## 6. Turn the prompt jump rail off (keep the code)

The user is shelving the right-edge prompt rail for now.
- Add `static let promptRailEnabled = false` (in `ChatTurnRail.swift`, documented "U5 rail,
  shelved 2026-11-11 by the user; flip to re-enable").
- When it's false:
  - `outlineRail` isn't mounted;
  - `revealTurnRail()` does nothing;
  - no outline fetch is triggered for the rail alone.
- Delete nothing else.

## Proof

As in `_E-common.md`. Also:
- a table of every colour token you added or changed (light / dark / pure black);
- the §3 explanation of which screens the launch passes through, before and after;
- the §5 panel canvas list.
