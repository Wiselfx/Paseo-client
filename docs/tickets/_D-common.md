# Shared rules for the D-round (device feedback, 2026-11-10)

The user ran the R-round build on an iPhone. Performance is "night and day", but a list of feel,
layout and correctness problems came back. Each D ticket fixes one cluster. The bar is the official
Claude iOS app and Apple's own apps: **invisible polish**. Nothing jumps, nothing is cut off,
nothing waits on a frame it doesn't need, every touch answers on touch-down, and motion is short,
eased and interruptible.

All of `_R-common.md` applies (files you own, wording, no new dependencies, Swift 6, compiling,
done, final message). Read it first, then `AGENTS.md` "UI rules". This file only adds to it.

## Additions

- **The look is OCU now.** `foundation` carries the OCU palette, motion, shape and radii (commits
  "OCU 1/4" to "4/4"). Use the tokens; never hard-code a value the tokens already have.
- **Taste calls are made in the ticket.** If you think a different choice would look or feel
  better, build what the ticket says and argue for the alternative under "Unsure". Don't swap it
  silently.
- **iOS 26 only.** The deployment target is iOS 26, so iOS 26 SwiftUI APIs need no availability
  checks (`safeAreaBar`, `scrollEdgeEffectStyle`, `glassEffect`, `onScrollGeometryChange`, …).
  List every Apple API you weren't 100 % sure of in your final message.
- **Copy:** approved new strings are listed in your ticket. Anything else is existing text or
  upstream `en.ts` verbatim.

## How the lead reviews

Your branch is reviewed twice. It goes back to you with demands if either pass fails.

1. **Performance.**
   - A view reads only what it draws (R-1).
   - No O(n) work in `body` or per scroll frame.
   - No `@State` written per frame unless something draws it.
   - No new per-row closures (R-2).
   - Nothing blocks the main actor: audio, files, image decoding and pasteboard reads of large
     data happen off main.
2. **Feel and taste.**
   - Every control has a pressed state.
   - Every state change is animated through `Motion.x.resolved(reduceMotion:)`, or deliberately
     not animated (a scroll pin, a keyboard frame).
   - No layout jump when content arrives.
   - Nothing clipped, nothing truncated where it could fit.
   - Hit areas are at least 44 pt.
   - VoiceOver labels are present.
   - It matches the ticket's described feel exactly.
