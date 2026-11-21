#if canImport(UIKit)
import Foundation

/// One retained emulator. `generation` only changes when the user reattaches after the process
/// ended; a tab switch keeps the same identity, so nothing is rebuilt or replayed.
struct MountedTerminal: Identifiable {
    let terminalId: String
    let generation: Int
    var id: String { "\(terminalId)#\(generation)" }
}
#endif
