import Foundation

/// Cron → words, for the Schedules screen and anywhere else the app shows a cadence in English
/// ("Every day at 9:00"). Pure Foundation on purpose: PaseoUI builds only on Apple platforms, so
/// this file is also copied into a scratch package to run its tests on Linux.
///
/// Supported and tested:
/// - `every minute` / `every N minutes` (`* * * * *`, `* /` steps on the minute field)
/// - `every hour` and `every hour at :MM` (`M * * * *`)
/// - `every N hours` (`0 * / N * * *` with step on the hour field)
/// - `every day at H:MM` (`M H * * *`)
/// - weekday rules: `1-5` / `MON-FRI` → "Every weekday at H:MM", `0,6` / `SAT,SUN` → "Every weekend at H:MM",
///   single named or numeric day → "Every Monday at H:MM", lists → "Every Monday, Wednesday and Friday at H:MM"
/// - `0 M D * *` → "On the 1st of every month at H:MM"
/// - `every day` from `.every(ms: 86_400_000)` and the minute/hour/day/week family
/// - `?` (a Quartz-ism) is read as `*`
///
/// Anything outside that grammar renders as `"Cron: <expression>"` — unusual cron is shown, never
/// silently mistranslated. A timezone, when present, is appended after the words.
enum ScheduleWords {
    /// The cadence line Paseo explains for itself, shown on list rows and the detail page.
    static func cadence(everyMs: Int) -> String {
        let minute = 60_000
        let hour = 60 * minute
        let day = 24 * hour
        let week = 7 * day

        func every(_ count: Int, _ unit: String) -> String {
            count == 1 ? "Every \(unit)" : "Every \(count) \(unit)s"
        }

        switch everyMs {
        case minute: return "Every minute"
        case hour: return "Every hour"
        case day: return "Every day"
        case week: return "Every week"
        default: break
        }
        if everyMs % week == 0, everyMs / week >= 2 { return every(everyMs / week, "week") }
        if everyMs % day == 0, everyMs / day >= 2 { return every(everyMs / day, "day") }
        if everyMs % hour == 0, everyMs / hour >= 2 { return every(everyMs / hour, "hour") }
        if everyMs % minute == 0, everyMs / minute >= 2 { return every(everyMs / minute, "minute") }
        return "Every \(everyMs) ms"
    }

    /// The cadence line for a cron expression; `timezone`, when present, is appended.
    static func cadence(expression: String, timezone: String?) -> String {
        guard let fields = parse(expression) else {
            return withTimezone("Cron: \(expression)", timezone)
        }
        let (minute, hour, dayOfMonth, month, dayOfWeek) = fields
        let words: String
        switch describe(minute: minute, hour: hour, dayOfMonth: dayOfMonth, month: month, dayOfWeek: dayOfWeek) {
        case .some(let described): words = described
        case .none: words = "Cron: \(expression)"
        }
        return withTimezone(words, timezone)
    }

    /// True when all five fields parse under the grammar. Used to reject a custom cadence at the form.
    static func isValid(cron expression: String) -> Bool {
        parse(expression) != nil
    }

    // MARK: Grammar

    private enum ParsedField: Equatable {
        case any
        case step(Int)
        case set(Set<Int>)
    }

    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    private static func parse(_ expression: String) -> (ParsedField, ParsedField, ParsedField, ParsedField, ParsedField)? {
        let cleaned = expression.replacingOccurrences(of: "?", with: "*")
        let fields = cleaned.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 5 else { return nil }
        guard
            let minute = field(fields[0], min: 0, max: 59, names: nil),
            let hour = field(fields[1], min: 0, max: 23, names: nil),
            let dayOfMonth = field(fields[2], min: 1, max: 31, names: nil),
            let month = field(fields[3], min: 1, max: 12, names: monthNames),
            let dayOfWeek = field(fields[4], min: 0, max: 7, names: dayNames),
            let normalizedWeekday = normalizeWeekday(dayOfWeek)
        else { return nil }
        return (minute, hour, dayOfMonth, month, normalizedWeekday)
    }

    /// 0 and 7 are both Sunday; collapse 7 to 0. A range or set covering 0…6 is all week.
    private static func normalizeWeekday(_ field: ParsedField) -> ParsedField? {
        switch field {
        case .any: return .any
        case .step(let step): return .step(step)
        case .set(var values):
            if values.contains(7) {
                var shifted = values.subtracting([7])
                shifted.insert(0)
                values = shifted
            }
            if values == [0, 1, 2, 3, 4, 5, 6] { return .any }
            return .set(values)
        }
    }

    private static func field(_ raw: String, min: Int, max: Int, names: [String]?) -> ParsedField? {
        if raw == "*" { return .any }

        let terms = raw.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
        guard !terms.isEmpty else { return nil }

        var values = Set<Int>()
        var step: Int?
        for term in terms {
            if term == "*" {
                values = Set(min...max)
                continue
            }
            if term.hasPrefix("*/") {
                let rest = String(term.dropFirst(2))
                guard let n = Int(rest), n >= 1 else { return nil }
                if n == 1 { return .any }
                if step != nil { return nil } // at most one step term per field
                step = n
                continue
            }
            if let dash = term.firstIndex(of: "-") {
                let lower = resolve(String(term[..<dash]), names: names)
                let upper = resolve(String(term[term.index(after: dash)...]), names: names)
                guard let lower, let upper, lower >= min, upper <= max, lower <= upper else { return nil }
                values.formUnion(lower...upper)
                continue
            }
            guard let value = resolve(term, names: names) else { return nil }
            guard value >= min, value <= max else { return nil }
            values.insert(value)
        }

        if let step {
            guard values.isEmpty else {
                // "*/2,4" is beyond the words we promise.
                return nil
            }
            return .step(step)
        }
        if values == Set(min...max) { return .any }
        return .set(values)
    }

    private static func resolve(_ token: String, names: [String]?) -> Int? {
        if let number = Int(token) { return number }
        guard let names else { return nil }
        let lower = token.lowercased()
        guard let index = names.firstIndex(of: lower) else { return nil }
        return names == dayNames ? index : index + 1
    }

    // MARK: Words

    private static func describe(
        minute: ParsedField, hour: ParsedField, dayOfMonth: ParsedField, month: ParsedField, dayOfWeek: ParsedField
    ) -> String? {
        let domAny = dayOfMonth == .any
        let monthAny = month == .any
        let dowAny = dayOfWeek == .any

        func clock(_ minuteValue: Int, _ hourValue: Int) -> String {
            String(format: "%d:%02d", hourValue, minuteValue)
        }

        func exactMinute() -> Int? {
            guard case .set(let values) = minute, values.count == 1, let value = values.first else { return nil }
            return value
        }

        func exactHour() -> Int? {
            guard case .set(let values) = hour, values.count == 1, let value = values.first else { return nil }
            return value
        }

        func stepCount(_ field: ParsedField) -> Int? {
            guard case .step(let n) = field else { return nil }
            return n
        }

        // Every minute.
        if minute == .any, hour == .any, domAny, monthAny, dowAny { return "Every minute" }

        // Every N minutes.
        if let n = stepCount(minute), hour == .any, domAny, monthAny, dowAny {
            return n == 1 ? "Every minute" : "Every \(n) minutes"
        }

        // Every N hours (optionally "at :MM").
        if let n = stepCount(hour), domAny, monthAny, dowAny {
            let m = exactMinute()
            if m == 0 { return "Every \(n) hours" }
            if let m { return String(format: "Every %d hours at :%02d", n, m) }
        }

        // Every hour at :MM (or every hour).
        if hour == .any, domAny, monthAny, dowAny {
            if let m = exactMinute() {
                return m == 0 ? "Every hour" : String(format: "Every hour at :%02d", m)
            }
            if case .set(let values) = minute, values.count <= 3, !values.isEmpty {
                let marks = values.sorted().map { String(format: ":%02d", $0) }.joined(separator: " and ")
                return "Every hour at \(marks)"
            }
        }

        // The daily/weekly family: single hour, single minute.
        if let hourValue = exactHour(), let minuteValue = exactMinute() {
            let at = clock(minuteValue, hourValue)

            if domAny, monthAny, dowAny { return "Every day at \(at)" }

            if domAny, monthAny, let dayText = weekdayWords(dayOfWeek) { return "\(dayText) at \(at)" }

            if case .set(let days) = dayOfMonth, days.count == 1, monthAny, dowAny, let day = days.first {
                return "On the \(ordinal(day)) of every month at \(at)"
            }

            if case .set(let days) = dayOfMonth, days.count <= 3, monthAny, dowAny {
                let list = days.sorted().map(ordinal).joined(separator: " and ")
                return "On the \(list) of every month at \(at)"
            }
        }

        return nil
    }

    private static func weekdayWords(_ field: ParsedField) -> String? {
        switch field {
        case .any: return "Every day"
        case .step: return nil
        case .set(let values):
            let sorted = values.sorted()
            if sorted == [1, 2, 3, 4, 5] { return "Every weekday" }
            if sorted == [0, 6] { return "Every weekend" }
            if let value = sorted.first, sorted.count == 1 { return "Every \(dayName(value))" }
            if sorted.count > 1 {
                if isContiguous(sorted) {
                    return "Every \(dayName(sorted.first!))–\(dayName(sorted.last!))"
                }
                return "Every " + joinedWithAnd(sorted.map(dayName))
            }
            return nil
        }
    }

    private static func isContiguous(_ values: [Int]) -> Bool {
        for index in 1..<values.count where values[index] != values[index - 1] + 1 {
            return false
        }
        return true
    }

    /// "Monday, Wednesday and Friday".
    private static func joinedWithAnd(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return parts.joined(separator: " and ")
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }

    private static func dayName(_ value: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][value]
    }

    private static func ordinal(_ day: Int) -> String {
        // 1st, 2nd, 3rd, 4th…, with the 11th/12th/13th exceptions.
        let suffix: String
        if (11...13).contains(day % 100) {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    private static func withTimezone(_ words: String, _ timezone: String?) -> String {
        guard let timezone, !timezone.isEmpty else { return words }
        return "\(words) · \(timezone)"
    }
}
