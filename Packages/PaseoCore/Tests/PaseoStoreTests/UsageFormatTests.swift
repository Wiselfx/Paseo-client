import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Upstream `packages/app/src/usage/format.ts` ported into Core: percent maths, the two-unit
/// countdown, the exact reset time, relative freshness and upstream's own copy.
@Suite
struct UsageFormatTests {
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
    private static let english = Locale(identifier: "en_US")

    private static let now: Date = {
        ISO8601DateFormatter().date(from: "2026-11-09T08:00:00Z") ?? Date(timeIntervalSince1970: 0)
    }()

    private static func at(_ seconds: TimeInterval) -> String {
        let date = now.addingTimeInterval(seconds)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = utc
        return formatter.string(from: date)
    }

    // MARK: Percent (format.ts:29-52)

    @Test func percentIsClampedAndHasNoFractionDigits() {
        #expect(UsageFormat.percent(21) == "21%")
        #expect(UsageFormat.percent(20.6) == "21%")
        #expect(UsageFormat.percent(20.4) == "20%")
        #expect(UsageFormat.percent(-4) == "0%")
        #expect(UsageFormat.percent(140) == "100%")
        #expect(UsageFormat.clampPct(.nan) == 0)
    }

    @Test func displayPercentSaysWhetherItIsUsedOrLeft() {
        #expect(UsageFormat.displayPercent(21, as: .used) == "21% used")
        #expect(UsageFormat.displayPercent(79, as: .remaining) == "79% left")
    }

    // MARK: Countdowns (format.ts:70-115)

    @Test func countdownShowsTwoFlooredUnits() {
        // 37 minutes.
        #expect(UsageFormat.resetLabel(Self.at(37 * 60), now: Self.now) == "resets in 37m")
        // 4h 59m 30s floors to two units.
        let fourHours = Self.at(4 * 3600 + 59 * 60 + 30)
        #expect(UsageFormat.resetLabel(fourHours, now: Self.now) == "resets in 4h 59m")
        // 2d 23h 10m.
        let twoDays = Self.at(2 * 86_400 + 23 * 3600 + 600)
        #expect(UsageFormat.resetLabel(twoDays, now: Self.now) == "resets in 2d 23h")
        // A whole number of hours drops the zero minutes.
        #expect(UsageFormat.resetLabel(Self.at(3 * 3600), now: Self.now) == "resets in 3h")
    }

    @Test func aPassedResetSaysSoAndRetainedDataSaysTheResetHasPassed() {
        let past = Self.at(-60)
        #expect(UsageFormat.resetLabel(past, now: Self.now) == "resetting now")
        #expect(UsageFormat.resetLabel(past, retained: true, now: Self.now) == "Reset time passed")
        #expect(UsageFormat.resetLabel(nil, now: Self.now) == nil)
        #expect(UsageFormat.resetLabel("not a date", now: Self.now) == nil)
    }

    @Test func runsOutWarningUsesItsOwnVerb() {
        #expect(UsageFormat.runsOutLabel(Self.at(125 * 60), now: Self.now) == "runs out in 2h 5m")
        #expect(UsageFormat.runsOutLabel(Self.at(-5), now: Self.now) == "runs out now")
    }

    // MARK: Exact reset time (format.ts:117-140)

    /// ICU writes the gap before AM/PM as a narrow no-break space; compare words, not bytes.
    private static func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func resetTimeIsAClockTimeWithinADay() {
        // 15:00 UTC, seven hours out.
        #expect(
            Self.plain(
                UsageFormat.resetTime(
                    Self.at(7 * 3600), now: Self.now, locale: Self.english, timeZone: Self.utc))
                == "3:00 PM")
    }

    @Test func resetTimeNamesTheWeekdayAndThenTheDate() {
        let inThreeDays = Self.at(3 * 86_400)
        #expect(
            Self.plain(
                UsageFormat.resetTime(
                    inThreeDays, now: Self.now, locale: Self.english, timeZone: Self.utc))
                == "Thu 8:00 AM")
        let inTenDays = Self.at(10 * 86_400)
        // 2026-11-19.
        #expect(
            Self.plain(
                UsageFormat.resetTime(
                    inTenDays, now: Self.now, locale: Self.english, timeZone: Self.utc))
                == "Nov 19, 8:00 AM")
    }

    @Test func resetTimeIsNilForAPassedTimeOrAnUnreadableDate() {
        #expect(
            UsageFormat.resetTime(Self.at(-60), now: Self.now, locale: Self.english,
                timeZone: Self.utc) == nil)
        #expect(UsageFormat.resetTime(nil, now: Self.now) == nil)
    }

    // MARK: Freshness (format.ts:154-182, card.tsx:255-280)

    @Test func agoCountsUpFromJustNow() {
        #expect(UsageFormat.ago(Self.at(-10), now: Self.now) == "just now")
        #expect(UsageFormat.ago(Self.at(-37 * 60), now: Self.now) == "37m ago")
        #expect(UsageFormat.ago(Self.at(-5 * 3600), now: Self.now) == "5h ago")
        #expect(UsageFormat.ago(Self.at(-3 * 86_400), now: Self.now) == "3d ago")
    }

    @Test func freshnessUsesUpstreamsThreeSentences() {
        #expect(
            UsageFormat.freshness(Self.at(-5 * 60), retained: false, now: Self.now)
                == "Updated 5m ago")
        #expect(
            UsageFormat.freshness(Self.at(-5 * 60), retained: true, now: Self.now)
                == "Last updated 5m ago")
        #expect(
            UsageFormat.freshness(nil, retained: true, now: Self.now) == "No successful update")
    }

    // MARK: Amounts (format.ts:184-197)

    @Test func amountsWearUpstreamsShapes() {
        #expect(UsageFormat.amount(1234.5, unit: .usd) == "$1,234.50")
        #expect(UsageFormat.amount(12.25, unit: .credits) == "12.25")
        #expect(UsageFormat.amount(12_345, unit: .tokens) == "12.3K")
        #expect(UsageFormat.amount(2_000_000, unit: .tokens) == "2M")
        #expect(UsageFormat.amount(950, unit: .requests) == "950")
    }

    // MARK: Labels (format.ts:7-27)

    @Test func knownWindowsWearUpstreamsNames() {
        #expect(UsageFormat.providerUsageLabel(id: "five_hour", label: "Session") == "Session")
        #expect(UsageFormat.providerUsageLabel(id: "weekly", label: "Weekly") == "Weekly")
        #expect(UsageFormat.providerUsageLabel(id: "monthly_credits", label: "Monthly credits")
            == "Monthly credits")
        // A source's own words stay: upstream only substitutes its own default.
        #expect(UsageFormat.providerUsageLabel(id: "weekly", label: "Rolling week") == "Rolling week")
        #expect(UsageFormat.providerUsageLabel(id: "code_review:weekly", label: "Code review · Weekly")
            == "Code review · Weekly")
        #expect(UsageFormat.providerUsageLabel(id: "mystery", label: "Mystery") == "Mystery")
    }

    // MARK: Problem sentences (copy.ts:8-19)

    private func problem(_ json: String) throws -> UsageProblem {
        try JSONDecoder().decode(UsageProblem.self, from: Data(json.utf8))
    }

    @Test func problemSentencesAreUpstreams() throws {
        #expect(
            UsageFormat.problem(try problem(#"{"kind":"no_quota","detail":"No quota left"}"#),
                now: Self.now) == "No quota left")
        #expect(
            UsageFormat.problem(
                try problem(#"{"kind":"rejected","status":401}"#), now: Self.now)
                == "Login rejected (HTTP 401). Sign in again.")
        #expect(
            UsageFormat.problem(
                try problem(#"{"kind":"rejected","status":403,"refreshedBy":"paseo auth"}"#),
                now: Self.now) == "Login rejected (HTTP 403). Run paseo auth to refresh it.")
        let expired = try problem(
            #"{"kind":"expired","expiresAt":"2026-11-09T07:00:00Z"}"#)
        #expect(UsageFormat.problem(expired, now: Self.now) == "Login expired 1h ago. Sign in again.")
    }
}
