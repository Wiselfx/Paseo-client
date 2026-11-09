#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The "Terminal" page of the workspace panel (`WorkspacePanel`).
///
/// Chips along the top switch between the workspace's terminals (or create one); the body is a
/// SwiftTerm-backed emulator fed by `TerminalsStore`'s byte stream; below it, the workspace's
/// configured `paseo.json` scripts (start/stop, lifecycle, health, port). Everything talks to
/// the daemon through `session.terminals` — never through the client directly.
struct WorkspaceTerminalsView: View {
    let session: HostSession
    let workspace: WorkspaceDescriptor

    @State private var selectedTerminalId: String?
    @State private var isCreating = false
    @State private var busyScripts: Set<String> = []
    @State private var exitMessage: String?
    @State private var exitGeneration = 0
    @Environment(\.openURL) private var openURL

    private let typography = ClaudeTypography()

    private var store: TerminalsStore { session.terminals }
    private var workspaceId: String { workspace.id }

    var body: some View {
        let terminals = orderedTerminals
        VStack(spacing: 0) {
            if let error = store.error { errorBanner(error) }
            terminalPicker(terminals)
            ClaudeDivider()
            terminalArea(terminals)
            let scripts = store.scripts(in: workspaceId)
            if !scripts.isEmpty || store.loadingScriptWorkspaces.contains(workspaceId) {
                ClaudeDivider()
                scriptsSection(scripts)
            }
        }
        .background(ClaudePalette.background)
        .task { await store.open(workspaceId: workspaceId, cwd: workspace.cwd) }
        .onAppear {
            if selectedTerminalId == nil || !terminalIds.contains(selectedTerminalId ?? "") {
                selectedTerminalId = terminalIds.first
            }
        }
        .onChange(of: terminalIds) { _, ids in
            if let selectedTerminalId, ids.contains(selectedTerminalId) { return }
            selectedTerminalId = ids.first
            exitMessage = nil
        }
    }

    // MARK: Terminals

    private var terminalIds: [String] {
        orderedTerminals.map(\.id)
    }

    /// Newest first when the daemon sent timestamps; otherwise the daemon's order.
    private var orderedTerminals: [TerminalInfo] {
        let all = store.terminals(in: workspaceId)
        return all.sorted { lhs, rhs in
            switch (lhs.createdAt.flatMap(PaseoDate.parse), rhs.createdAt.flatMap(PaseoDate.parse)) {
            case let (left?, right?): return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.name < rhs.name
            }
        }
    }

    private func displayName(_ terminal: TerminalInfo) -> String {
        if let title = terminal.title, !title.isEmpty, title != terminal.name {
            return title
        }
        return terminal.name
    }

    private func terminalPicker(_ terminals: [TerminalInfo]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(terminals) { terminal in
                    terminalChip(terminal)
                }
                newTerminalButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 48)
    }

    private func terminalChip(_ terminal: TerminalInfo) -> some View {
        let isSelected = terminal.id == selectedTerminalId
        return Button {
            Haptics.selection()
            if selectedTerminalId != terminal.id {
                selectedTerminalId = terminal.id
                exitMessage = nil
            }
        } label: {
            HStack(spacing: 6) {
                PaseoStatusDot(kind: dotKind(for: terminal))
                Text(displayName(terminal))
                    .font(typography.sans(13))
                    .foregroundStyle(isSelected ? ClaudePalette.ink : ClaudePalette.secondaryInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isSelected ? ClaudePalette.chip : Color.clear, in: .capsule)
            .overlay(
                Capsule().strokeBorder(
                    ClaudePalette.cardBorder, lineWidth: isSelected ? 0 : 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Terminal \(displayName(terminal))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func dotKind(for terminal: TerminalInfo) -> PaseoStatusDot.Kind {
        switch terminal.activityBucket {
        case .needsInput: return .needsInput
        case .attention: return .done
        case .running: return .running
        case nil: return .idle
        }
    }

    private var newTerminalButton: some View {
        Button {
            Haptics.selection()
            guard !isCreating else { return }
            isCreating = true
            Task {
                let created = await store.createTerminal(in: workspaceId, cwd: workspace.cwd)
                isCreating = false
                if let created {
                    selectedTerminalId = created.id
                    exitMessage = nil
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isCreating {
                    ProgressView().controlSize(.mini).tint(ClaudePalette.secondaryInk)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                Text("New").font(typography.sans(13))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(ClaudePalette.ink)
            .overlay(
                Capsule().strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
        .accessibilityLabel("New terminal")
    }

    private func terminalArea(_ terminals: [TerminalInfo]) -> some View {
        ZStack {
            if !store.isSupported {
                statusMessage(
                    "Update the host to view terminals.",
                    detail: "This daemon predates the terminal replay protocol.")
            } else if let selectedTerminalId, terminals.contains(where: { $0.id == selectedTerminalId }) {
                PaseoTerminalView(
                    store: store,
                    terminalId: selectedTerminalId,
                    onExit: { message in exitMessage = exitLine(for: message) }
                )
                .id("\(selectedTerminalId)-\(exitGeneration)")
                if let exitMessage {
                    exitOverlay(exitMessage)
                }
            } else if terminals.isEmpty {
                emptyState
            } else {
                // The selected id is stale during the same frame the data refreshes.
                ProgressView().tint(ClaudePalette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("No terminals yet")
                .font(typography.sans(15, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
            Text("Start one to run commands in this workspace.")
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .multilineTextAlignment(.center)
            Button {
                Haptics.selection()
                guard !isCreating else { return }
                isCreating = true
                Task {
                    let created = await store.createTerminal(in: workspaceId, cwd: workspace.cwd)
                    isCreating = false
                    if let created {
                        selectedTerminalId = created.id
                        exitMessage = nil
                    }
                }
            } label: {
                Text("New terminal")
                    .font(typography.sans(15, weight: .medium))
                    .foregroundStyle(ClaudePalette.background)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(ClaudePalette.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isCreating)
        }
        .padding(.horizontal, 32)
    }

    private func statusMessage(_ title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "info")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(ClaudePalette.secondaryInk)
            Text(title)
                .font(typography.sans(15, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
    }

    private func exitLine(for error: String?) -> String {
        guard let error else { return "The terminal ended." }
        return "\(error)\nThe process may still be running."
    }

    private func exitOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button {
                    Haptics.selection()
                    exitMessage = nil
                    exitGeneration += 1
                } label: {
                    Text("Reattach")
                        .font(typography.sans(14, weight: .medium))
                        .foregroundStyle(ClaudePalette.background)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(ClaudePalette.ink, in: .capsule)
                }
                .buttonStyle(.plain)
                Button {
                    exitMessage = nil
                } label: {
                    Text("Dismiss")
                        .font(typography.sans(14, weight: .medium))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .overlay(Capsule().strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(ClaudePalette.panel, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
        .padding(.horizontal, 32)
    }

    // MARK: Scripts

    private func scriptsSection(_ scripts: [WorkspaceScript]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Scripts")
                    .font(typography.sans(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Spacer(minLength: 8)
                if store.loadingScriptWorkspaces.contains(workspaceId) {
                    ProgressView().controlSize(.small).tint(ClaudePalette.secondaryInk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(scripts) { script in
                        if script.id != scripts.first?.id { ClaudeDivider().padding(.leading, 40) }
                        scriptRow(script)
                    }
                }
            }
            .frame(maxHeight: 168)
        }
        .padding(.bottom, 4)
    }

    private func scriptRow(_ script: WorkspaceScript) -> some View {
        HStack(spacing: 12) {
            PaseoStatusDot(kind: scriptDotKind(script))
            VStack(alignment: .leading, spacing: 2) {
                Text(script.scriptName)
                    .font(typography.sans(15))
                    .foregroundStyle(ClaudePalette.ink)
                    .lineLimit(1)
                Text(scriptSubtitle(script))
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if script.lifecycle == .running, let url = script.preferredURL, let target = URL(string: url) {
                Button {
                    Haptics.selection()
                    openURL(target)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(script.scriptName) in browser")
            }
            if let terminalId = script.terminalId, terminalIds.contains(terminalId) {
                Button {
                    Haptics.selection()
                    selectedTerminalId = terminalId
                    exitMessage = nil
                } label: {
                    Text("View")
                        .font(typography.sans(13, weight: .medium))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .frame(height: 30)
                        .padding(.horizontal, 12)
                        .overlay(Capsule().strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show terminal for \(script.scriptName)")
            }
            scriptActionButton(script)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    private func scriptSubtitle(_ script: WorkspaceScript) -> String {
        var parts: [String] = []
        switch script.lifecycle {
        case .running: parts.append("Running")
        case .stopped: parts.append("Stopped")
        case .unknown: parts.append("Unknown")
        }
        switch script.health {
        case .healthy: parts.append("healthy")
        case .unhealthy: parts.append("unhealthy")
        case .unknown, .none: break
        }
        if let port = script.port { parts.append(":\(port)") }
        if script.lifecycle == .stopped, let code = script.exitCode, code != 0 {
            parts.append("exit \(code)")
        }
        return parts.joined(separator: " · ")
    }

    private func scriptDotKind(_ script: WorkspaceScript) -> PaseoStatusDot.Kind {
        switch script.lifecycle {
        case .running:
            return script.health == .unhealthy ? .failed : .running
        case .stopped:
            return (script.exitCode ?? 0) != 0 ? .failed : .idle
        case .unknown:
            return .idle
        }
    }

    private func scriptActionButton(_ script: WorkspaceScript) -> some View {
        let busy = busyScripts.contains(script.scriptName)
        let isRunning = script.lifecycle == .running
        return Button {
            Haptics.selection()
            busyScripts.insert(script.scriptName)
            Task {
                if isRunning {
                    _ = await store.stopScript(script.scriptName, in: workspaceId)
                } else {
                    _ = await store.startScript(script.scriptName, in: workspaceId)
                }
                busyScripts.remove(script.scriptName)
            }
        } label: {
            Group {
                if busy {
                    ProgressView().controlSize(.small).tint(ClaudePalette.ink)
                } else {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                }
            }
            .frame(width: 32, height: 32)
            .background(ClaudePalette.chip, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("\(isRunning ? "Stop" : "Start") \(script.scriptName)")
    }

    // MARK: Errors

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.failureInk)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                store.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ClaudePalette.failureInk.opacity(0.08))
    }
}
#endif
