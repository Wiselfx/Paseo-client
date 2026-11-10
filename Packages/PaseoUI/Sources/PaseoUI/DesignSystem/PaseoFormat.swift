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

    /// One reused formatter per fraction-digit count. Building and configuring a `NumberFormatter`
    /// costs ~21 µs against ~0.7 µs to reuse one, and rows format several numbers per evaluation
    /// (diff stats, counts), so it was showing up in list scrolling (P3). Display-only: every
    /// caller is a view body on the main actor.
    private static let zeroDigits = decimalFormatter(maximumFractionDigits: 0)
    private static let oneDigit = decimalFormatter(maximumFractionDigits: 1)
    private static let twoDigits = decimalFormatter(maximumFractionDigits: 2)

    private static func formatter(_ maximumFractionDigits: Int) -> NumberFormatter {
        switch maximumFractionDigits {
        case 0: zeroDigits
        case 1: oneDigit
        default: twoDigits
        }
    }

    /// `119,900`, `0`, `-1,234`.
    static func integer(_ value: Int) -> String {
        formatter(0).string(from: NSNumber(value: value)) ?? String(value)
    }

    /// `999`, `1.2k`, `3.4M`, `1.2B`. For tight spots like the context ring.
    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude < 1000 {
            return formatter(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2)
                .string(from: NSNumber(value: value)) ?? String(value)
        }
        let scaled: (Double, String)
        switch magnitude {
        case 1_000..<1_000_000: scaled = (value / 1_000, "k")
        case 1_000_000..<1_000_000_000: scaled = (value / 1_000_000, "M")
        default: scaled = (value / 1_000_000_000, "B")
        }
        let text = formatter(1)
            .string(from: NSNumber(value: scaled.0)) ?? String(scaled.0)
        return text + scaled.1
    }

    /// Token and line counts in the tightest form the context rows use: `950`, `1k`, `1.3k`,
    /// `12k`, `134k`, `1.2M`. One decimal below ten of each unit, none above; never a trailing
    /// `.0`. Integer arithmetic throughout, so `1_250` is `1.3k` and not the even-rounding `1.2k`.
    static func compactCount(_ value: Int) -> String {
        let magnitude = value.magnitude
        let text: String
        if magnitude < 1_000 {
            text = String(magnitude)
        } else if magnitude < 1_000_000 {
            text = compactScale(magnitude, unit: 1_000) + "k"
        } else if magnitude < 1_000_000_000 {
            text = compactScale(magnitude, unit: 1_000_000) + "M"
        } else {
            text = compactScale(magnitude, unit: 1_000_000_000) + "B"
        }
        return value < 0 ? "-" + text : text
    }

    /// `1`, `1.3`, `12`, `134`: one decimal (half up) below ten units, whole units above it.
    private static func compactScale(_ magnitude: UInt, unit: UInt) -> String {
        if magnitude / unit >= 10 {
            return String((magnitude + unit / 2) / unit)
        }
        let tenths = (magnitude * 10 + unit / 2) / unit
        let fraction = tenths % 10
        return fraction == 0 ? String(tenths / 10) : "\(tenths / 10).\(fraction)"
    }

    /// `2m ago`, `yesterday`: one static formatter, the outputs the rows used to build per call.
    /// Main-actor only, like the display callers it serves: `RelativeDateTimeFormatter` is not
    /// Sendable.
    @MainActor private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = displayLocale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    @MainActor static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Times and dates follow the device locale (UX-SPEC §0.2), unlike the grouping above.
    @MainActor private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    @MainActor private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    @MainActor static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    @MainActor static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
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
        let text = formatter(digits).string(from: NSNumber(value: scaled))
            ?? String(Int(scaled.rounded()))
        return text + " " + units[unit]
    }
}
#endif
