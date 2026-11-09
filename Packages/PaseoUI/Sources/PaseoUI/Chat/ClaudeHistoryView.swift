#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The History screen (M7 §3): every agent on this host, newest first, grouped by day — Today,
/// Yesterday, Earlier — with a title filter. Active agents only: the wire would carry archived
/// ones (`FetchAgentsRequest` entries include `archivedAt`), but HostSession discards them at
/// ingest and there is no unarchive RPC, so an archived agent can never be re-opened from here.
/// Tapping a row opens the agent.
struct ClaudeHistoryView: View {
    let session: HostSession
    let onClose: () -> Void
    /// Tap row → the sidebar dismisses this sheet and selects the agent.
    let onOpenAgent: (String) -> Void

    private let typography = ClaudeTypography()
    @State private var query = ""

    private var agents: [AgentSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return session.agents }
        return session.agents.filter { title(for: $0).lowercased().contains(trimmed) }
    }

    private var groups: [HistoryGroup] {
        let calendar = Calendar.current
        var today: [AgentSnapshot] = [], yesterday: [AgentSnapshot] = [], earlier: [AgentSnapshot] = []
        for agent in agents {
            let reference = Date(timeIntervalSince1970: 0)
            let date = PaseoDate.parse(agent.lastUserMessageAt ?? agent.updatedAt) ?? reference
            if calendar.isDateInToday(date) {
                today.append(agent)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(agent)
            } else {
                earlier.append(agent)
            }
        }
        return [
            HistoryGroup(label: "Today", agents: today),
            HistoryGroup(label: "Yesterday", agents: yesterday),
            HistoryGroup(label: "Earlier", agents: earlier),
        ].filter { !$0.agents.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            content
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        ZStack {
            Text("History")
                .font(typography.serif(19, relativeTo: .headline, weight: .semibold))
            HStack {
                Button {
                    Haptics.selection()
                    onClose()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 19, weight: .light))
                        .frame(width: 42, height: 42)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(ClaudePalette.secondaryInk)
            TextField("Search history", text: $query)
                .font(typography.sans(15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("history.search")
            if !query.isEmpty {
                Button {
                    Haptics.selection()
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(ClaudePalette.chip, in: .rect(cornerRadius: 11))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var content: some View {
        if agents.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
                Text(query.isEmpty ? "No agents yet" : "No matches")
                    .font(typography.sans(15, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                if !query.isEmpty {
                    Text("Try a different title.")
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        Text(group.label.uppercased())
                            .font(typography.sans(11, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        ForEach(Array(group.agents.enumerated()), id: \.element.id) { index, agent in
                            if index > 0 {
                                ClaudeDivider().padding(.leading, 20)
                            }
                            row(agent)
                        }
                    }
                }
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(_ agent: AgentSnapshot) -> some View {
        Button {
            Haptics.selection()
            onOpenAgent(agent.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: agent))
                        .font(typography.sans(15, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle(for: agent))
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(relativeAge(agent.lastUserMessageAt ?? agent.updatedAt))
                    .font(typography.mono(11))
                    .foregroundStyle(ClaudePalette.captionInk)
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open agent \(title(for: agent))")
    }

    private func title(for agent: AgentSnapshot) -> String {
        let title = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false ? title : nil) ?? "New agent"
    }

    /// `workspace · provider · model`, middle-truncated.
    private func subtitle(for agent: AgentSnapshot) -> String {
        var parts: [String] = []
        if let workspaceId = agent.workspaceId,
           let workspace = session.workspaceDirectory.groups.flatMap(\.workspaces)
           .first(where: { $0.id == workspaceId }) {
            parts.append(workspace.title?.isEmpty == false ? workspace.title! : workspace.name)
        }
        parts.append(session.agentControl.provider(agent.provider)?.label ?? agent.provider)
        if let model = agent.model {
            let label = session.agentControl.models(forProvider: agent.provider)
                .first(where: { $0.id == model })?.label
            parts.append(label ?? model)
        }
        return parts.joined(separator: " · ")
    }

    private func relativeAge(_ iso: String) -> String {
        guard let date = PaseoDate.parse(iso) else { return "" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 2 * 86_400 { return "1d" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400))d" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private struct HistoryGroup: Identifiable {
        var id: String { label }
        var label: String
        var agents: [AgentSnapshot]
    }
}
#endif
