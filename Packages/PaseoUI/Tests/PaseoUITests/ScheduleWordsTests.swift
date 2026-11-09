import Foundation
import Testing
@testable import PaseoUI

struct ScheduleWordsTests {
    @Test func everyCadences() {
        #expect(ScheduleWords.cadence(everyMs: 60_000) == "Every minute")
        #expect(ScheduleWords.cadence(everyMs: 300_000) == "Every 5 minutes")
        #expect(ScheduleWords.cadence(everyMs: 3_600_000) == "Every hour")
        #expect(ScheduleWords.cadence(everyMs: 7_200_000) == "Every 2 hours")
        #expect(ScheduleWords.cadence(everyMs: 86_400_000) == "Every day")
        #expect(ScheduleWords.cadence(everyMs: 604_800_000) == "Every week")
        #expect(ScheduleWords.cadence(everyMs: 1_800_000) == "Every 30 minutes")
        #expect(ScheduleWords.cadence(everyMs: 5_400_000) == "Every 90 minutes")
        #expect(ScheduleWords.cadence(everyMs: 172_800_000) == "Every 2 days")
        #expect(ScheduleWords.cadence(everyMs: 45_000) == "Every 45000 ms")
    }

    @Test func everyMinuteCron() {
        #expect(ScheduleWords.cadence(expression: "* * * * *", timezone: nil) == "Every minute")
        #expect(ScheduleWords.cadence(expression: "* * * * *", timezone: "") == "Every minute")
        #expect(ScheduleWords.cadence(expression: "*/15 * * * *", timezone: nil) == "Every 15 minutes")
        #expect(ScheduleWords.cadence(expression: "*/2 * * * *", timezone: nil) == "Every 2 minutes")
        #expect(ScheduleWords.cadence(expression: "*/1 * * * *", timezone: nil) == "Every minute")
        #expect(ScheduleWords.cadence(expression: "? * * * *", timezone: nil) == "Every minute")
    }

    @Test func hourlyCron() {
        #expect(ScheduleWords.cadence(expression: "0 * * * *", timezone: nil) == "Every hour")
        #expect(ScheduleWords.cadence(expression: "15 * * * *", timezone: nil) == "Every hour at :15")
        #expect(ScheduleWords.cadence(expression: "30 * * * *", timezone: nil) == "Every hour at :30")
        #expect(ScheduleWords.cadence(expression: "0,30 * * * *", timezone: nil) == "Every hour at :00 and :30")
        #expect(ScheduleWords.cadence(expression: "0 */6 * * *", timezone: nil) == "Every 6 hours")
        #expect(ScheduleWords.cadence(expression: "0 */2 * * *", timezone: nil) == "Every 2 hours")
        #expect(ScheduleWords.cadence(expression: "15 */6 * * *", timezone: nil) == "Every 6 hours at :15")
    }

    @Test func dailyCron() {
        #expect(ScheduleWords.cadence(expression: "0 9 * * *", timezone: nil) == "Every day at 9:00")
        #expect(ScheduleWords.cadence(expression: "30 18 * * *", timezone: nil) == "Every day at 18:30")
        #expect(ScheduleWords.cadence(expression: "0 0 * * *", timezone: nil) == "Every day at 0:00")
        #expect(ScheduleWords.cadence(expression: "5 7 * * *", timezone: "Europe/Sofia") == "Every day at 7:05 · Europe/Sofia")
    }

    @Test func weekdayCron() {
        #expect(ScheduleWords.cadence(expression: "0 9 * * 1", timezone: nil) == "Every Monday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * MON", timezone: nil) == "Every Monday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * mon", timezone: nil) == "Every Monday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * 0", timezone: nil) == "Every Sunday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * 7", timezone: nil) == "Every Sunday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * 3", timezone: nil) == "Every Wednesday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * 1-5", timezone: nil) == "Every weekday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * MON-FRI", timezone: nil) == "Every weekday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * mon-fri", timezone: nil) == "Every weekday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * 0,6", timezone: nil) == "Every weekend at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * 6,0", timezone: nil) == "Every weekend at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * SAT,SUN", timezone: nil) == "Every weekend at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * 1,3,5", timezone: nil) == "Every Monday, Wednesday and Friday at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 * * 2-4", timezone: nil) == "Every Tuesday–Thursday at 9:00")
    }

    @Test func monthlyCron() {
        #expect(ScheduleWords.cadence(expression: "0 9 1 * *", timezone: nil) == "On the 1st of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 2 * *", timezone: nil) == "On the 2nd of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 3 * *", timezone: nil) == "On the 3rd of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 4 * *", timezone: nil) == "On the 4th of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 11 * *", timezone: nil) == "On the 11th of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 12 * *", timezone: nil) == "On the 12th of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 13 * *", timezone: nil) == "On the 13th of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 21 * *", timezone: nil) == "On the 21st of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 22 * *", timezone: nil) == "On the 22nd of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 23 * *", timezone: nil) == "On the 23rd of every month at 9:00")
        #expect(ScheduleWords.cadence(expression: "0 9 31 * *", timezone: nil) == "On the 31st of every month at 9:00")
    }

    @Test func unsupportedCronShowsRawExpression() {
        #expect(ScheduleWords.cadence(expression: "gibberish", timezone: nil) == "Cron: gibberish")
        #expect(ScheduleWords.cadence(expression: "*/30 */6 * * *", timezone: nil) == "Cron: */30 */6 * * *")
        #expect(ScheduleWords.cadence(expression: "0 9 * JAN *", timezone: "UTC") == "Cron: 0 9 * JAN * · UTC")
        #expect(ScheduleWords.cadence(expression: "0 9 * JAN *", timezone: nil) == "Cron: 0 9 * JAN *")
    }

    @Test func validation() {
        #expect(ScheduleWords.isValid(cron: "0 9 * * *"))
        #expect(ScheduleWords.isValid(cron: "0 9 * * 1-5"))
        #expect(ScheduleWords.isValid(cron: "0 9 * * MON-FRI"))
        #expect(ScheduleWords.isValid(cron: "*/15 * * * *"))
        #expect(!ScheduleWords.isValid(cron: "0 9 * *"))
        #expect(!ScheduleWords.isValid(cron: "60 * * * *"))
        #expect(!ScheduleWords.isValid(cron: "*/0 * * * *"))
        #expect(!ScheduleWords.isValid(cron: "0 9 * * 8"))
        #expect(!ScheduleWords.isValid(cron: "0 9 0 * *"))
        #expect(!ScheduleWords.isValid(cron: "gibberish"))
        // 0–7 is a legal range (0 and 7 are both Sunday); it normalizes to "all week".
        #expect(ScheduleWords.isValid(cron: "0 9 * * 0-7"))
    }
}
