# P1: polish audit (UI/UX), with small safe fixes

Branch `p1-polish-audit`. You are the design reviewer for this app. Output: an audit doc
`docs/research/12-polish-audit.md` plus a small number of low-risk fixes.

## The brief (fixed: read first, it overrides any general design advice)

- The visual direction is pinned: ClaudeUI (Anthropic's iOS app look: `Chat/ClaudeStyle.swift`
  palette, `ClaudeTypography` sans/serif/mono roles, `ClaudeMotion`, 0.5 pt dividers) with DSH
  Claude-style behavior (`docs/research/06-dsh-ux-spec.md`, `08-dsh-live-observation.md`). Cream,
  serif titles and the Claude accent are the brief, not a cliché to remove. Do not restyle,
  re-palette, change fonts, or invent a new aesthetic.
- Quality bar: Apple-level, invisible polish, no bloat. A screen should feel like it was always
  part of the Claude iOS app. Removing is often the fix.
- Wording: reuse upstream Paseo (`/home/paseo/dev/paseo-reference/packages/app/src/i18n/resources/en.ts`)
  and DSH wording; never replace it with your own. You may fix wording that is ours, generic or
  system-shaped (names things by implementation instead of by what the user understands).
- Project rules: `AGENTS.md`, `ARCHITECTURE.md`, shared UI rules at the top of
  `docs/tickets/M3-workspace-panel.md`.

## Your lens

Read `/tmp/polish-skill/SKILL.md` (Anthropic's frontend-design skill). It is for you only: don't
copy it into the repo or install it anywhere. Use the parts that apply to a native app with a
pinned style: restraint ("remove one accessory"), structure as information (dividers, labels,
numbering only when they encode something), motion only in answer to an action or as one
deliberate moment, empty and error states that direct ("what happened, how to fix it"), action
names that stay the same through a flow, sentence case, no filler, accessibility as a floor. Its
advice on picking a distinctive palette/typeface does not apply here (the brief pins them).
Add Apple HIG judgment: 44 pt hit targets, Dynamic Type behavior, VoiceOver labels/order, Reduce
Motion/Transparency, safe areas, keyboard avoidance, haptics used sparingly and consistently.

## What to do

1. Walk every screen in `Packages/PaseoUI/Sources/PaseoUI` (+ `App/Sources`) by reading the code:
   shell/sidebar, chat/turns/composer, workspace panel (files, changes, terminal, PR), sheets,
   settings, schedules, welcome/connect. For each finding: file:line, what's wrong, why it
   matters to the user, the fix, risk (low/medium/high), and whether it's consistency (same thing
   done two ways), hierarchy, motion, copy, state (empty/loading/error), accessibility, or bloat.
   Rank them. Note the best screens too, so the pattern can be copied.
2. Fix only **low-risk** findings yourself: inconsistent use of existing tokens (raw colors/sizes
   where a `ClaudePalette`/`ClaudeTypography` role exists), missing accessibility labels, missing
   Reduce Motion checks, a duplicated control, generic copy of our own, missing empty/error text,
   hit targets under 44 pt. Each fix small and local. Anything medium/high (layout changes,
   navigation changes, new components, removing a feature) goes in the doc as a proposal for the
   user, not into code.
3. Don't touch files under active tickets: the Voice settings pages and host settings voice code
   (M13), the usage sheet/overview and `ConnectView.swift`/App connect path (M14), and
   `PaseoKit` relay work (R16). Note findings there in the doc instead.

SwiftUI can't compile here: keep every change small, `swiftc -parse` every touched file, run
`Tools/api-audit` (README) and confirm no new real findings; PaseoCore must stay green (you
shouldn't need to touch it). No screenshots exist for you; reason from code and the specs. No
background tasks or subagents; don't end your turn while waiting. Commit "P1: polish audit"
(doc + fixes), don't push. Final message: the top 10 findings, what you fixed, what you propose
for the user, unsure-compile spots.
