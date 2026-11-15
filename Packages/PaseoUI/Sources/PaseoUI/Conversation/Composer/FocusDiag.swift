import Foundation
import SwiftUI
import os
import UIKit

/// TEMPORARY diagnostics for the composer-focus bug. Never merged.
/// Lines are kept in memory and shown as hidden accessibility text (`diag.log`), because the
/// simulator's unified log is not readable from the gate.
enum FocusDiag {
    nonisolated(unsafe) private static var lastSummary = ""
    /// Live composer text views, weakly held.
    nonisolated(unsafe) static let registry = NSHashTable<AnyObject>.weakObjects()

    /// Logs only when the number of live / windowed composers changes.
    static func noteCount(_ context: String) {
        let views = registry.allObjects.compactMap { $0 as? UIView }
        let inWindow = views.filter { $0.window != nil }.count
        let summary = "live=\(views.count) inWindow=\(inWindow)"
        guard summary != lastSummary else { return }
        lastSummary = summary
        note("COUNT \(summary) after \(context)")
    }

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
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let _ = FocusDiag.noteCount("tick")
            VStack(alignment: .leading, spacing: 0) {
                Text("DIAG alive \(Int(context.date.timeIntervalSince1970) % 1000)")
                Text(FocusDiag.tail(20))
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.leading)
            .padding(2)
            .frame(width: 380, alignment: .leading)
            .background(Color.yellow.opacity(0.9))
            .allowsHitTesting(false)
        }
    }
}
