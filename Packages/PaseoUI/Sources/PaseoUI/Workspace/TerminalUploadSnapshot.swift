#if canImport(UIKit)
import SwiftTerm
import SwiftUI
import UIKit

/// A virtual key bar shown above the keyboard while a terminal is focused: the keys the
/// iOS software keyboard can't produce — Esc, Tab, a sticky one-shot Ctrl, arrows, and the
/// shell punctuation `|`, `~`, `/`, `-` — plus a hide/show-keyboard button.
///
/// Wired to SwiftTerm's `TerminalView` as `inputAccessoryView` (the built-in accessory is
/// replaced). Arrow keys go through `TerminalView.sendKeyUp/Down/Left/Right`, which encode
/// for the app's cursor-key mode. Esc/Tab/punctuation are sent as raw bytes through
/// `TerminalsStore.sendInput`. Ctrl flips `TerminalView.controlModifier`, which SwiftTerm
/// clears after the next key automatically.
/// One-line snapshot of an in-flight T14 (`file.upload`) transfer, for the key bar's progress
/// row. `progress` is 0…1 bytes-sent; the daemon answers only after all bytes arrive.
struct TerminalUploadSnapshot: Equatable {
    let fileName: String
    let progress: Double
}
#endif
