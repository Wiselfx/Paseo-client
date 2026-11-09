# R10: split PaseoSidebar and ClaudeSchedulesView (no behaviour change)

Branch `r10-split`. Pure refactor so Xcode's type-checker and future tickets stay fast: move code,
don't change it. Files: `Chat/PaseoSidebar.swift` (~1400 lines) and `Chat/ClaudeSchedulesView.swift`
(~1600 lines) → several files each, in a new folder `Sidebar/` and `Schedules/` under
`Sources/PaseoUI/` (or alongside, your call; one type or one cohesive group per file, e.g.
`PaseoSidebar.swift` (root view), `SidebarWorkspaceRow.swift`, `SidebarProjectGroup.swift`,
`SidebarDisplayOptions.swift`, `ClaudeNewWorkspaceSheet.swift`, `SidebarToasts.swift`).

Rules: identical behaviour and public API; `private` members that now cross files become
`fileprivate`→`internal` only as needed (prefer extensions of the root view in separate files so
`@State` stays private-ish: use `extension PaseoSidebar` files where that keeps things readable);
no renames of public types; no formatting churn inside moved code. Every resulting file passes
`swiftc -parse`; `rg` for each moved type proves one definition. Don't touch `ClaudeChatView.swift`
or `PaseoSettingsView.swift` (other tickets are editing them).

Commit "R10: split sidebar and schedules files", don't push. Final message: new file map,
access-level changes made, anything you weren't sure moved cleanly.
