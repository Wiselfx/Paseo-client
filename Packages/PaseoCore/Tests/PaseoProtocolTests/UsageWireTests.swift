import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

/// `AgentUsage` on agent snapshots, `usage` on stream events, and the two usage-reports
/// wire protocols, decoded against fixtures captured from the sandbox daemon.
@Suite struct UsageWireTests {
    @Test func agentsSnapshotCarriesLastUsage() throws {
        let data = try Fixture.usageAgents()
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<FetchAgentsRequest.Response>.self, from: data
        ).payload
        #expect(response.entries.count == 5)
        let withWindow = response.entries.filter { $0.agent.lastUsage?.contextWindowUsedTokens != nil }
        #expect(withWindow.count == 5)
        // Every reporting window has both bounds and they are consistent.
        for entry in response.entries {
            let usage = try #require(entry.agent.lastUsage)
            let max = try #require(usage.contextWindowMaxTokens)
            let used = try #require(usage.contextWindowUsedTokens)
            #expect(used <= max)
            #expect(max > 0)
        }
        // The sandbox lead agent reports a session cost.
        let costs = response.entries.compactMap { $0.agent.lastUsage?.totalCostUsd }
        #expect(costs.contains { $0 > 0 })
    }

    @Test func turnCompletedEventDecodesUsage() throws {
        let data = try Fixture.usageTurnCompleted()
        let event = try JSONDecoder().decode(AgentStreamEvent.self, from: data)
        guard case .turnCompleted(let turnId, let usage) = event else {
            Issue.record("expected .turnCompleted, got \(event)")
            return
        }
        #expect(turnId == "eea87f84-25e6-47bd-89d8-137ef81ba04c")
        let value = try #require(usage)
        #expect(value.inputTokens == 79_621)
        #expect(value.cachedInputTokens == 227_072)
        #expect(value.outputTokens == 501)
        #expect(value.totalCostUsd == 0)
        #expect(value.contextWindowMaxTokens == nil)
        #expect(value.contextWindowUsedTokens == nil)
    }

    @Test func usageListReportsUpdateDecodesBothReports() throws {
        let decoder = JSONDecoder()
        let claude = try decoder.decode(
            SessionPayloadEnvelope<UsageListReportsUpdate>.self,
            from: Fixture.usageReportAvailable()).payload
        #expect(claude.requestId == "t16-reports")
        #expect(claude.report.sourceLabel == "Claude")
        #expect(claude.report.accountLabel == "fixture-account@example.invalid")

        guard case .available(let claudeReport) = claude.report.report else {
            Issue.record("expected an available claude report")
            return
        }
        #expect(claudeReport.planLabel == "Pro ai")
        #expect(claudeReport.windows.map(\.id) == ["five_hour", "weekly"])
        #expect(claudeReport.windows.first?.usedPct == 42)
        #expect(claudeReport.windows.first?.remainingPct == 58)
        #expect(claudeReport.windows.first?.shortLabel == "5h")
        #expect(claudeReport.windows.first?.summary == true)
        #expect(claudeReport.windows.first?.tone == .ok)

        let copilot = try decoder.decode(
            SessionPayloadEnvelope<UsageListReportsUpdate>.self,
            from: Fixture.usageReportSecond()).payload
        #expect(copilot.requestId == "t16-reports")
        #expect(copilot.report.accountLabel == nil)
        guard case .available(let copilotReport) = copilot.report.report else {
            Issue.record("expected an available copilot report")
            return
        }
        #expect(copilotReport.planLabel == "individual")
        #expect(copilotReport.windows.isEmpty)
        #expect(copilotReport.details?.map(\.id) == ["reset"])
        #expect(copilotReport.details?.first?.value == "2026-12-01")
    }

    @Test func usageListReportsResponseDecodes() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<UsageListReportsResponse>.self,
            from: Fixture.usageListReportsResponse()).payload
        #expect(response.requestId == "t16-reports")
        #expect(response.error == nil)
    }

    @Test func unavailableReportDecodesProblemKinds() throws {
        let decoder = JSONDecoder()
        let cases: [(name: String, reportJSON: String, expect: (UsageReport) -> Bool)] = [
            ("expired", """
            {"status":"unavailable","problem":{"kind":"expired","expiresAt":"2026-11-10T00:00:00.000Z","refreshedBy":"cli"}}
            """, {
                if case .unavailable(.expired(let expiresAt, let refreshedBy)) = $0 {
                    return expiresAt == "2026-11-10T00:00:00.000Z" && refreshedBy == "cli"
                }
                return false
            }),
            ("rejected", """
            {"status":"unavailable","problem":{"kind":"rejected","status":401}}
            """, {
                if case .unavailable(.rejected(let status, _)) = $0 { return status == 401 }
                return false
            }),
            ("no_quota", """
            {"status":"unavailable","problem":{"kind":"no_quota","detail":"nope"}}
            """, {
                if case .unavailable(.noQuota(let detail)) = $0 { return detail == "nope" }
                return false
            }),
            ("error", """
            {"status":"error","error":"boom"}
            """, {
                if case .failure(let message) = $0 { return message == "boom" }
                return false
            }),
        ]
        for testCase in cases {
            let data = inlineUpdate(report: testCase.reportJSON)
            let update = try decoder.decode(
                SessionPayloadEnvelope<UsageListReportsUpdate>.self, from: data).payload
            #expect(testCase.expect(update.report.report), "case \(testCase.name)")
        }
    }

    @Test func unknownProblemKindsAndTonesDoNotThrow() throws {
        let tone = try JSONDecoder().decode(ProviderUsageTone.self, from: Data("\"purple\"".utf8))
        #expect(tone == .unknown("purple"))
        let status = try JSONDecoder().decode(ProviderUsageStatus.self, from: Data("\"halfway\"".utf8))
        #expect(status == .unknown("halfway"))

        let unknownProblem = inlineUpdate(
            report: #"{"status":"unavailable","problem":{"kind":"alien","detail":"elsewhere"}}"#)
        let update = try JSONDecoder().decode(
            SessionPayloadEnvelope<UsageListReportsUpdate>.self, from: unknownProblem).payload
        guard case .unavailable(.unknown) = update.report.report else {
            Issue.record("expected unknown problem")
            return
        }
    }

    @Test func legacyProviderUsageListResponseDecodes() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ProviderUsageListResponse>.self,
            from: Fixture.providerUsageListResponse()).payload
        #expect(response.providers.map(\.providerId) == ["claude", "copilot"])
        let claude = response.providers[0]
        #expect(claude.status == .available)
        #expect(claude.planLabel == "Pro ai")
        #expect(claude.displayName == "Claude (fixture-account@example.invalid)")
        #expect(claude.windows.map(\.id) == ["five_hour", "weekly"])
        #expect(claude.windows.first?.tone == .ok)
        #expect(claude.details?.first?.value == "Disabled")
        let copilot = response.providers[1]
        #expect(copilot.status == .available)
        #expect(copilot.planLabel == "individual")
        #expect(copilot.windows.isEmpty)
        #expect(copilot.details?.first?.value == "2026-12-01")
    }
}
private func inlineUpdate(report: String) -> Data {
    let envelope = """
    {"type":"session","message":{"type":"usage.list_reports.update","payload":{"requestId":"r","report":{"id":"x","account":{},"fetchedAt":"2026-11-09T00:00:00.000Z","sourceId":"s","sourceLabel":"S","report":\(report)}}}}
    """
    return Data(envelope.utf8)
}
