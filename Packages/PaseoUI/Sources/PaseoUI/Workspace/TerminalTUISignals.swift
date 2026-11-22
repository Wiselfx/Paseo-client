#if canImport(UIKit)
import QuartzCore

/// Whether a full-screen TUI is driving the terminal, read from the output stream itself.
///
/// Two signals, both DEC private modes (`ESC [ ? n h` / `ESC [ ? n l`):
/// - **Synchronized output (2026).** Claude Code, pi and other Ink-style TUIs wrap every frame in
///   it, so a frame seen in the last `syncHold` seconds means one is repainting right now.
/// - **Alternate screen (1049, 1047, 47).** vim, htop, less: on until they switch it off.
///
/// While either holds, the Metal renderer rebuilds the whole screen per frame in one buffer
/// (`perFrameAggregated`), which suits repaints that touch most rows; a shell keeps the per-row
/// cache. A sequence split across two chunks is missed once, which is harmless: TUIs send 2026
/// with every frame.
struct TerminalTUISignals {
    private(set) var alternateScreen = false
    private var lastSyncFrameAt: CFTimeInterval = -.infinity

    /// How long one synchronized frame keeps the TUI mode on.
    static let syncHold: CFTimeInterval = 2

    func isTUI(at now: CFTimeInterval) -> Bool {
        alternateScreen || now - lastSyncFrameAt < Self.syncHold
    }

    mutating func reset() {
        alternateScreen = false
        lastSyncFrameAt = -.infinity
    }

    mutating func scan<Bytes: Collection>(_ bytes: Bytes, at now: CFTimeInterval)
    where Bytes.Element == UInt8 {
        let scanned: Void? = bytes.withContiguousStorageIfAvailable { scan($0, at: now) }
        if scanned == nil {
            Array(bytes).withUnsafeBufferPointer { scan($0, at: now) }
        }
    }

    private mutating func scan(_ buffer: UnsafeBufferPointer<UInt8>, at now: CFTimeInterval) {
        let count = buffer.count
        var index = 0
        while index + 3 < count {
            // ESC [ ?
            guard buffer[index] == 0x1B, buffer[index + 1] == 0x5B, buffer[index + 2] == 0x3F else {
                index += 1
                continue
            }
            var cursor = index + 3
            var value = 0
            var hasSync = false
            var hasAlternate = false
            var final: UInt8 = 0
            while cursor < count {
                let byte = buffer[cursor]
                if byte >= 0x30, byte <= 0x39 {
                    value = min(value * 10 + Int(byte - 0x30), 100_000)
                } else if byte == 0x3B || byte == 0x68 || byte == 0x6C {
                    // `;` separates modes; `h` sets and `l` resets them.
                    if value == 2026 { hasSync = true }
                    if value == 1049 || value == 1047 || value == 47 { hasAlternate = true }
                    value = 0
                    if byte != 0x3B {
                        final = byte
                        break
                    }
                } else {
                    break
                }
                cursor += 1
            }
            if final == 0x68 {
                if hasSync { lastSyncFrameAt = now }
                if hasAlternate { alternateScreen = true }
            } else if final == 0x6C, hasAlternate {
                alternateScreen = false
            }
            index = max(cursor, index + 1)
        }
    }
}
#endif
