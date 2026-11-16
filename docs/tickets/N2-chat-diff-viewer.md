# N2: the "files changed" diff sheet shows the file, with upstream's diff options menu

Read `AGENTS.md`, then `docs/tickets/_L-common.md` (upstream-first rules apply in full), then this file.

## What the user sees today, and what they want
Under an assistant message a "files changed" card lists the files the turn edited
(`Conversation/Turn/TurnChangesCard.swift`). Tapping a file calls `richActions.openDiff` ->
`ChatController.openDiff(turnID:path:)` (`Conversation/Screen/ChatController.swift` ~line 680), which sets
`diffDocument`, and `Conversation/Screen/ChatSheets.swift` ~line 49 presents it in a sheet with
`ClaudeDiffView` (`Conversation/Turn/ClaudeToolDetail.swift` ~line 107). That view is a small box: its
scroll area has `.frame(maxHeight: 300)` and `.fixedSize(horizontal: false, vertical: true)`, so the sheet
shows a short box in the middle with a scroller inside, and long lines never wrap.
**Wanted:** the sheet shows the diff at full size, filling the sheet, so you can scroll and read the whole
file; and a three-dot menu in the sheet's top bar with the options upstream has: "Hide whitespace" /
"Show whitespace" and "Wrap long lines" / "Scroll long lines".

## Upstream (read first, copy it)
`/home/paseo/dev/paseo-upstream-ref/packages/app/src/git/diff-pane.tsx` (~lines 840-850: the options menu,
`hideWhitespace`, wrap vs scroll) and the copy in `packages/app/src/i18n/resources/en.ts` under
`workspace.git.diff`: `options: "Diff options"`, `hideWhitespace: "Hide whitespace"`,
`showWhitespace: "Show whitespace"`, `scrollLongLines: "Scroll long lines"`,
`wrapLongLines: "Wrap long lines"`. Use these strings **verbatim**. Cite `Upstream: path:line` in the commit.

## Reuse before writing (R-7)
Our workspace Changes screen already has these two options:
`Workspace/WorkspaceChangesDiffView.swift` lines ~31-32 use
`@AppStorage("paseo.diff.hideWhitespace")` and `@AppStorage("paseo.diff.wrapLongLines")`. Read that file
and see how it renders its options and applies them. Use **the same two `@AppStorage` keys** so one
preference governs both places, and the same menu wording and structure. Do not create new keys. Do not
copy a whole second diff renderer: only add what `ClaudeDiffView` needs.

## Owns (touch only these)
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Turn/ClaudeToolDetail.swift` (only `ClaudeDiffView` and
  `ClaudeDiffLine`)
- `Packages/PaseoUI/Sources/PaseoUI/Conversation/Screen/ChatSheets.swift` (only the `diffDocument` sheet)
- new files under `Packages/PaseoUI/Sources/PaseoUI/Conversation/Turn/` if you need one
- new test files only. Never edit an existing test.
`ClaudeDiffView` is also used inline by tool-call detail rows (`ClaudeToolDetail.swift` ~line 37). Those
inline uses **must keep today's compact look** (the 300 pt box). Add a parameter (for example
`fullHeight: Bool = false`) so only the sheet asks for the full-size version.

## Steps
1. Read `ClaudeDiffView`, `ClaudeDiffLine` and the `diffDocument` sheet in `ChatSheets.swift`. Read
   `SheetScaffold` (grep it) to see whether it supports toolbar items or a trailing menu; use its existing
   mechanism for the three-dot menu. If it has none, add the menu with a `.toolbar { ToolbarItem(placement: .topBarTrailing) ... }`
   only if the sheet is inside a `NavigationStack` there; otherwise report what is missing instead of
   building a new scaffold.
2. Add `fullHeight: Bool = false` to `ClaudeDiffView`. When true: drop `.frame(maxHeight: 300)` and
   `.fixedSize(...)` so the scroll view fills the available height (`.frame(maxHeight: .infinity)`), and
   hide the path header row if the sheet title already shows the file name (the sheet title is
   `document.fileName`; keep the full path visible as a single secondary line, that is fine).
3. Wrap: with "Wrap long lines" on, lines wrap to the sheet width (vertical scroll only,
   `.fixedSize(horizontal: false, vertical: true)` on the line text instead of `horizontal: true`); with
   "Scroll long lines" (default) behaviour stays as today (horizontal scroll). Read the preference with
   the shared `@AppStorage` key.
4. Whitespace: "Hide whitespace" drops lines whose only change is whitespace. Our diff lines come from
   `ClaudeDiffLine.parse(unifiedDiff:old:new:)`. Implement it the simplest correct way on the parsed lines
   (a removed line and the next added line that are equal after trimming and collapsing whitespace are both
   dropped); keep it O(lines), computed with the parse (in the `.task(id:)` key add the flag), never in
   `body`. If you cannot do it correctly in this view, ship the Wrap option only, and say so.
5. The menu: a three-dot (`ellipsis`) button with `accessibilityLabel("Diff options")` opening a `Menu`
   with two toggles whose titles flip exactly as upstream: "Hide whitespace"/"Show whitespace" and
   "Wrap long lines"/"Scroll long lines". 44 pt hit area. Use `Haptics.selection()` if the workspace diff
   menu does.
6. In `ChatSheets.swift` pass `fullHeight: true` for the sheet's `ClaudeDiffView`.

## Proof
`swiftc -parse` every edited file. `Tools/style-lint/style-lint.sh` on your files: no new hits. Commit as
`N2: chat diff sheet at full size with diff options`, body listing the upstream citations.

## Final message
What you did per step, every Apple API or token you were unsure of, what you could not do and why, and
"Found, not fixed".
