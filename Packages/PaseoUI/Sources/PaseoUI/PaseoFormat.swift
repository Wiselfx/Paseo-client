#if canImport(UIKit)
import Foundation

/// The one place display numbers are formatted (UX-SPEC §0.2).
/// English UI: grouping always uses a comma, regardless of device region.
/// Never call `.formatted()` or `NumberFormatter` for display elsewhere.
enum PaseoFormat {
    private static var displayLocale: Locale { Locale(identifier: "en_US") }

    private static func decimalFormatter(maximumFractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = displayLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter
    }

    /// `119,900`, `0`, `-1,234`.
    static func integer(_ value: Int) -> String {
        decimalFormatter(maximumFractionDigits: 0).string(from: NSNumber(value: value))
            ?? String(value)
    }

    /// `999`, `1.2k`, `3.4M`, `1.2B`. For tight spots like the context ring.
    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude < 1000 {
            return decimalFormatter(maximumFractionDigits: value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2)
                .string(from: NSNumber(value: value)) ?? String(value)
        }
        let scaled: (Double, String)
        switch magnitude {
        case 1_000..<1_000_000: scaled = (value / 1_000, "k")
        case 1_000_000..<1_000_000_000: scaled = (value / 1_000_000, "M")
        default: scaled = (value / 1_000_000_000, "B")
        }
        let text = decimalFormatter(maximumFractionDigits: 1)
            .string(from: NSNumber(value: scaled.0)) ?? String(scaled.0)
        return text + scaled.1
    }

    /// `42%` for a 0–100 percent value, rounded to a whole percent.
    static func percent(_ value: Double) -> String {
        integer(Int(value.rounded())) + "%"
    }

    /// File sizes from a byte count: `842 bytes`, `12 KB`, `1.2 MB` (SI, like Finder).
    /// Hand-rolled because `ByteCountFormatter` always follows the device region (no `locale`),
    /// which would bring back `1'234 KB`.
    static func bytes(_ value: Int) -> String {
        let count = max(0, value)
        if count < 1_000 { return count == 1 ? "1 byte" : "\(count) bytes" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var scaled = Double(count) / 1_000
        var unit = 0
        while scaled >= 999.95, unit < units.count - 1 {
            scaled /= 1_000
            unit += 1
        }
        let digits = scaled < 10 && unit > 0 ? 1 : 0
        let text = decimalFormatter(maximumFractionDigits: digits).string(from: NSNumber(value: scaled))
            ?? String(Int(scaled.rounded()))
        return text + " " + units[unit]
    }
}
#endif
