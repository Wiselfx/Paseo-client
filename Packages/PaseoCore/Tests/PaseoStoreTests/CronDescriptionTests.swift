import Foundation
import Testing

@testable import PaseoStore

/// UX-SPEC §5: the cron describer table, time-zone conversion and the custom fallback.
@Suite struct CronDescriptionTests {
    private var now: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: "2026-11-09T12:00:00Z") ?? Date(timeIntervalSince1970: 0)
    }

    private var utc: TimeZone { TimeZone(identifier: "UTC") ?? .gmt }

    private func describe(_ expression: String, scheduleTimeZone: String? = nil, deviceTimeZone: TimeZone? = nil) -> String {
        CronDescription.describe(
            expression: expression,
            scheduleTimeZone: scheduleTimeZone,
            now: now,
            deviceTimeZone: deviceTimeZone ?? utc)
    }

    @Test func everyNMinutes() {
        #expect(describe("*/15 * * * *") == "Every 15 minutes")
        #expect(describe("*/2 * * * *") == "Every 2 minutes")
        #expect(describe("*/5 * * * *") == "Every 5 minutes")
        #expect(describe("*/1 * * * *") == "Every minute")
    }

    @Test func hourlyAtMinute() {
        #expect(describe("30 * * * *") == "Hourly at :30")
        #expect(describe("0 * * * *") == "Hourly at :00")
        #expect(describe("5 * * * *") == "Hourly at :05")
    }

    @Test func daily() {
        #expect(describe("30 9 * * *") == "Daily at 9:30 AM")
        #expect(describe("21 1 * * *") == "Daily at 1:21 AM")
        #expect(describe("0 0 * * *") == "Daily at 12:00 AM")
        #expect(describe("0 12 * * *") == "Daily at 12:00 PM")
        #expect(describe("45 18 * * *") == "Daily at 6:45 PM")
    }

    @Test func weekdays() {
        #expect(describe("30 9 * * 1-5") == "Weekdays at 9:30 AM")
        #expect(describe("0 17 * * 1-5") == "Weekdays at 5:00 PM")
    }

    @Test func singleWeekday() {
        #expect(describe("30 9 * * 1") == "Every Monday at 9:30 AM")
        #expect(describe("30 9 * * 3") == "Every Wednesday at 9:30 AM")
        #expect(describe("30 9 * * 5") == "Every Friday at 9:30 AM")
        #expect(describe("30 9 * * 0") == "Every Sunday at 9:30 AM")
        #expect(describe("30 9 * * 7") == "Every Sunday at 9:30 AM")
        #expect(describe("30 9 * * MON") == "Every Monday at 9:30 AM")
    }

    @Test func monthlyOrdinals() {
        #expect(describe("30 9 1 * *") == "Monthly on the 1st at 9:30 AM")
        #expect(describe("30 9 2 * *") == "Monthly on the 2nd at 9:30 AM")
        #expect(describe("30 9 3 * *") == "Monthly on the 3rd at 9:30 AM")
        #expect(describe("30 9 9 * *") == "Monthly on the 9th at 9:30 AM")
        #expect(describe("30 9 11 * *") == "Monthly on the 11th at 9:30 AM")
        #expect(describe("30 9 12 * *") == "Monthly on the 12th at 9:30 AM")
        #expect(describe("30 9 13 * *") == "Monthly on the 13th at 9:30 AM")
        #expect(describe("30 9 21 * *") == "Monthly on the 21st at 9:30 AM")
        #expect(describe("30 9 22 * *") == "Monthly on the 22nd at 9:30 AM")
        #expect(describe("30 9 23 * *") == "Monthly on the 23rd at 9:30 AM")
        #expect(describe("30 9 31 * *") == "Monthly on the 31st at 9:30 AM")
    }

    @Test func yearly() {
        #expect(describe("21 1 9 11 *") == "Once a year on Nov 9 at 1:21 AM")
        #expect(describe("21 1 9 NOV *") == "Once a year on Nov 9 at 1:21 AM")
        #expect(describe("0 0 1 1 *") == "Once a year on Jan 1 at 12:00 AM")
    }

    @Test func customFallback() {
        #expect(describe("gibberish") == "Custom schedule")
        #expect(describe("") == "Custom schedule")
        #expect(describe("0 9 * *") == "Custom schedule")
        #expect(describe("*/30 */6 * * *") == "Custom schedule")
        #expect(describe("0 9 * JAN *") == "Custom schedule")
        #expect(describe("0 9 * * 8") == "Custom schedule")
        #expect(describe("60 * * * *") == "Custom schedule")
        #expect(describe("* * * * *") == "Custom schedule")
        #expect(describe("0 9 1,15 * *") == "Custom schedule")
        #expect(describe("0 9 * * 0,6") == "Custom schedule")
    }

    @Test func isCustom() {
        #expect(CronDescription.isCustom(expression: "30 9 * * *", scheduleTimeZone: nil, now: now, deviceTimeZone: utc) == false)
        #expect(CronDescription.isCustom(expression: "gibberish", scheduleTimeZone: nil, now: now, deviceTimeZone: utc) == true)
    }

    @Test func convertsFromScheduleTimeZoneToDevice() throws {
        // Europe/Sofia is UTC+2 in November: 9:30 Sofia is 7:30 in UTC.
        let sofia = try #require(TimeZone(identifier: "Europe/Sofia"))
        #expect(describe("30 9 * * *", scheduleTimeZone: "Europe/Sofia", deviceTimeZone: utc) == "Daily at 7:30 AM")
        // Unknown schedule time zone: no conversion.
        #expect(describe("30 9 * * *", scheduleTimeZone: "Not/AZone", deviceTimeZone: utc) == "Daily at 9:30 AM")
        _ = sofia
    }

    @Test func conversionCrossesMidnight() throws {
        // 23:30 in New York (UTC-5 in November) is 4:30 next day in UTC.
        _ = try #require(TimeZone(identifier: "America/New_York"))
        #expect(describe("30 23 * * *", scheduleTimeZone: "America/New_York", deviceTimeZone: utc) == "Daily at 4:30 AM")
    }
}
