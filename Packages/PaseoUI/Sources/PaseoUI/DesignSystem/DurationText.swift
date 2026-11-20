#if canImport(UIKit)
import SwiftUI

/// "Completed in 4s", "Worked for 2m 10s".
enum DurationText {
    static func completed(_ seconds: TimeInterval) -> String {
        "Completed in \(short(seconds))"
    }

    static func short(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60, rest = total % 60
        if minutes < 60 { return rest == 0 ? "\(minutes)m" : "\(minutes)m \(rest)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
#endif
