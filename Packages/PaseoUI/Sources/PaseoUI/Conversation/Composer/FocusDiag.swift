import Foundation
import SwiftUI
import os

/// TEMPORARY diagnostics for the composer-focus bug. Never merged.
/// Lines are kept in memory and shown as hidden accessibility text (`diag.log`), because the
/// simulator's unified log is not readable from the gate.
enum FocusDiag {
    private static let log = Logger(subsystem: "com.wiselfx.paseoclient", category: "focus")
    private static let buffer = OSAllocatedUnfairLock(initialState: [String]())

    static func note(_ message: String) {
        let stamp = String(format: "%.2f", ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 1000))
        let line = "\(stamp) \(message)"
        log.notice("\(line, privacy: .public)")
        buffer.withLock { lines in
            lines.append(line)
            if lines.count > 40 { lines.removeFirst(lines.count - 40) }
        }
    }

    static func dump() -> String {
        buffer.withLock { $0.joined(separator: " // ") }
    }
}

struct FocusDiagOverlay: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let text = FocusDiag.dump()
            Color.clear
                .frame(width: 24, height: 24)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
                .accessibilityIdentifier("diag.log")
        }
    }
}
