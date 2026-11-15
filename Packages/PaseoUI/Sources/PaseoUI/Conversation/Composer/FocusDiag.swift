import os

/// TEMPORARY diagnostics for the composer-focus bug. Never merged.
enum FocusDiag {
    private static let log = Logger(subsystem: "com.wiselfx.paseoclient", category: "focus")
    static func note(_ message: String) {
        log.notice("\(message, privacy: .public)")
    }
}
