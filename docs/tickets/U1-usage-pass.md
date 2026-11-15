# U1: plan usage, a proper pass against upstream

Read `AGENTS.md`, then `docs/tickets/_P-common.md` (upstream first, use the daemon's own channels, no invention, never push, one commit per part), then this file.

## What the owner sees
The sidebar's usage block at the bottom ("Claude · Session 21% · resets 3h", "Claude · Weekly 11% · resets 5d", two caption lines with tiny meters) is oddly
sized and its stats look wrong: the meter bars differ in width from row to row, the numbers shown do not match the accessibility label of the same row
(a row read "15 percent used" while 21% was drawn), the text is long and the reset text is ours, not upstream's. Make it behave and look the way upstream's
usage module does, using the host's own usage channel.

## Upstream (read these in full first)
Channel and wire: `packages/protocol/src/messages.ts` `provider.usage.list.request` / `.response` (lines ~1961, 6726-6790), feature gate
`providerUsageList` (~4023); windows have `id, label, shortLabel, summary, usedPct, remainingPct, resetsAt, runsOutAt, shortfallPct, tone`; balances and
details exist too; `UsageProblem` (expired / rejected / no_quota) is shown with the copy in `en.ts` `providerUsage` (~2223-2262).
App module: `packages/app/src/usage/` , especially `model.ts` (used vs remaining percent, `displayPercent`, stream/settle of reports), `queries.ts` (when it
polls: only while the sidebar item is on screen, the app visible and the setting on; `nextRefreshAt`), `pinned.ts` (which windows the sidebar shows:
`summary` windows until the user pins their own; `choosePinnedUsageLayout`), `sidebar-item.tsx` (ONE line: per source an icon, then per window a meter and
"31% 5h" (percent + `shortLabel`); it measures and picks the richest layout that fits, otherwise percents alone), `format.ts` (reset and relative-time wording),
`preferences.ts`, `tone.ts`, `window-bar.tsx`, `meter.tsx`, `card.tsx`, `usage-modal.tsx`, `reset-line.tsx`, `controls.tsx`, `options.tsx`.
Copy: `packages/app/src/i18n/resources/en.ts` `providerUsage` block, verbatim.

## Ours (read before changing)
Wire and store: `PaseoCore/Sources/PaseoProtocol/Usage.swift`, `PaseoStore/HostUsageStore.swift`, `UsageOverview.swift`.
UI: `PaseoUI/Sidebar/SidebarUsageFooter.swift`, `DesignSystem/UsageMeters.swift`, `Sidebar/ClaudeUsageReportsSheet.swift` and where the sidebar wires them
(`PaseoSidebar.swift`, `ShellView.swift`).

## Work
A. **Audit first, write findings as the first commit message body and in your final message:** list every difference between ours and upstream for (1) the
   request and gating (do we use `provider.usage.list.request` and the `providerUsageList` feature, stream per report, refresh single report, poll rules),
   (2) the numbers (used vs remaining, `usedPct` missing but `remainingPct` present, rounding, tone), (3) reset and relative-time wording (`format.ts`),
   (4) the sidebar line layout, (5) the usage sheet content (windows, balances, details, problems, refresh, pin, "Percentages Used/Remaining",
   "Summary in sidebar"). Cite `path:line` on both sides. Anything that is a real bug (wrong number, mismatched labels) goes first.
B. **Fix the numbers and the channel**: port `model.ts` / `format.ts` logic into Core (Linux-testable, new test files only), make the store follow upstream's
   request, refresh and polling rules, and make one source of truth for the percent shown, so the drawn text and the accessibility label can never differ.
C. **Sidebar line**: replace the two caption rows with upstream's single line: source icon, meter and "31% 5h" per summary window, picking the richest layout
   that fits and otherwise percents only. Meters have one fixed width and height (use `Space`/`Metrics` tokens), the same on every row. Tone colours as upstream
   (`tone.ts`), through `Palette` tokens. Tapping opens the usage sheet. Show nothing while no summary window has data (upstream: the footer's Usage icon
   already opens Usage).
D. **Usage sheet**: bring it to upstream's content and copy (verbatim `providerUsage` strings): per-source card, windows with meters and reset lines, balances,
   details, the three problem states, refresh and refresh all, pin/unpin windows, Percentages Used/Remaining, Summary in sidebar. Skip only what has no iPhone meaning, and say so.
   Persist pins and the used/remaining choice as upstream's `preferences.ts` does, in the app's existing preference style.
Do the parts in order; if C or D is too large for one pass, finish A, B and C completely and list D's remainder precisely.

## Owns
The usage files named above, `Sidebar/SidebarMetrics.swift` only for usage tokens, new Core files and tests for the ported logic. Not `HostSession.swift` or
`ConversationStore`. Keep the Claude/other provider naming coming from the host's `displayName`/source labels, never hard-coded.

## Done
`swift build --build-tests` and `swift test` in `Packages/PaseoCore` pass; `swiftc -parse` on every edited UI file; list what must be eyeballed on the simulator.
Commits: `U1.A audit`, `U1.B usage numbers and channel`, `U1.C sidebar line`, `U1.D usage sheet`.
