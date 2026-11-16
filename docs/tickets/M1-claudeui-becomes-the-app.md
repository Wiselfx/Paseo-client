# M1: ClaudeUI becomes the app's UI package

The user decided the app's UI is built on ClaudeUI (the Claude iOS recreation in
`Packages/ClaudeUI`), edited in place. This ticket restructures and deletes. It adds no features.
After it, the app must still build in Xcode and behave as it does today.

Read first: `AGENTS.md`, `ARCHITECTURE.md`, and `docs/research/07-claudeui-adoption-map.md`
(the map: §1 inventory, §3 decision table, §4 deletion safety and order). The map is your spec.

## Steps

1. **Move the current generic UI aside.** `Packages/PaseoUI` (DesignSystem, HostsFeature,
   AgentsFeature, ConversationFeature) is the temporary UI the app runs today. Its contents move
   into the ClaudeUI package as a folder `Sources/ClaudeUI/Paseo/` (one subfolder per old target).
   Drop their separate targets; they become part of one module. Fix imports accordingly
   (`import DesignSystem` etc. disappear). Delete DesignSystem pieces that duplicate ClaudeUI's
   (Markdown wrapper stays as long as something uses it). Nothing is restyled in this ticket.
2. **Rename the package.** `git mv Packages/ClaudeUI Packages/PaseoUI` (after step 1 freed the
   name). Package name, product and module become `PaseoUI`. Add the dependency on PaseoCore's
   `PaseoStore` product (`.package(path: "../PaseoCore")`). Type names (`ClaudeSessionView`,
   `ClaudePalette`, …) stay for now; renaming them is a later, mechanical ticket.
3. **Delete every DELETE row** of the decision table (§3), in the order of §4.3, using §4.1/§4.2
   to fix every reference in kept files. Also delete the `ClaudeWidgets` target and its sources,
   `Examples/` (the old demo app and its snapshot/UI tests; our app is `App/`), the old package's
   `docs/fidelity` and `docs/features` pages for deleted features, and unit tests in `Tests/` that
   cover deleted code. Keep tests for kept code.
4. **ADAPT rows are not touched** in this ticket. They keep their current fake/demo behavior.
5. **App.** Update `App/project.yml` to the renamed package and its single `PaseoUI` product,
   regenerate the project (`cd App && USER=paseo xcodegen generate`), and fix `App/Sources` imports.
   The app's screens stay the ones it uses today (connect, agent list, conversation).
6. Update `.github/dependabot.yml` if it points at removed paths.

## Verification (no Xcode here)

SwiftUI can't be compiled on this machine, so be rigorous:
- Before deleting a file, `rg` for every type it declares across `Packages/` and `App/`, and
  resolve each reference.
- After all edits, `rg` for every type name you deleted; there must be no hits outside comments.
- `swiftc -parse` every remaining Swift file in `Packages/PaseoUI` and `App/Sources` (catches
  syntax errors).
- `PaseoCore` must still pass `swift test` (you shouldn't touch it).
- List, in your final message, every place you're less than certain compiles, with file:line.

Commit as "M1: ClaudeUI becomes PaseoUI" (several commits are fine). Don't push. Final message:
what moved, what was deleted (file count and list of features), what remains, the uncertain spots,
and the exact steps the user should take in Xcode (e.g. "File → Packages → Reset Package Caches"
if needed).
