#if canImport(UIKit)
import Foundation
import Observation
import PaseoStore
import SwiftUI

/// The History screen's data: one pass over the lifecycle entries, dates parsed once, and
/// the filter applied to those precomputed rows (PLAN §RE, R-1). The view
/// rebuilds it when the entries change and when the debounced query changes.
@MainActor @Observable final class HistoryModel {
    struct Row: Identifiable, Equatable {
        let id: String
        let agent: AgentSnapshot
        let title: String
        let subtitle: String
        let date: Date?
        let archived: Bool
    }

    struct Group: Identifiable, Equatable {
        var id: String { label }
        let label: String
        let rows: [Row]
    }

    /// Every row, newest first, unfiltered.
    private var rows: [Row] = []
    private(set) var groups: [Group] = []
    /// The query the current groups were filtered with, so a rebuild keeps the filter.
    private var query = ""

    init() {}

    /// Rebuilds the rows for `entries` and re-applies the current filter.
    func rebuild(
        entries: [AgentSnapshot],
        workspaceTitles: [String: String],
        providerLabels: [String: String],
        modelLabel: (String, String) -> String
    ) {
        var built: [Row] = []
        built.reserveCapacity(entries.count)
        for agent in entries {
            let title = Self.title(for: agent)
            var parts: [String] = []
            if let workspaceId = agent.workspaceId, let workspace = workspaceTitles[workspaceId] {
                parts.append(workspace)
            }
            parts.append(providerLabels[agent.provider] ?? agent.provider)
            if let model = agent.model {
                parts.append(modelLabel(agent.provider, model))
            }
            let stamp = agent.lastUserMessageAt ?? agent.updatedAt
            built.append(
                Row(
                    id: agent.id,
                    agent: agent,
                    title: title,
                    subtitle: parts.joined(separator: " · "),
                    date: PaseoDate.parse(stamp),
                    archived: agent.archivedAt != nil
                ))
        }
        rows = built
        applyFilter(query)
    }

    /// Filters the precomputed rows and regroups them by day.
    func applyFilter(_ text: String) {
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched =
            trimmed.isEmpty ? rows : rows.filter { $0.title.localizedStandardContains(trimmed) }
        var today: [Row] = []
        var yesterday: [Row] = []
        var earlier: [Row] = []
        let calendar = Calendar.current
        let reference = Date(timeIntervalSince1970: 0)
        for row in matched {
            let date = row.date ?? reference
            if calendar.isDateInToday(date) {
                today.append(row)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(row)
            } else {
                earlier.append(row)
            }
        }
        groups = [
            Group(label: "Today", rows: today),
            Group(label: "Yesterday", rows: yesterday),
            Group(label: "Earlier", rows: earlier),
        ].filter { !$0.rows.isEmpty }
    }

    var isEmpty: Bool { rows.isEmpty }

    static func title(for agent: AgentSnapshot) -> String {
        let title = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false ? title : nil) ?? "New agent"
    }
}
#endif
