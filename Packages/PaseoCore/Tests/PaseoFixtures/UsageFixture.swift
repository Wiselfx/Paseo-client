import Foundation

/// Usage capture from the live sandbox daemon (agent 1c51ee58-…), scrubbed of account emails and
/// absolute paths. The reports fixtures carry `requestId` `t16-reports`.
extension Fixture {
    /// `Fixtures/usage/fetch_agents_response.json` — agents with `lastUsage` on every entry.
    public static func usageAgents() throws -> Data {
        try data("fetch_agents_response", area: "usage")
    }

    /// `Fixtures/usage/turn_completed.json` — a `turn_completed` stream event carrying `usage`.
    public static func usageTurnCompleted() throws -> Data {
        try data("turn_completed", area: "usage")
    }

    /// `Fixtures/usage/usage_list_reports_update_claude.json` — one streamed report (available).
    public static func usageReportAvailable() throws -> Data {
        try data("usage_list_reports_update_claude", area: "usage")
    }

    /// `Fixtures/usage/usage_list_reports_update_copilot.json` — second streamed report.
    public static func usageReportSecond() throws -> Data {
        try data("usage_list_reports_update_copilot", area: "usage")
    }

    /// `Fixtures/usage/usage_list_reports_response.json` — the terminal response frame.
    public static func usageListReportsResponse() throws -> Data {
        try data("usage_list_reports_response", area: "usage")
    }

    /// `Fixtures/usage/provider_usage_list_response.json` — the legacy per-provider snapshot.
    public static func providerUsageListResponse() throws -> Data {
        try data("provider_usage_list_response", area: "usage")
    }
}
