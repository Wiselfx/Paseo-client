# D5: haptics, soft and few

Branch `d5-haptics`, from `foundation` after D1–D4. Read `_D-common.md` first.

**Owns:**
- `DesignSystem/Haptics.swift`
- every `Haptics.` call site in `Packages/PaseoUI` (call lines only; no other edits in those files)

The user's verdict: haptics "need a bit of soft attention".

Today there are 212 `Haptics.selection()` calls, 34 `Haptics.success()` and 28 `Haptics.failure()`.
- `success()` is `UINotificationFeedbackGenerator(.success)`: the strong triple buzz Apple reserves
  for "a thing you waited for is done". We fire it on copy, rename, stage, discard….
- `selection()` fires on plain buttons that open a sheet or navigate. iOS itself never does that.

## 1. The vocabulary (`Haptics.swift`)

| Call | Generator | When |
|---|---|---|
| `selection()` | `UISelectionFeedbackGenerator` (unchanged) | A value ticks: toggles, segmented and picker changes, a disclosure opening or closing, a drag crossing a threshold (drawer snap, rail scrub), a long-press menu appearing |
| `light()` | `UIImpactFeedbackGenerator(.light)` at 0.6 | A small confirmation: copy to clipboard, a row action committed, an attachment added |
| `send()` | `UIImpactFeedbackGenerator(.soft)` at 0.9 | Sending a message: a soft, full thump, not a rigid click |
| `medium()` | unchanged | Queueing a message (the long press firing) |
| `settle()` | `UIImpactFeedbackGenerator(.soft)` at 0.45 | A turn finished in the conversation on screen, app active |
| `success()` | **`UIImpactFeedbackGenerator(.soft)` at 0.7** | An action you waited on completed (commit, push, PR created, branch switched, pairing done, project added) |
| `failure()` | `UINotificationFeedbackGenerator(.error)` (unchanged) | A user-initiated action failed. Never on a background or automatic failure |

`prepare()` also prepares the soft generator. Call `Haptics.prepare()` on touch-down of the send
button and of the drawer pan (where it isn't already called), so the first tap isn't late.

## 2. Call sites

Grep every call. For each, apply the table:
- **Remove `selection()`** from buttons whose only effect is opening a sheet, pushing a page,
  opening a menu, dismissing, or navigating (row taps in lists, "Settings", "History", header
  buttons, the back-to-end button, the panel's tab buttons).
  - **Keep it** for segmented and tab-like *value* switches (panel tabs count as value switches:
    keep), toggles, disclosure chevrons, pickers, and the terminal Ctrl latch.
- **Copy actions** use `light()`, not `success()`.
- **`success()` stays only** on completions of awaited work, as in the table. Everything else
  becomes `light()` or nothing.
- **`failure()`** stays only where the user directly triggered the failed action.
- **One haptic per intent.** If an action calls a helper that already plays one, remove the outer
  one. No haptic on something merely appearing (toasts, banners, rows arriving).

## Proof

- `swiftc -parse` on every touched file.
- Final message: counts per call before and after, and a list of every `success()` that remains,
  with one line each on why it stays.
