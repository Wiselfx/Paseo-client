import Foundation

/// Human wording for a cron cadence, per UX-SPEC §5.
///
/// Pure function: the caller supplies the schedule's time zone, the current
/// instant and the device time zone. Times are shown in the device time zone;
/// the cron clock is read in the schedule's time zone and the next run is
/// converted into the device time zone. A missing or unknown schedule time
/// zone means no conversion (the clock is already the device clock).
///
/// Recognised shapes only; anything else is "Custom schedule" (the raw
/// expression is shown in the detail page, never in the list):
/// - `*/N * * * *` → "Every N minutes"
/// - `M * * * *` → "Hourly at :MM"
/// - `M H * * *` → "Daily at 9:30 AM"
/// - `M H * * 1-5` → "Weekdays at 9:30 AM"
/// - `M H * * D` → "Every Monday at 9:30 AM"
/// - `M H d * *` → "Monthly on the 9th at 9:30 AM"
/// - `M H d m *` → "Once a year on Nov 9 at 1:21 AM"
public enum CronDescription {
    public static let custom = "Custom schedule"

    public static func describe(
        expression: String,
        scheduleTimeZone: String?,
        now: Date,
        deviceTimeZone: TimeZone
    ) -> String {
        guard let shape = parse(expression) else { return custom }
        let scheduleZone = scheduleTimeZone.flatMap { TimeZone(identifier: $0) } ?? deviceTimeZone
        switch shape {
        case .everyMinutes(let step):
            return step == 1 ? "Every minute" : "Every \(step) minutes"
        case .hourly(let minute):
            let shifted = shiftedMinute(minute, scheduleZone: scheduleZone, deviceTimeZone: deviceTimeZone, now: now)
            return "Hourly at :\(twoDigits(shifted))"
        case .daily(let minute, let hour):
            let instant = nextDaily(minute: minute, hour: hour, scheduleZone: scheduleZone, now: now)
            return "Daily at \(clockTime(at: instant, deviceTimeZone: deviceTimeZone))"
        case .weekdays(let minute, let hour):
            let instant = nextWeekday(minute: minute, hour: hour, scheduleZone: scheduleZone, now: now)
            return "Weekdays at \(clockTime(at: instant, deviceTimeZone: deviceTimeZone))"
        case .singleWeekday(let minute, let hour, let weekday):
            let instant = nextSingleWeekday(minute: minute, hour: hour, weekday: weekday, scheduleZone: scheduleZone, now: now)
            let converted = components(at: instant, deviceTimeZone: deviceTimeZone)
            return "Every \(weekdayName(converted.weekday)) at \(clockTime(at: instant, deviceTimeZone: deviceTimeZone))"
        case .monthly(let minute, let hour, let day):
            let instant = nextMonthly(minute: minute, hour: hour, day: day, scheduleZone: scheduleZone, now: now)
            let converted = components(at: instant, deviceTimeZone: deviceTimeZone)
            return "Monthly on the \(ordinal(converted.day)) at \(clockTime(at: instant, deviceTimeZone: deviceTimeZone))"
        case .yearly(let minute, let hour, let day, let month):
            let instant = nextYearly(minute: minute, hour: hour, day: day, month: month, scheduleZone: scheduleZone, now: now)
            let converted = components(at: instant, deviceTimeZone: deviceTimeZone)
            return "Once a year on \(monthName(converted.month)) \(converted.day) at \(clockTime(at: instant, deviceTimeZone: deviceTimeZone))"
        }
    }

    public static func isCustom(
        expression: String,
        scheduleTimeZone: String?,
        now: Date,
        deviceTimeZone: TimeZone
    ) -> Bool {
        describe(expression: expression, scheduleTimeZone: scheduleTimeZone, now: now, deviceTimeZone: deviceTimeZone) == custom
    }

    // MARK: Shapes

    private enum Shape {
        case everyMinutes(Int)
        case hourly(minute: Int)
        case daily(minute: Int, hour: Int)
        case weekdays(minute: Int, hour: Int)
        case singleWeekday(minute: Int, hour: Int, weekday: Int)
        case monthly(minute: Int, hour: Int, day: Int)
        case yearly(minute: Int, hour: Int, day: Int, month: Int)
    }

    private static func parse(_ expression: String) -> Shape? {
        let fields = expression.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 5 else { return nil }
        guard let minute = anyField(fields[0]) ?? exact(fields[0], min: 0, max: 59) ?? step(fields[0], max: 59),
              let hour = anyField(fields[1]) ?? exact(fields[1], min: 0, max: 23) ?? step(fields[1], max: 23)
        else { return nil }

        // Every N minutes: */N * * * *
        if case .step(let n) = minute, hour == .any, isAny(fields[2]), isAny(fields[3]), isAny(fields[4]) {
            return .everyMinutes(n)
        }
        // Hourly: M * * * *
        if case .exact(let m) = minute, hour == .any, isAny(fields[2]), isAny(fields[3]), isAny(fields[4]) {
            return .hourly(minute: m)
        }
        guard case .exact(let m) = minute, case .exact(let h) = hour else { return nil }

        // Daily / weekdays / single weekday: M H * * *
        if isAny(fields[2]), isAny(fields[3]) {
            if isAny(fields[4]) { return .daily(minute: m, hour: h) }
            if let weekdays = weekdaySet(fields[4]) {
                if weekdays == Set(1...5) { return .weekdays(minute: m, hour: h) }
                if weekdays.count == 1, let day = weekdays.first { return .singleWeekday(minute: m, hour: h, weekday: day) }
            }
            return nil
        }
        // Monthly: M H d * *
        if isAny(fields[3]), isAny(fields[4]), let day = exactValue(fields[2], min: 1, max: 31) {
            return .monthly(minute: m, hour: h, day: day)
        }
        // Yearly: M H d m *
        if isAny(fields[4]), let day = exactValue(fields[2], min: 1, max: 31), let month = monthValue(fields[3]) {
            return .yearly(minute: m, hour: h, day: day, month: month)
        }
        return nil
    }

    private enum Field: Equatable {
        case any
        case exact(Int)
        case step(Int)
    }

    private static func anyField(_ raw: String) -> Field? {
        isAny(raw) ? .any : nil
    }

    private static func exact(_ raw: String, min: Int, max: Int) -> Field? {
        guard let value = exactValue(raw, min: min, max: max) else { return nil }
        return .exact(value)
    }

    private static func exactValue(_ raw: String, min: Int, max: Int) -> Int? {
        guard let value = Int(raw), (min...max).contains(value) else { return nil }
        return value
    }

    private static func step(_ raw: String, max: Int) -> Field? {
        guard raw.hasPrefix("*/") else { return nil }
        guard let value = Int(String(raw.dropFirst(2))), value >= 1, value <= max else { return nil }
        return .step(value)
    }

    private static func isAny(_ raw: String) -> Bool { raw == "*" || raw == "?" }

    private static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// A weekday field as a set (1 = Monday … 7 = Sunday); 0 and 7 are Sunday.
    private static func weekdaySet(_ raw: String) -> Set<Int>? {
        var values = Set<Int>()
        for term in raw.split(separator: ",", omittingEmptySubsequences: true).map(String.init) {
            if let dash = term.firstIndex(of: "-") {
                guard let lower = weekdayValue(String(term[..<dash])), let upper = weekdayValue(String(term[term.index(after: dash)...])),
                      lower <= upper
                else { return nil }
                values.formUnion(lower...upper)
            } else if let value = weekdayValue(term) {
                values.insert(value)
            } else {
                return nil
            }
        }
        guard !values.isEmpty else { return nil }
        var normalized = Set<Int>()
        for value in values { normalized.insert(value == 7 ? 7 : value) }
        return normalized
    }

    private static func weekdayValue(_ token: String) -> Int? {
        if let number = Int(token) {
            guard (0...7).contains(number) else { return nil }
            return number == 0 ? 7 : number
        }
        let lower = token.lowercased()
        guard let index = dayNames.firstIndex(of: lower) else { return nil }
        // Sunday (index 0) is 7; Monday (1) is 1 … Saturday (6) is 6.
        return index == 0 ? 7 : index
    }

    private static func monthValue(_ token: String) -> Int? {
        if let number = Int(token) {
            guard (1...12).contains(number) else { return nil }
            return number
        }
        let lower = token.lowercased()
        guard let index = monthNames.firstIndex(of: lower) else { return nil }
        return index + 1
    }

    // MARK: Next run in the schedule time zone

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func date(in timeZone: TimeZone, year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date? {
        let calendar = calendar(in: timeZone)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = calendar.date(from: components) else { return nil }
        // Calendar silently rolls an impossible date (Nov 31) into the next month;
        // reject those so monthly/yearly shapes advance to a month that has the day.
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day,
              roundTrip.hour == hour, roundTrip.minute == minute else { return nil }
        return date
    }

    private static func components(at date: Date, deviceTimeZone: TimeZone) -> (year: Int, month: Int, day: Int, hour: Int, minute: Int, weekday: Int) {
        let calendar = calendar(in: deviceTimeZone)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        return (
            year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0,
            hour: parts.hour ?? 0, minute: parts.minute ?? 0, weekday: parts.weekday ?? 0
        )
    }

    private static func nextDaily(minute: Int, hour: Int, scheduleZone: TimeZone, now: Date) -> Date {
        let calendar = calendar(in: scheduleZone)
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        if let year = today.year, let month = today.month, let day = today.day,
           let candidate = date(in: scheduleZone, year: year, month: month, day: day, hour: hour, minute: minute),
           candidate >= now {
            return candidate
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let parts = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return now }
        return date(in: scheduleZone, year: year, month: month, day: day, hour: hour, minute: minute) ?? now
    }

    private static func nextWeekday(minute: Int, hour: Int, scheduleZone: TimeZone, now: Date) -> Date {
        let calendar = calendar(in: scheduleZone)
        for offset in 0...6 {
            let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            guard let weekday = parts.weekday, weekday != 1, weekday != 7,
                  let year = parts.year, let month = parts.month, let day = parts.day else { continue }
            if let candidate = date(in: scheduleZone, year: year, month: month, day: day, hour: hour, minute: minute),
               candidate >= now {
                return candidate
            }
        }
        return nextDaily(minute: minute, hour: hour, scheduleZone: scheduleZone, now: now)
    }

    private static func nextSingleWeekday(minute: Int, hour: Int, weekday: Int, scheduleZone: TimeZone, now: Date) -> Date {
        let calendar = calendar(in: scheduleZone)
        for offset in 0...7 {
            let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            // Calendar weekday: 1 = Sunday … 7 = Saturday. Cron weekday here: 1 = Monday … 7 = Sunday.
            guard let calendarWeekday = parts.weekday,
                  let year = parts.year, let month = parts.month, let day = parts.day else { continue }
            let cronWeekday = calendarWeekday == 1 ? 7 : calendarWeekday - 1
            guard cronWeekday == weekday else { continue }
            if let candidate = date(in: scheduleZone, year: year, month: month, day: day, hour: hour, minute: minute),
               candidate >= now {
                return candidate
            }
        }
        return nextDaily(minute: minute, hour: hour, scheduleZone: scheduleZone, now: now)
    }

    private static func nextMonthly(minute: Int, hour: Int, day: Int, scheduleZone: TimeZone, now: Date) -> Date {
        let calendar = calendar(in: scheduleZone)
        let today = calendar.dateComponents([.year, .month], from: now)
        if let year = today.year, let month = today.month,
           let candidate = date(in: scheduleZone, year: year, month: month, day: day, hour: hour, minute: minute),
           candidate >= now {
            return candidate
        }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        let parts = calendar.dateComponents([.year, .month], from: nextMonth)
        guard let year = parts.year, let month = parts.month else { return now }
        return date(in: scheduleZone, year: year, month: month, day: day, hour: hour, minute: minute) ?? now
    }

    private static func nextYearly(minute: Int, hour: Int, day: Int, month: Int, scheduleZone: TimeZone, now: Date) -> Date {
        let calendar = calendar(in: scheduleZone)
        let today = calendar.dateComponents([.year], from: now)
        guard let year = today.year else { return now }
        if let candidate = date(in: scheduleZone, year: year, month: month, day: day, hour: hour, minute: minute),
           candidate >= now {
            return candidate
        }
        return date(in: scheduleZone, year: year + 1, month: month, day: day, hour: hour, minute: minute) ?? now
    }

    private static func shiftedMinute(_ minute: Int, scheduleZone: TimeZone, deviceTimeZone: TimeZone, now: Date) -> Int {
        let difference = deviceTimeZone.secondsFromGMT(for: now) - scheduleZone.secondsFromGMT(for: now)
        let shifted = (minute + difference / 60) % 60
        return shifted >= 0 ? shifted : shifted + 60
    }

    // MARK: Words

    private static func clockTime(at date: Date, deviceTimeZone: TimeZone) -> String {
        let parts = components(at: date, deviceTimeZone: deviceTimeZone)
        let hour12 = parts.hour % 12 == 0 ? 12 : parts.hour % 12
        let suffix = parts.hour < 12 ? "AM" : "PM"
        return "\(hour12):\(twoDigits(parts.minute)) \(suffix)"
    }

    private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

    private static func weekdayName(_ calendarWeekday: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[min(max(calendarWeekday, 1), 7) - 1]
    }

    private static func monthName(_ month: Int) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return names[min(max(month, 1), 12) - 1]
    }

    private static func ordinal(_ day: Int) -> String {
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
}
