#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// M7f — the subagents track: a quiet pill under the header (provider subagents) and a sheet
/// that lists them with status; rows open the read-only timeline.

/// Counts the pill reports: the ticket's wording is `N subagents`, `N working`, `N failed`.
/// Provider rows carry no attention/needs-input signal, so there is no "needs input" mark here.
struct SubagentTrackPill: View {
    let items: [ProviderSubagent]
    let action: () -> Void

    private let typography = ClaudeTypography()

    var running: Int { items.filter { $0.status == .running }.count }
    var failed: Int { items.filter { $0.status == .failed }.count }

    var text: String {
        var parts: [String] = []
        if running > 0 { parts.append("\(running) working") }
        if failed > 0 { parts.append("\(failed) failed") }
        if parts.isEmpty {
            return items.count == 1 ? "1 subagent" : "\(items.count) subagents"
        }
        return parts.joined(separator: " · ")
    }

    var accessibilityText: String {
        var parts: [String] = []
        if running > 0 { parts.append("\(running) working") }
        if failed > 0 { parts.append("\(failed) failed") }
        if parts.isEmpty { parts.append(items.count == 1 ? "1 subagent" : "\(items.count) subagents") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "person.2")
                    .font(.system(size: 11, weight: .medium))
                Text(text)
                    .font(typography.sans(13))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
            .foregroundStyle(failed > 0 ? ClaudePalette.failureInk : ClaudePalette.secondaryInk)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(ClaudePalette.chip, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transcript.subagents")
        .accessibilityLabel("Subagents: \(accessibilityText)")
    }
}

/// Provider subagent status: dot color and sentence-case label.
enum SubagentStatusWord {
    static func label(_ status: ProviderSubagent.Status) -> String {
        switch status {
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .canceled: "Canceled"
        case .unknown: "Unknown"
        }
    }

    static func dot(_ status: ProviderSubagent.Status) -> Color {
        switch status {
        case .running: ClaudePalette.orange
        case .completed: ClaudePalette.successInk
        case .failed: ClaudePalette.failureInk
        case .canceled, .unknown: ClaudePalette.tertiaryInk
        }
    }
}

/// The sheet that lists provider subagents with status. Rows open a read-only timeline.
/// "Archive finished" hides every non-running row for this session (app-side only, in memory —
/// provider rows die with the provider session).
struct ChatSubagentsSheet: View {
    let subagents: ConversationSubagents
    let typography: ClaudeTypography
    @Binding var hiddenIds: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var pushTarget: ProviderSubagent?
    @State private var confirmArchiveFinished = false

    private var items: [ProviderSubagent] {
        subagents.items.filter { !hiddenIds.contains($0.id) }
    }

    private var finishedCount: Int {
        items.filter { $0.status != .running }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if subagents.isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                        Text("No subagents")
                            .font(typography.serif(19))
                            .foregroundStyle(ClaudePalette.ink)
                        Text("Subagents your provider runs for this agent appear here.")
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(items) { item in
                                subagentRow(item)
                                if item.id != items.last?.id {
                                    ClaudeDivider().padding(.leading, 44)
                                }
                            }
                            if let error = subagents.error {
                                Text(error)
                                    .font(typography.sans(12))
                                    .foregroundStyle(ClaudePalette.failureInk)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .background(ClaudePalette.background)
            .navigationTitle("Subagents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if finishedCount > 0 {
                    VStack(spacing: 0) {
                        ClaudeDivider()
                        Button("Archive finished") {
                            confirmArchiveFinished = true
                        }
                        .font(typography.sans(15))
                        .foregroundStyle(ClaudePalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(.rect)
                    }
                    .background(ClaudePalette.panel)
                }
            }
            .navigationDestination(item: $pushTarget) { subagent in
                ChatSubagentTimelineView(
                    subagents: subagents, subagent: subagent, typography: typography)
            }
            .confirmationDialog(
                "Archive finished subagents?",
                isPresented: $confirmArchiveFinished,
                titleVisibility: .visible
            ) {
                Button("Archive finished", role: .destructive) {
                    hiddenIds.formUnion(items.filter { $0.status != .running }.map(\.id))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Finished rows disappear until the app is relaunched.")
            }
            .task { await subagents.load() }
            .presentationDetents([.medium, .large])
        }
    }

    private func subagentRow(_ item: ProviderSubagent) -> some View {
        Button {
            Haptics.selection()
            pushTarget = item
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(SubagentStatusWord.dot(item.status))
                    .frame(width: 8, height: 8)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle(item))
                        .font(typography.sans(15, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    if let subtitle = rowSubtitle(item) {
                        Text(subtitle)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(SubagentStatusWord.label(item.status))
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rowTitle(item)), \(SubagentStatusWord.label(item.status))")
    }

    private func rowTitle(_ item: ProviderSubagent) -> String {
        item.title ?? item.description ?? item.provider
    }

    private func rowSubtitle(_ item: ProviderSubagent) -> String? {
        if item.title != nil {
            return item.description ?? item.subtitle
        }
        return item.subtitle
    }
}

/// One provider subagent's timeline, read-only: the tail page, plain rows.
struct ChatSubagentTimelineView: View {
    let subagents: ConversationSubagents
    let subagent: ProviderSubagent
    let typography: ClaudeTypography

    @State private var rows: [ProviderSubagentTimelineRequest.Response.Row] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if loading && rows.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let error {
                    VStack(spacing: 10) {
                        Text(error)
                            .font(typography.sans(14))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .font(typography.sans(15, weight: .medium))
                            .foregroundStyle(ClaudePalette.ink)
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background(ClaudePalette.chip, in: .capsule)
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity)
                } else if rows.isEmpty {
                    Text("No timeline rows yet.")
                        .font(typography.sans(14))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .padding(.top, 60)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(rows, id: \.seq) { row in
                        timelineRow(row)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(ClaudePalette.background)
        .navigationTitle(rowTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var rowTitle: String {
        subagent.title ?? subagent.description ?? subagent.provider
    }

    private func load() async {
        loading = true
        if let page = await subagents.timelinePage(for: subagent.id, limit: 50) {
            rows = page.rows
            error = nil
        } else {
            error = subagents.error ?? "Couldn't load the timeline."
        }
        loading = false
    }

    @ViewBuilder
    private func timelineRow(_ row: ProviderSubagentTimelineRequest.Response.Row) -> some View {
        switch row.item {
        case .userMessage(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("TASK")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(ClaudePalette.tertiaryInk)
                Text(message.text)
                    .font(typography.serif(15))
                    .foregroundStyle(ClaudePalette.primaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .assistantMessage(let message):
            Text(message.text)
                .font(typography.serif(14))
                .foregroundStyle(ClaudePalette.primaryInk)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        case .reasoning(let reasoning):
            Text(reasoning.text.replacingOccurrences(of: "\n", with: " "))
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.tertiaryInk)
                .lineLimit(2)
        case .toolCall(let call):
            ToolCallLine(call: call, typography: typography)
        case .todo(let list):
            Text("Todo · \(PaseoFormat.integer(list.items.count)) item\(list.items.count == 1 ? "" : "s")")
                .font(typography.mono(12))
                .foregroundStyle(ClaudePalette.tertiaryInk)
        case .error(let message):
            Text(message)
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.failureInk)
        case .notification(let level, let message):
            Text("\(level) · \(message)")
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.tertiaryInk)
        case .compaction:
            Text("Compacted")
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.tertiaryInk)
        case .unknown:
            Text("Unknown item")
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.tertiaryInk)
        }
    }
}

/// A one-line `verb · argument` for a tool call, e.g. `Read · src/server.ts`.
private struct ToolCallLine: View {
    let call: ToolCall
    let typography: ClaudeTypography

    private var presentation: ToolCallPresentation { ToolCallPresentation(call) }

    var body: some View {
        HStack(spacing: 8) {
            Text(presentation.title)
                .font(typography.mono(12))
                .foregroundStyle(ClaudePalette.tertiaryInk)
            if let subtitle = presentation.subtitle {
                Text(subtitle)
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
