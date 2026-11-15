import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Upstream `model.ts`, `tone.ts` and `balance-bar.tsx` ported into Core: the share a window shows,
/// its tone, the single value both the drawn text and the accessible label come from, and how a
/// report list merges.
@Suite
struct UsageModelTests {
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
    private static let english = Locale(identifier: "en_US")
    private static let now: Date = {
        ISO8601DateFormatter().date(from: "2026-11-09T08:00:00Z") ?? Date(timeIntervalSince1970: 0)
    }()

    private func window(_ json: String) throws -> ProviderUsageWindow {
        try JSONDecoder().decode(ProviderUsageWindow.self, from: Data(json.utf8))
    }

    private func balance(_ json: String) throws -> ProviderUsageBalance {
        try JSONDecoder().decode(ProviderUsageBalance.self, from: Data(json.utf8))
    }

    private func detail(_ json: String) throws -> ProviderUsageDetail {
        try JSONDecoder().decode(ProviderUsageDetail.self, from: Data(json.utf8))
    }

    /// ICU writes the gap before AM/PM as a narrow no-break space; compare words, not bytes.
    private static func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func iso(_ secondsFromNow: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = Self.utc
        return formatter.string(from: Self.now.addingTimeInterval(secondsFromNow))
    }

    private func entry(
        id: String, sourceId: String = "claude", fetchedAt: String = "2026-11-09T07:38:13.429Z",
        report: UsageReport? = nil, successfulAt: String? = nil,
        lastSuccessful: UsageReportEntry.LastSuccessful? = nil,
        loginErrors: [UsageReportEntry.LoginError]? = nil
    ) -> UsageReportEntry {
        UsageReportEntry(
            id: id,
            fetchedAt: fetchedAt,
            sourceId: sourceId,
            sourceLabel: sourceId.capitalized,
            report: report
                ?? .available(
                    AvailableUsageReport(windows: [], balances: nil, details: nil)),
            successfulAt: successfulAt,
            lastSuccessful: lastSuccessful,
            loginErrors: loginErrors)
    }

    // MARK: The share shown (model.ts:7-19)

    @Test func usedPercentFallsBackToTheRemainder() throws {
        let both = try window(#"{"id":"five_hour","label":"Session","usedPct":21,"remainingPct":79}"#)
        #expect(UsageModel.usedPercent(both) == 21)

        // The host that sends only the remainder is not a host with no figures.
        let remainingOnly = try window(#"{"id":"five_hour","label":"Session","remainingPct":79}"#)
        #expect(UsageModel.usedPercent(remainingOnly) == 21)

        let neither = try window(#"{"id":"five_hour","label":"Session"}"#)
        #expect(UsageModel.usedPercent(neither) == nil)
    }

    @Test func remainingFallsBackToTheUsedShare() throws {
        let usedOnly = try window(#"{"id":"five_hour","label":"Session","usedPct":21}"#)
        #expect(UsageModel.displayPercent(usedOnly, as: .remaining) == 79)
        #expect(UsageModel.displayPercent(usedOnly, as: .used) == 21)

        let remainingOnly = try window(#"{"id":"weekly","label":"Weekly","remainingPct":5}"#)
        #expect(UsageModel.displayPercent(remainingOnly, as: .remaining) == 5)
        #expect(UsageModel.displayPercent(remainingOnly, as: .used) == 95)
    }

    // MARK: Tone (tone.ts:5-12)

    @Test func toneIsTheHostsOwnOrDerivedFromTheShareUsed() throws {
        let given = try window(#"{"id":"a","label":"A","usedPct":10,"tone":"danger"}"#)
        #expect(UsageModel.windowTone(given) == .danger)

        let almostSpent = try window(#"{"id":"b","label":"B","usedPct":91}"#)
        #expect(UsageModel.windowTone(almostSpent) == .danger)
        let gettingFull = try window(#"{"id":"c","label":"C","remainingPct":30}"#)
        #expect(UsageModel.windowTone(gettingFull) == .warning)
        let comfortable = try window(#"{"id":"d","label":"D","usedPct":42}"#)
        #expect(UsageModel.windowTone(comfortable) == .default)
        let noFigures = try window(#"{"id":"e","label":"E"}"#)
        #expect(UsageModel.windowTone(noFigures) == .default)
    }

    // MARK: One value for the row and its label (window-bar.tsx:44-60, model.ts:21-33)

    @Test func theRowShowsTheSameValueItsLabelSpells() throws {
        let session = try window(
            #"{"id":"five_hour","label":"Session","shortLabel":"5h","usedPct":31,"resetsAt":"2026-11-09T10:00:00Z"}"#)
        let display = UsageModel.display(
            session, as: .used, now: Self.now, locale: Self.english, timeZone: Self.utc)
        #expect(display.label == "Session")
        #expect(display.percent == 31)
        #expect(display.value == "31% used")
        #expect(display.countdown == "resets in 2h")
        #expect(Self.plain(display.exactTime) == "10:00 AM")
        #expect(display.isAtRisk == false)

        // The accessible label is built from that same value, never a second computation.
        let exactTime = Self.plain(display.exactTime)
        #expect(
            UsageModel.windowRowLabel(
                pinLabel: "Pin Claude Session", value: display.value,
                trailing: [display.countdown, exactTime].compactMap { $0 }
                    .joined(separator: " · "))
                == "Pin Claude Session, 31% used · resets in 2h · 10:00 AM")
        #expect(
            UsageModel.windowRowLabel(pinLabel: "Pin Claude Session", value: display.value,
                trailing: nil) == "Pin Claude Session, 31% used")
    }

    @Test func aWindowWithoutFiguresPrintsTheDash() throws {
        let bare = try window(#"{"id":"weekly","label":"Weekly"}"#)
        let display = UsageModel.display(bare, as: .used, now: Self.now)
        #expect(display.value == "—")
        #expect(display.countdown == nil)
    }

    @Test func aQuotaThatWillNotLastShowsTheRunsOutWarningInsteadOfTheReset() throws {
        let atRisk = try window(
            #"{"id":"five_hour","label":"Session","usedPct":88,"shortfallPct":4,"runsOutAt":"2026-11-09T10:00:00Z","resetsAt":"2026-11-10T10:00:00Z"}"#)
        let display = UsageModel.display(
            atRisk, as: .used, now: Self.now, locale: Self.english, timeZone: Self.utc)
        #expect(display.isAtRisk)
        #expect(display.countdown == "runs out in 2h")
        // The exact reset time beside a runs-out warning would read as the moment it runs out.
        #expect(display.exactTime == nil)
    }

    @Test func retainedDataIgnoresARunsOutTimeThatHasPassed() throws {
        let stale = try window(
            #"{"id":"five_hour","label":"Session","usedPct":88,"shortfallPct":4,"runsOutAt":"2026-11-09T07:00:00Z","resetsAt":"2026-11-09T06:00:00Z"}"#)
        let display = UsageModel.display(stale, as: .used, retained: true, now: Self.now)
        #expect(display.isAtRisk == false)
        #expect(display.countdown == "Reset time passed")
    }

    // MARK: Balances (balance-bar.tsx:21-87)

    @Test func aBalanceAgainstALimitReadsAsUsedOverLimit() throws {
        let withLimit = try balance(
            #"{"id":"credits","label":"Credits","used":12.5,"limit":50,"unit":"usd"}"#)
        let display = UsageModel.display(withLimit, now: Self.now)
        #expect(display.label == "Credits")
        #expect(display.amountText == "$12.50 / $50.00")
        #expect(display.usedPct == 25)
    }

    @Test func aBalanceWithoutUsedDerivesItFromTheRemainder() throws {
        let remainingOnly = try balance(
            #"{"id":"credits","label":"Credits","remaining":40,"limit":50,"unit":"credits"}"#)
        #expect(UsageModel.amountText(remainingOnly) == "10 / 50")
        #expect(UsageModel.usedShare(remainingOnly) == 20)
    }

    @Test func aBalanceWithoutALimitPrintsWhatIsLeft() throws {
        let noLimit = try balance(
            #"{"id":"credits","label":"Credits","remaining":12.25,"unit":"credits"}"#)
        #expect(UsageModel.amountText(noLimit) == "12.25 left")
        #expect(UsageModel.usedShare(noLimit) == nil)

        let usedOnly = try balance(#"{"id":"credits","label":"Credits","used":3,"unit":"usd"}"#)
        #expect(UsageModel.amountText(usedOnly) == "$3.00")

        let bare = try balance(#"{"id":"credits","label":"Credits","unit":"credits"}"#)
        #expect(UsageModel.amountText(bare) == "—")
    }

    // MARK: A report's content (model.ts:208-239)

    @Test func anAvailableReportOwnsItsValuesAndFreshness() throws {
        let session = try window(#"{"id":"five_hour","label":"Session","usedPct":31}"#)
        let report = entry(
            id: "claude:one",
            report: .available(
                AvailableUsageReport(
                    planLabel: "Pro", windows: [session],
                    details: [try detail(#"{"id":"extra","label":"Extra","value":"Off"}"#)])),
            successfulAt: "2026-11-09T07:39:00Z")
        let content = UsageModel.resolve(report, now: Self.now)
        #expect(content.windows.map(\.id) == ["five_hour"])
        #expect(content.planLabel == "Pro")
        // COMPAT(usageSuccessfulAt): the successful completion time, not the attempt time.
        #expect(content.successfulAt == "2026-11-09T07:39:00Z")
        #expect(content.retained == false)
        #expect(content.messages.isEmpty)
    }

    @Test func aFailedReportKeepsItsLastSuccessfulContentAndSaysWhy() throws {
        let retainedWindow = try window(#"{"id":"five_hour","label":"Session","usedPct":31}"#)
        let snapshot = UsageReportEntry.LastSuccessful(
            fetchedAt: "2026-11-09T07:00:00Z",
            report: AvailableUsageReport(windows: [retainedWindow]))
        let report = entry(
            id: "claude:one",
            fetchedAt: "2026-11-09T08:00:00Z",
            report: .unavailable(problem: .noQuota(detail: "Quota exhausted")),
            lastSuccessful: snapshot)
        let content = UsageModel.resolve(report, now: Self.now)
        #expect(content.retained)
        #expect(content.windows.map(\.id) == ["five_hour"])
        // Freshness is the last success, never the failed attempt.
        #expect(content.successfulAt == "2026-11-09T07:00:00Z")
        #expect(content.messages == ["Quota exhausted"])
    }

    @Test func aFailedReportWithoutHistoryShowsOnlyTheReason() throws {
        let report = entry(
            id: "copilot:one", report: .failure(error: "HTTP 500"))
        let content = UsageModel.resolve(report, now: Self.now)
        #expect(content.windows.isEmpty)
        #expect(content.successfulAt == nil)
        #expect(content.retained == false)
        #expect(content.messages == ["HTTP 500"])
    }

    @Test func perHarnessLoginErrorsAreEachNamed() throws {
        let report = entry(
            id: "claude:one",
            report: .unavailable(problem: .noQuota(detail: "")),
            loginErrors: [
                .init(
                    harness: "claude",
                    report: .unavailable(
                        problem: .expired(
                            expiresAt: "2026-11-09T07:00:00Z", refreshedBy: nil))),
                .init(harness: "codex", report: .failure(error: "No credentials")),
            ])
        let content = UsageModel.resolve(report, now: Self.now)
        #expect(
            content.messages == [
                "claude: Login expired 1h ago. Sign in again.",
                "codex: No credentials",
            ])
    }

    // MARK: Merging the list (model.ts:35-99)

    @Test func aStreamedReportReplacesItsOldCopyOnlyWhenNewer() {
        let old = entry(id: "a", fetchedAt: "2026-11-09T07:00:00Z")
        let newer = entry(id: "a", fetchedAt: "2026-11-09T08:00:00Z")
        #expect(UsageModel.upsertReport([old], old).first?.fetchedAt == old.fetchedAt)
        #expect(UsageModel.upsertReport([old], newer).first?.fetchedAt == newer.fetchedAt)
        // A copy fetched after the streamed one stays.
        #expect(UsageModel.upsertReport([newer], old).first?.fetchedAt == newer.fetchedAt)
        // A new report is appended.
        let added = UsageModel.upsertReport([old], entry(id: "b"))
        #expect(added.map(\.id) == ["a", "b"])
        #expect(UsageModel.upsertReport(nil, added[0]).map(\.id) == ["a"])
    }

    @Test func settlingKeepsTheDisplayedOrderAndDropsWhatTheHostLost() {
        let first = entry(id: "a", fetchedAt: "2026-11-09T07:00:00Z")
        let second = entry(id: "b", fetchedAt: "2026-11-09T07:00:00Z")
        // The finished list comes back in fetch-completion order.
        let finished = [entry(id: "b"), entry(id: "a"), entry(id: "c")]
        let settled = UsageModel.settleReports(shown: [first, second], finished: finished)
        #expect(settled.map(\.id) == ["a", "b", "c"])

        // A report the host no longer has leaves the list.
        let dropped = UsageModel.settleReports(shown: [first, second], finished: [finished[1]])
        #expect(dropped.map(\.id) == ["a"])
    }

    @Test func settlingKeepsANewerCopyFetchedWhileTheListStreamed() {
        let refreshed = entry(id: "a", fetchedAt: "2026-11-09T08:00:00Z")
        let staleArrival = entry(id: "a", fetchedAt: "2026-11-09T07:00:00Z")
        let settled = UsageModel.settleReports(shown: [refreshed], finished: [staleArrival])
        #expect(settled.first?.fetchedAt == refreshed.fetchedAt)
    }

    @Test func replacingOneReportLeavesTheRestAlone() {
        let a = entry(id: "a")
        let b = entry(id: "b")
        let refreshed = entry(id: "a", fetchedAt: "2026-11-09T09:00:00Z")
        #expect(UsageModel.replaceReport([a, b], reportId: "a", refreshed: refreshed)
            .map(\.id) == ["a", "b"])
        #expect(UsageModel.replaceReport([a, b], reportId: "a", refreshed: nil).map(\.id) == ["b"])
    }
}
