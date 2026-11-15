import Foundation
import SwiftUI
import UIKit
import os

/// TEMPORARY diagnostics: who hosts the composer. Never merged.
enum FocusDiag {
    nonisolated(unsafe) private static var lastSummary = ""
    nonisolated(unsafe) static let registry = NSHashTable<AnyObject>.weakObjects()
    private static let buffer = OSAllocatedUnfairLock(initialState: [String]())

    static func note(_ message: String) {
        let stamp = String(format: "%.1f", ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 1000))
        buffer.withLock { lines in
            lines.append("\(stamp) \(message)")
            if lines.count > 60 { lines.removeFirst(lines.count - 60) }
        }
    }

    static func tail(_ count: Int) -> String {
        buffer.withLock { Array($0.suffix(count)).joined(separator: "\n") }
    }

    /// Short chain of superview class names, innermost first.
    private static func chain(_ view: UIView) -> String {
        var names: [String] = []
        var current: UIView? = view.superview
        while let v = current, names.count < 12 {
            var name = NSStringFromClass(type(of: v))
            if let range = name.range(of: "SwiftUI.") { name = String(name[range.upperBound...]) }
            names.append(String(name.prefix(22)))
            current = v.superview
        }
        return names.joined(separator: "<")
    }

    static func noteCount(_ context: String) {
        let views = registry.allObjects.compactMap { $0 as? UIView }
        let summary = views.map { "\($0.window != nil ? "W" : "-")\(Int($0.frame.origin.y))" }.joined(separator: ",")
        guard summary != lastSummary else { return }
        lastSummary = summary
        note("COUNT live=\(views.count) [\(summary)] \(context)")
        for (index, view) in views.enumerated() {
            note("  #\(index) win=\(view.window != nil) hidden=\(view.isHidden) frame=\(Int(view.frame.width))x\(Int(view.frame.height))")
            note("  #\(index) \(chain(view))")
        }
    }
}

struct FocusDiagOverlay: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let _ = FocusDiag.noteCount("tick")
            Text(FocusDiag.tail(34))
                .font(.system(size: 6.5, design: .monospaced))
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.leading)
                .padding(2)
                .frame(width: 400, alignment: .leading)
                .background(Color.yellow.opacity(0.92))
                .allowsHitTesting(false)
        }
    }
}
