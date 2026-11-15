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

    static func tail(_ count: Int) -> String {
        buffer.withLock { Array($0.suffix(count)).joined(separator: "\n") }
    }
}

struct FocusDiagOverlay: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Text(FocusDiag.tail(22))
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(Color.red)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 400, alignment: .leading)
                .background(Color.white.opacity(0.85))
                .offset(y: -620)
                .allowsHitTesting(false)
        }
    }
}
