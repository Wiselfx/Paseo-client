#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The setup sheet: what the worktree setup is doing right now, what it already did, and a way
/// to run it again. Opened from the quiet "Setup failed" / "Setting up…" line in the panel header.
struct WorkspaceSetupSheet: View {
    let session: HostSession
    let workspace: WorkspaceDescriptor

    @Environment(\.dismiss) private var dismiss
    @State private var isRerunning = false
    private let typography = ClaudeTypography()

    private var snapshot: WorkspaceSetupSnapshot? {
        session.setupObservation.snapshot(for: workspace.id)
    }

    private var capabilities: WorkspaceSetupObservationStore.Capabilities {
        session.setupObservation.capabilities
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Setup", close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusRow
                    detailCard
                    if let log = snapshot?.detail.log, !log.isEmpty { logCard(log) }
                    if let commands = snapshot?.detail.commands, !commands.isEmpty {
                        commandsList(commands)
                    }
                    if let blocked = snapshot?.blockedSource { blockedRow(blocked) }
                    if let error = snapshot?.error, !error.isEmpty {
                        Text(error)
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let message = session.setupObservation.error {
                        Text(message)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    runAgainButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .task { await session.setupObservation.refresh(workspace.id) }
    }

    // MARK: Rows

    private var statusRow: some View {
        HStack(spacing: 10) {
            StatusGlyph(status: snapshot?.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(typography.sans(15, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                if let branch = snapshot?.detail.branchName, !branch.isEmpty {
                    Text(branch)
                        .font(typography.mono(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if snapshot?.status == .running {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var statusText: String {
        switch snapshot?.status {
        case .running: "Setting up…"
        case .completed: "Setup completed"
        case .failed: "Setup failed"
        case .blocked: "Setup blocked"
        case .unknown(let raw): raw.capitalized
        case nil: "Setup"
        }
    }

    @ViewBuilder private var detailCard: some View {
        if let path = snapshot?.detail.worktreePath, !path.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ClaudeDivider()
                Text("Worktree")
                    .font(typography.sans(11, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .padding(.top, 6)
                Text(path)
                    .font(typography.mono(11))
                    .foregroundStyle(ClaudePalette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
        }
    }

    private func logCard(_ log: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(log)
                .font(typography.mono(11))
                .foregroundStyle(ClaudePalette.primaryInk)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
        .padding(10)
        .background(ClaudePalette.codeSurface, in: .rect(cornerRadius: 12))
    }

    private func commandsList(_ commands: [WorkspaceSetupCommand]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commands) { command in
                HStack(spacing: 10) {
                    CommandStatusGlyph(status: command.status, exitCode: command.exitCode)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(command.command)
                            .font(typography.mono(12))
                            .foregroundStyle(ClaudePalette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !command.log.isEmpty {
                            Text(command.log.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(typography.sans(11))
                                .foregroundStyle(ClaudePalette.secondaryInk)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    if let duration = command.durationMs {
                        Text("\(PaseoFormat.integer(duration)) ms")
                            .font(typography.mono(10))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                    }
                }
                .padding(.vertical, 6)
                if command.id != commands.last?.id {
                    ClaudeDivider().padding(.leading, 26)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func blockedRow(_ source: WorkspaceSetupBlockedSource) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClaudePalette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Blocked on change request")
                    .font(typography.sans(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Text("\(source.forge) #\(PaseoFormat.integer(source.number)) · \(source.headRepository)")
                    .font(typography.mono(11))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
    }

    private var runAgainButton: some View {
        Button {
            guard !isRerunning else { return }
            isRerunning = true
            Task {
                _ = await session.setupObservation.runSetup(workspace.id)
                isRerunning = false
            }
        } label: {
            if isRerunning {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            } else {
                Text("Run setup again")
                    .font(typography.sans(15, weight: .semibold))
                    .foregroundStyle(
                        capabilities.run ? ClaudePalette.background : ClaudePalette.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
        .background(
            ClaudePalette.ink.opacity(capabilities.run ? 1 : 0.35), in: .capsule)
        .disabled(!capabilities.run || isRerunning)
        .accessibilityLabel("Run setup again")
        .padding(.top, 4)
    }
}

private struct StatusGlyph: View {
    let status: WorkspaceSetupStatus?

    var body: some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small).tint(ClaudePalette.secondaryInk)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ClaudePalette.successInk)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(ClaudePalette.failureInk)
        case .blocked:
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(ClaudePalette.warning)
        default:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(ClaudePalette.tertiaryInk)
        }
    }
}

private struct CommandStatusGlyph: View {
    let status: WorkspaceSetupCommandStatus
    let exitCode: Int?

    var body: some View {
        Group {
            switch status {
            case .running:
                ProgressView().controlSize(.mini).tint(ClaudePalette.secondaryInk)
            case .completed:
                if (exitCode ?? 0) == 0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClaudePalette.successInk)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClaudePalette.failureInk)
                }
            case .failed:
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClaudePalette.failureInk)
            case .unknown:
                Image(systemName: "questionmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
        }
        .frame(width: 18, height: 18)
    }
}
#endif
