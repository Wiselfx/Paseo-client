import Foundation
import PaseoProtocol

/// The wording and numbers the usage surfaces print.
///
/// Port of upstream `packages/app/src/usage/format.ts`; the strings are upstream's own
/// `providerUsage` copy from `packages/app/src/i18n/resources/en.ts:2223-2292`, verbatim, because
/// this app is English-only and the words are not ours to invent (R-7). One function per string,
/// so the sidebar and the sheet cannot drift.

public enum UsageFormat {
    // MARK: - Copy (Upstream: packages/app/src/i18n/resources/en.ts:2223-2292)

    private enum Copy {
        // `providerUsage.values` (en.ts:2261-2263).
        static let used = "used"
        static let left = "left"

        // `providerUsage.duration` (en.ts:2274-2279).
        static func days(_ value: String) -> String { "\(value)d" }
        static func hours(_ value: String) -> String { "\(value)h" }
        static func minutes(_ value: String) -> String { "\(value)m" }
        static func pair(_ first: String, _ second: String) -> String { "\(first) \(second)" }

        // `providerUsage.timing` (en.ts:2281-2292).
        static let resetTimePassed = "Reset time passed"
        static let resettingNow = "resetting now"
        static func resetsIn(_ duration: String) -> String { "resets in \(duration)" }
        static func resetsAtWeekday(_ weekday: String, _ time: String) -> String {
            "\(weekday) \(time)"
        }
        static func resetsAtDate(_ date: String, _ time: String) -> String { "\(date), \(time)" }
        static let runsOutNow = "runs out now"
        static func runsOutIn(_ duration: String) -> String { "runs out in \(duration)" }
        static let justNow = "just now"
        static func daysAgo(_ value: String) -> String { "\(value)d ago" }
        static func hoursAgo(_ value: String) -> String { "\(value)h ago" }
        static func minutesAgo(_ value: String) -> String { "\(value)m ago" }
        static func updated(_ relativeTime: String) -> String { "Updated \(relativeTime)" }
        static func lastUpdated(_ relativeTime: String) -> String {
            "Last updated \(relativeTime)"
        }
        static let noSuccessfulUpdate = "No successful update"

        // `providerUsage` problem sentence pieces (en.ts:2239-2243).
        static func runToRefresh(_ command: String) -> String { "Run \(command) to refresh it." }
        static let signInAgain = "Sign in again."
        static func loginRejected(_ status: Int, _ remedy: String) -> String {
            "Login rejected (HTTP \(status)). \(remedy)"
        }
        static func loginExpired(_ relativeTime: String, _ remedy: String) -> String {
            "Login expired \(relativeTime). \(remedy)"
        }

        /// The em dash upstream prints where a figure cannot be read (window-bar.tsx:60,
        /// balance-bar.tsx:35).
        static let unknownValue = "—"
    }

    // MARK: - Percent (format.ts:29-52)

    /// 0…100. Upstream `clampPct` (format.ts:29-31).
    public static func clampPct(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, min(100, value))
    }

    /// `21%`: clamped, no fraction digits (format.ts:33-39).
    public static func percent(_ value: Double) -> String {
        "\(Int(clampPct(value).rounded()))%"
    }

    /// The percent with its meaning: "21% used" / "79% left" (format.ts:41-52).
    public static func displayPercent(_ value: Double, as displayAs: UsageDisplayAs) -> String {
        let text = percent(value)
        return displayAs == .used ? "\(text) \(Copy.used)" : "\(text) \(Copy.left)"
    }

    // MARK: - Reset and relative time (format.ts:54-182)

    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * minute
    private static let day: TimeInterval = 24 * hour

    /// A countdown's parts, or `.now` once it has passed.
    private enum RelativeDuration {
        case now
        case remaining([(unit: Unit, count: Int)])

        enum Unit { case days, hours, minutes }
    }

    /// Two units, floored, so a countdown keeps moving: "2d 23h", "4h 59m", "37m"
    /// (format.ts:70-86).
    private static func relativeDuration(_ iso: String, now: Date) -> RelativeDuration? {
        guard let target = PaseoDate.parse(iso) else { return nil }
        let diff = target.timeIntervalSince(now)
        guard diff.isFinite else { return nil }
        if diff <= 0 { return .now }
        let days = Int((diff / day).rounded(.down))
        let hours = Int((diff.truncatingRemainder(dividingBy: day) / hour).rounded(.down))
        let minutes = Int((diff.truncatingRemainder(dividingBy: hour) / minute).rounded(.down))
        if days > 0 {
            return .remaining(hours > 0 ? [(.days, days), (.hours, hours)] : [(.days, days)])
        }
        if hours > 0 {
            let parts: [(unit: RelativeDuration.Unit, count: Int)] =
                minutes > 0 ? [(.hours, hours), (.minutes, minutes)] : [(.hours, hours)]
            return .remaining(parts)
        }
        return .remaining([(.minutes, minutes)])
    }

    /// The major unit, plus the minor one unless it is zero (format.ts:88-101).
    private static func durationText(_ parts: [(unit: RelativeDuration.Unit, count: Int)]) -> String?
    {
        let words = parts.map { part -> String in
            let count = countText(part.count)
            switch part.unit {
            case .days: return Copy.days(count)
            case .hours: return Copy.hours(count)
            case .minutes: return Copy.minutes(count)
            }
        }
        guard let first = words.first else { return nil }
        if words.count > 1 { return Copy.pair(first, words[1]) }
        return first
    }

    /// When a window resets, as a countdown: "resets in 4h 59m" / "resetting now".
    /// A retained report has already reset, so it says so instead (format.ts:103-115).
    public static func resetLabel(
        _ iso: String?, retained: Bool = false, now: Date = .now
    ) -> String? {
        guard let iso, let duration = relativeDuration(iso, now: now) else { return nil }
        switch duration {
        case .now:
            return retained ? Copy.resetTimePassed : Copy.resettingNow
        case .remaining(let parts):
            guard let text = durationText(parts) else { return nil }
            return Copy.resetsIn(text)
        }
    }

    /// The exact clock time a window resets: "3:00 PM" within a day, "Fri 3:00 PM" within a week,
    /// "Oct 31, 3:00 PM" after that, and nothing for a time that has passed
    /// (format.ts:117-140). Names follow the app language (English); the clock follows the device.
    public static func resetTime(
        _ iso: String?, now: Date = .now, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String? {
        guard let iso, let target = PaseoDate.parse(iso) else { return nil }
        let diff = target.timeIntervalSince(now)
        guard diff.isFinite, diff > 0 else { return nil }
        let time = timeOfDay(target, locale: locale, timeZone: timeZone)
        if diff < day { return time }
        if diff < 7 * day {
            return Copy.resetsAtWeekday(weekday(target, timeZone: timeZone), time)
        }
        return Copy.resetsAtDate(dayAndMonth(target, timeZone: timeZone), time)
    }

    /// A quota that will not last: "runs out in 2h 5m" / "runs out now" (format.ts:142-152).
    public static func runsOutLabel(_ iso: String?, now: Date = .now) -> String? {
        guard let iso, let duration = relativeDuration(iso, now: now) else { return nil }
        switch duration {
        case .now: return Copy.runsOutNow
        case .remaining(let parts):
            guard let text = durationText(parts) else { return nil }
            return Copy.runsOutIn(text)
        }
    }

    /// How long ago a report was fetched: "just now", "37m ago", "5h ago", "3d ago"
    /// (format.ts:154-182).
    public static func ago(_ iso: String?, now: Date = .now) -> String? {
        guard let iso, let date = PaseoDate.parse(iso) else { return nil }
        let diff = now.timeIntervalSince(date)
        guard diff.isFinite else { return nil }
        if diff < minute { return Copy.justNow }
        let minutes = Int((diff / minute).rounded(.down))
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 { return Copy.daysAgo(countText(days)) }
        if hours > 0 { return Copy.hoursAgo(countText(hours)) }
        return Copy.minutesAgo(countText(minutes))
    }

    /// The card's freshness line: "Updated 5m ago" for a live report, "Last updated 5m ago" over
    /// retained data, and "No successful update" when the host never got one
    /// (Upstream: packages/app/src/usage/card.tsx:255-280).
    public static func freshness(_ successfulAt: String?, retained: Bool, now: Date = .now)
        -> String
    {
        guard let relative = ago(successfulAt, now: now) else { return Copy.noSuccessfulUpdate }
        return retained ? Copy.lastUpdated(relative) : Copy.updated(relative)
    }

    // MARK: - Amounts (format.ts:184-197)

    /// A balance amount as English writes it: "$1,234.50", "12.3K".
    public static func amount(_ value: Double, unit: ProviderUsageBalance.Unit) -> String {
        switch unit {
        case .usd:
            return decimal(value, minimumFractionDigits: 2, maximumFractionDigits: 2, currency: true)
        case .tokens:
            return compact(value)
        case .credits, .requests, .unknown:
            return decimal(value, minimumFractionDigits: 0, maximumFractionDigits: 2)
        }
    }

    /// Intl's compact notation, one fraction digit (format.ts:189-193).
    private static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        let divisor: Double
        let suffix: String
        switch magnitude {
        case 1_000..<1_000_000: (divisor, suffix) = (1_000, "K")
        case 1_000_000..<1_000_000_000: (divisor, suffix) = (1_000_000, "M")
        case 1_000_000_000..<1e12: (divisor, suffix) = (1_000_000_000, "B")
        case 1e12...: (divisor, suffix) = (1e12, "T")
        default: (divisor, suffix) = (1, "")
        }
        return decimal(
            value / divisor, minimumFractionDigits: 0, maximumFractionDigits: 1, suffix: suffix)
    }

    private static let displayLocale = Locale(identifier: "en_US")

    private static func decimal(
        _ value: Double, minimumFractionDigits: Int, maximumFractionDigits: Int,
        suffix: String = "", currency: Bool = false
    ) -> String {
        let fractionDigits = minimumFractionDigits...maximumFractionDigits
        if currency {
            return value.formatted(
                .currency(code: "USD").precision(.fractionLength(fractionDigits))
                    .locale(displayLocale))
        }
        return value.formatted(
            .number.precision(.fractionLength(fractionDigits)).locale(displayLocale)) + suffix
    }

    // MARK: - Window and balance labels (format.ts:7-27)

    /// Upstream's own names for the windows and balances it knows, else the source's label
    /// (format.ts:7-27). Only translated when the host sent upstream's English default.
    public static func providerUsageLabel(id: String, label: String) -> String {
        let reviewPrefix = "Code review · "
        if id.hasPrefix("code_review:"), label.hasPrefix(reviewPrefix) {
            let periodId = String(id.dropFirst("code_review:".count))
            let periodLabel = String(label.dropFirst(reviewPrefix.count))
            return "Code review · \(providerUsageLabel(id: periodId, label: periodLabel))"
        }
        let standard: String?
        switch id {
        case "session", "five_hour": standard = "Session"
        case "weekly": standard = "Weekly"
        case "monthly": standard = "Monthly"
        case "code_review": standard = "Code review"
        case "credits": standard = "Credits"
        case "monthly_credits": standard = "Monthly credits"
        default: standard = nil
        }
        guard let standard, standard == label else { return label }
        return standard
    }

    // MARK: - Small helpers

    /// Grouped digits for counts inside copy ("1,204d ago").
    private static func countText(_ value: Int) -> String {
        value.formatted(.number.locale(displayLocale))
    }

    /// The device's 12/24-hour choice, as upstream's `formatTimeOfDay` (utils/time.ts:129-131).
    private static func timeOfDay(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    private static func weekday(_ date: Date, timeZone: TimeZone) -> String {
        date.formatted(
            Date.FormatStyle(locale: displayLocale, timeZone: timeZone).weekday(.abbreviated))
    }

    private static func dayAndMonth(_ date: Date, timeZone: TimeZone) -> String {
        date.formatted(
            Date.FormatStyle(locale: displayLocale, timeZone: timeZone).month(.abbreviated).day())
    }

    // MARK: - Problem sentences (Upstream: packages/app/src/usage/copy.ts:8-19)

    /// The sentence behind an `unavailable` report, with the host's own remedy when it has one.
    public static func problem(_ problem: UsageProblem, now: Date = .now) -> String {
        switch problem {
        case .noQuota(let detail):
            return detail
        case .rejected(let status, let refreshedBy):
            let remedy = refreshedBy.map { Copy.runToRefresh($0) } ?? Copy.signInAgain
            return Copy.loginRejected(status, remedy)
        case .expired(let expiresAt, let refreshedBy):
            let remedy = refreshedBy.map { Copy.runToRefresh($0) } ?? Copy.signInAgain
            return Copy.loginExpired(ago(expiresAt, now: now) ?? "", remedy)
        case .unknown:
            return ""
        }
    }

    /// The em dash upstream prints where a figure cannot be read (window-bar.tsx:60,
    /// balance-bar.tsx:35).
    public static var unknownValue: String { Copy.unknownValue }

    /// "{{amount}} left" (en.ts:2262): a balance with no limit to measure against.
    public static func remaining(_ amount: String) -> String { "\(amount) \(Copy.left)" }
}
