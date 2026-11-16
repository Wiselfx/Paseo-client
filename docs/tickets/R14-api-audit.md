# R14: audit PaseoUI → PaseoCore API usage (catch Xcode errors early)

Branch `r14-api-audit`. `swiftc -parse` can't see missing members; M7e shipped a UI that called a
store HostSession never had. Build a checker and fix what it finds.

1. Extract PaseoCore's public API: `swift build` then `swift symbolgraph-extract` (or
   `swift package dump-symbol-graph`) for PaseoProtocol, PaseoKit, PaseoStore → a list of public
   types, members, initializers with argument labels, and enum cases.
2. Scan `Packages/PaseoUI/Sources` and `App/Sources` for uses of those types: member accesses on
   known store types (`session.x`, `store.x`, `session.x.y(...)`), initializer calls with labels,
   enum cases (`.case`), and report every reference that doesn't exist or whose labels don't match.
   A pragmatic regex/tokenizer approach is fine; keep the script in `Tools/api-audit/` with a
   README line so it can be rerun before each merge.
3. Also report: PaseoUI-internal symbols referenced but defined nowhere (the R10 `sectionHeader`
   class), and duplicate top-level type names.
4. Fix the real findings with the smallest change on the UI side (or an additive PaseoCore change
   if the UI's intent is clearly right; then tests). List false positives you suppressed.

PaseoCore tests must stay green. Commit "R14: API audit", don't push. Final message: findings table
(file:line, symbol, fix), the rerun command, false-positive notes.
