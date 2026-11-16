#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The setup sheet: what the worktree setup is doing right now, what it already did, and a way
/// to run it again. Opened from the quiet "Setup failed" / "Setting up…" line in the panel header.
struct WorkspaceSetupSheet: View {
    let session: HostSession
    let workspace: WorkspaceDescriptor

    @State private var isRerunning = false

    private var snapshot: WorkspaceSetupSnapshot? {
        session.setupObservation.snapshot(for: workspace.id)
    }

    private var capabilities: WorkspaceSetupObservationStore.Capabilities {
        session.setupObservation.capabilities
    }

    var body: some View {
        SheetScaffold("Setup", detents: .mediumLarge) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    statusRow
                    detailCard
                    if let log = snapshot?.detail.log, !log.isEmpty { logCard(log) }
                    if let commands = snapshot?.detail.commands, !commands.isEmpty {
                        commandsList(commands)
                    }
                    if let blocked = snapshot?.blockedSource { blockedRow(blocked) }
                    if let error = snapshot?.error, !error.isEmpty {
                        InlineBanner(.failure, title: error)
                    }
                    if let message = session.setupObservation.error {
                        InlineBanner(.failure, title: message)
                    }
                    runAgainButton
                }
                .padding(.horizontal, Space.lg)
                .padding(.bottom, Space.lg)
            }
            .scrollIndicators(.hidden)
        }
        .task { await session.setupObservation.refresh(workspace.id) }
    }

    // MARK: Rows

    private var statusRow: some View {
        HStack(spacing: 10) {
            StatusGlyph(status: snapshot?.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.paseo(.callout, weight: .medium))
                    .foregroundStyle(Palette.ink)
                if let branch = snapshot?.detail.branchName, !branch.isEmpty {
                    Text(branch)
                        .font(.paseo(.codeSmall))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if snapshot?.status == .running {
                InlineProgress()
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
                    .font(.paseo(.caption2, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.top, 6)
                Text(path)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.ink)
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
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
        .padding(10)
        .background(Palette.codeSurface, in: .rect(cornerRadius: Radius.md))
    }

    private func commandsList(_ commands: [WorkspaceSetupCommand]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commands) { command in
                HStack(spacing: 10) {
                    CommandStatusGlyph(status: command.status, exitCode: command.exitCode)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(command.command)
                            .font(.paseo(.codeSmall))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !command.log.isEmpty {
                            Text(command.log.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.paseo(.caption2))
                                .foregroundStyle(Palette.secondaryInk)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    if let duration = command.durationMs {
                        Text("\(PaseoFormat.integer(duration)) ms")
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.tertiaryInk)
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
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Blocked on change request")
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text("\(source.forge) #\(String(source.number)) · \(source.headRepository)")
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
    }

    private var runAgainButton: some View {
        Button("Run setup again") {
            guard !isRerunning else { return }
            isRerunning = true
            Task {
                _ = await session.setupObservation.runSetup(workspace.id)
                isRerunning = false
            }
        }
        .buttonStyle(.paseoPrimary(isWorking: isRerunning))
        .disabled(!capabilities.run)
        .accessibilityLabel("Run setup again")
        .padding(.top, Space.xs)
    }
}

private struct StatusGlyph: View {
    let status: WorkspaceSetupStatus?

    var body: some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small).tint(Palette.secondaryInk)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.successInk)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Palette.failureInk)
        case .blocked:
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(Palette.warning)
        default:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(Palette.tertiaryInk)
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
                ProgressView().controlSize(.mini).tint(Palette.secondaryInk)
            case .completed:
                if (exitCode ?? 0) == 0 {
                    Image(systemName: "checkmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.successInk)
                } else {
                    Image(systemName: "xmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.failureInk)
                }
            case .failed:
                Image(systemName: "xmark")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.failureInk)
            case .unknown:
                Image(systemName: "questionmark")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(width: 18, height: 18)
    }
}
#endif
