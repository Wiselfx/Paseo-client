# R11: split ClaudeChatView into files (pure move)

Branch `r11-split-chat`. Same method as your R10: **no behavior changes**, only moving code into
files and widening `private` → internal where a cross-file extension needs it. You may edit
`Chat/ClaudeChatView.swift` and create files under a new `Sources/PaseoUI/Conversation/` folder.
Nothing else (if another file must change to compile, say so instead).

Target shape (adjust to the code's real seams; aim for files under ~400 lines):
- `ClaudeChatView.swift`: the root view (stored props, body, sheets/dialog wiring)
- header + title menu + find bar wiring; transcript list + turn/segment views + scroll follow /
  anchor logic; composer (toolbar, menus: slash/mention, queue, attachments, dictation, Fast chip,
  context ring, send/steer/queue logic); permission/question cards if they live here; toasts.

Prove it like R10: `swiftc -parse` on every new/changed file, a line-multiset diff between the
original and the reassembled pieces showing only visibility changes and moves, and grep that every
symbol referenced across files is defined exactly once (R10 found a missing `sectionHeader`: look
for similar missing or duplicated helpers and report them; restore missing ones verbatim from git
history only). PaseoCore untouched. Commit "R11: split ClaudeChatView", don't push. Final message:
file map with line counts, access changes, anything found missing or odd.
