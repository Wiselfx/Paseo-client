# H4: a clean splash, a usage footer that works, appearance that applies everywhere

Branch `h4-shell`, from `foundation`. Read `_H-common.md` first.

**Owns:**
- `Shell/LaunchSkeleton.swift`, `Shell/HomeHeroLayout.swift`, `Shell/ShellView.swift`
  (`EmptyMain` + the launch branch only)
- `App/Sources/RootView.swift`, `App/Sources/AppModel.swift` (launch + appearance only), and a new
  small file in `App/Sources/` if the appearance fix needs one
- `Sidebar/PaseoSidebar.swift` (usage section + its loading only),
  `Sidebar/ClaudeUsageReportsSheet.swift`, `Settings/SidebarPage.swift`
- `DesignSystem/ClaudeAppearance.swift`, `DesignSystem/Components/AppearancePicker.swift`,
  `Settings/GeneralPage.swift` (appearance row only)
- PaseoCore `HostUsageStore.swift` (+ new tests)

## 1. The splash shows the sidebar button, in the middle (user bug 5)

User: *"Splash screen still shows the sidebar button in the middle. It shouldn't show at all, let
alone be in the middle."* (E2 claimed to fix the "floating sidebar button" by pinning it with
`HomeHeroLayout`'s `.safeAreaBar(edge: .top)`; on device it is still mid-screen.)

**Behaviour to build:**
- The launch frame (`LaunchSkeleton`, used by `RootView` while a saved host connects and by
  `ShellView` while deciding chat vs draft) shows **the canvas and the hero only** — no sidebar
  button, no header chrome. It is a splash, not an inert copy of the UI.
- The hand-off to the real screen moves nothing: the hero sits exactly where it will sit on the
  draft/home screen. So the skeleton must still **reserve** the header's height (an empty spacer
  of the header's height, from a shared token — not a hidden button) and the footer strip.
- **Find out why the header was centred** in `RootView`'s launch branch (`RootView.swift:99`) —
  e.g. `safeAreaBar` placement relative to the `Group`/`.preferredColorScheme`/safe-area chain, or
  the container not filling the window. Fix the root cause in `HomeHeroLayout`, because `EmptyMain`
  uses the same layout *with* a real sidebar button and must have it pinned top-leading. State
  the cause with `file:line`.
- Check the very first frames too: iOS's static launch screen (`UILaunchScreen: {}` in
  `App/project.yml`) → `LaunchSkeleton` → shell. Background colour must match in light and dark so
  there's no flash (the static launch screen can take a background colour from an asset; if the
  fix needs `project.yml`, say so under "Found, not fixed" with the exact keys).

## 2. "Show usage in sidebar" does nothing (user bug 4)

**What's there:** the footer (`PaseoSidebar.swift:314`) renders only rows from
`session.hostUsage.reports`, which are loaded **once**, in the sidebar's `onAppear` (`:101`), and
only if the toggle was already on and `isSupported` was already true. The sidebar is mounted at
launch inside the drawer, so: turning the toggle on later never loads; `isSupported` is set on
`server_info`, which may arrive after `onAppear`; a failed load (usage disabled on host,
unsupported host, error) shows nothing at all; nothing ever refreshes.

**Behaviour to build:**
- Loading is driven by state, not by appear: `.task(id:)` keyed on (toggle on, `isSupported`,
  host identity), plus a throttled refresh when the drawer opens (≥ 60 s since the last success;
  use the drawer-open signal that exists — don't add per-frame drag observation).
- The footer always shows **something** when the toggle is on:
  - loading (first time): a quiet one-line placeholder, same height as a usage line, so the
    sidebar doesn't jump when data lands;
  - reports: one line per summary window, as now (tap → usage sheet);
  - failure/disabled/unsupported: one secondary line with the store's existing message, tappable
    to retry (or to the sheet, which explains);
  - no providers report usage: one line saying so (find existing copy first).
- Settings → Sidebar toggle copy and the footer agree. Turning it on shows the footer immediately
  without reopening anything.
- Live check: run `paseo-probe` against the local daemon (read-only usage request) and record
  whether this daemon supports `usageSources`/`providerUsageList` and what it returns, so we know
  what the user's host will show. Never touch Claude agents.
- `HostUsageStore`: add a `lastLoadedAt` and anything else the throttling needs, with tests.

## 3. Switching light/dark leaves Settings in the old mode (user bug 8)

**What's there:** the appearance is applied once with `.preferredColorScheme(colorScheme)` on
`RootView` (`RootView.swift:134`). Settings is presented as a sheet; a presented sheet's hosting
controller doesn't pick up a `preferredColorScheme` change from the presenter until it's
re-presented, and `preferredColorScheme(nil)` ("System") is a known case that never resets to the
system style until relaunch.

**Behaviour to build:**
- Changing Appearance (System / Light / Dark / and pure black if that's an option) applies **to
  every window and every presented sheet immediately**, including the Settings sheet you're in,
  with the system's own cross-fade — and "System" really returns to following the OS.
- Root-cause fix: drive the scene's windows' `overrideUserInterfaceStyle` from the setting (one
  small, well-named component in `App/`, observing the `@AppStorage` value; `.unspecified` for
  System). Keep `.preferredColorScheme` only if it's still needed for SwiftUI previews/parts that
  don't inherit the trait, and explain why.
- Check `Palette`: if any token resolves its colour from SwiftUI `colorScheme` at evaluation time
  instead of a dynamic `UIColor`, sheets and UIKit-hosted surfaces (SwiftTerm, WKWebView
  backgrounds, the drawers' shadow/card colours) won't follow. List any you find; fix the ones in
  your files, report the rest.
- Pure black: same immediacy.

## Acceptance

- Root cause per item with `file:line` (for item 1, why the button was centred).
- Walk: cold launch to a saved host, light and dark: what the user sees frame by frame.
- Walk: Settings → Appearance Light → Dark → System while Settings is open; the sidebar, the
  conversation behind, the terminal panel.
- Walk: toggle usage on with the sidebar closed, open it; host with usage disabled; reconnect.
