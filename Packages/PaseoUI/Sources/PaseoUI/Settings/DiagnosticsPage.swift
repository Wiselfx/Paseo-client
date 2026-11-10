#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Settings → Diagnostics: a copyable app report for support bundles, plus the daemon's own
/// host diagnostics (`diagnostics.request`) when the daemon advertises
/// `features.daemonDiagnostics`. Everything in the app report is derived from this device's
/// build info and the daemon's `server_info`, and it is scrubbed by construction: no tokens,
/// no passwords, no full host name (the host appears only as a stable `host-…` digest). The
/// daemon bundle is scrubbed the same way before it is shown or copied (see
/// `scrubHostDiagnostic`).
struct DiagnosticsPage: View {
    let session: HostSession

    @State private var report = ""
    @State private var audioEngine = VoiceAudioEngine()
    @State private var testAudioPlaying = false
    @State private var testAudioResult: String?


    var body: some View {
        PageList {
            Section {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ScrollView {
                        Text(report)
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.sm)
                    }
                    .frame(maxHeight: 300)
                    HStack {
                        CopyButton(text: report)
                            .accessibilityIdentifier("settings.diagnostics.copy")
                        Spacer(minLength: 0)
                    }
                }
                .padding(Space.md)
                .panelRow()
            } header: {
                Text("App report")
            } footer: {
                Text(
                    "Contains no tokens, passwords or host names. The host appears as a stable `host-…` digest. Share it only if support asks for it."
                )
            }
            Section {
                hostDiagnosticsRow
            } header: {
                Text("Host diagnostics")
            }
            Section {
                testAudioRow
            } header: {
                Text("Audio")
            }
        }
        .inlinePageTitle("Diagnostics")
        .refreshable {
            // No refresh button anywhere: the page reloads by pulling it (PLAN §1).
            report = Self.makeReport(session: session)
            await session.hostSettings.loadDiagnostics()
        }
        .task {
            if report.isEmpty { report = Self.makeReport(session: session) }
            if session.hostSettings.supportsDaemonDiagnostics,
                session.hostSettings.diagnosticsState == .idle
            {
                await session.hostSettings.loadDiagnostics()
            }
        }
    }

    // MARK: Host diagnostics

    @ViewBuilder private var hostDiagnosticsRow: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            switch session.hostSettings.diagnosticsState {
            case .idle:
                Text("Ask the daemon for its support bundle: versions, provider availability and runtime metrics.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            case .unsupported:
                Text("Not supported by this daemon.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            case .loading:
                HStack(spacing: Space.sm) {
                    InlineProgress()
                    Text("Running…")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
            case .ready(let diagnostic):
                ScrollView {
                    Text(Self.scrubHostDiagnostic(diagnostic))
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.sm)
                }
                .frame(maxHeight: 300)
                HStack {
                    CopyButton(text: Self.scrubHostDiagnostic(diagnostic))
                        .accessibilityIdentifier("settings.diagnostics.hostCopy")
                    Spacer(minLength: 0)
                }
            case .failed(let message):
                Text(message)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .panelRow()
    }

    // MARK: Test audio (M15: upstream plays the thinking-tone PCM here)

    private var testAudioRow: some View {
        HStack(alignment: .center, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Test audio")
                    .font(.paseo(.body))
                    .foregroundStyle(Palette.ink)
                if let testAudioResult {
                    Text(testAudioResult)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.sm)
            Button {
                Haptics.selection()
                playTestTone()
            } label: {
                Text(testAudioPlaying ? "Playing..." : "Play test")
            }
            .buttonStyle(.paseoSecondary)
            .disabled(testAudioPlaying)
            .accessibilityIdentifier("settings.diagnostics.testAudio")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(minHeight: 44)
        .panelRow()
    }

    private func playTestTone() {
        Task {
            testAudioPlaying = true
            testAudioResult = nil
            do {
                try await audioEngine.playTestTone()
                testAudioResult = nil
            } catch {
                testAudioResult = "Playback failed: \(error.localizedDescription)"
            }
            testAudioPlaying = false
        }
    }

    // MARK: Privacy scrubber

    /// The privacy scrubber, byte-identical to the pre-split implementation: the home path and
    /// any bearer token, password or key are replaced before the text is shown or copied.
    private static func scrubHostDiagnostic(_ text: String) -> String {
        var result = text
        let home = FileManager.default.homeDirectoryForCurrentUser().path
        if !home.isEmpty, home != "/" {
            result = result.replacingOccurrences(of: home, with: "~")
        }
        result = Self.redact(pattern: #"(?i)\b(Bearer)\s+\S+"#, in: result, replacement: "$1 [redacted]")
        result = Self.redact(
            pattern: #"(?i)\b(token|password|passwd|secret|api[_-]?key|access[_-]?key)\s*[:=]\s*[^\s,;]+"#,
            in: result, replacement: "$1: [redacted]")
        return result
    }

    private static func redact(pattern: String, in text: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    // MARK: Report

    static func makeReport(session: HostSession, now: Date = Date()) -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"

        var lines: [String] = []
        lines.append("Paseo Client diagnostics")
        lines.append("App: \(short) (\(build))")
        lines.append("iOS: \(UIDevice.current.systemVersion)")
        lines.append("Device: \(UIDevice.current.model)")
        lines.append("Connection: \(connectionLine(session))")
        lines.append("Host: \(hostDigest(session))")
        lines.append("Daemon: \(session.serverInfo?.version ?? "unknown")")
        lines.append("Protocol: \(session.serverInfo?.protocolVersion.map(String.init) ?? "unknown")")
        if let serverId = session.serverInfo?.serverId, !serverId.isEmpty {
            lines.append("Server ID: \(serverId)")
        }
        lines.append("Features: \(enabledFeatures(session))")
        if let last = lastConnectionError(session) {
            lines.append("Last connection error: \(last)")
        }
        lines.append("Generated: \(iso8601(now))")
        return lines.joined(separator: "\n")
    }

    static func connectionLine(_ session: HostSession) -> String {
        switch session.connection {
        case .connected: "connected"
        case .connecting: "connecting"
        case .reconnecting(let attempt, _): "reconnecting (attempt \(attempt))"
        case .failed: "disconnected"
        case .idle: "not connected"
        }
    }

    /// A stable `host-…` digest. FNV-1a of hostname + serverId; one-way, so the report cannot be
    /// used to learn the host's name, but support can correlate two reports from the same host.
    static func hostDigest(_ session: HostSession) -> String {
        let seed =
            (session.serverInfo?.hostname ?? "") + "|"
            + (session.serverInfo?.serverId ?? "")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "host-%08x", UInt32(truncatingIfNeeded: hash))
    }

    private static func enabledFeatures(_ session: HostSession) -> String {
        guard let features = session.serverInfo?.features else { return "none advertised" }
        let enabled = features
            .filter { $0.value == .bool(true) }
            .map(\.key)
            .sorted()
        return enabled.isEmpty ? "none" : enabled.joined(separator: ", ")
    }

    /// Only machine-readable bits survive; free text (which can carry addresses) never does.
    private static func lastConnectionError(_ session: HostSession) -> String? {
        switch session.connection {
        case .reconnecting(_, let last): errorSummary(last)
        case .failed(let error): errorSummary(error)
        case .connected, .connecting, .idle: nil
        }
    }

    private static func errorSummary(_ error: ConnectionError) -> String {
        switch error {
        case .rejected(let reason):
            // Reason is a machine code (password_required, incorrect_password, …).
            "rejected (\(reason))"
        case .timeout:
            "timeout"
        case .transport:
            // The message can contain the daemon's address; never include it.
            "transport error"
        case .closed(let code, _):
            "closed (\(code))"
        case .protocolViolation:
            "protocol violation"
        case .disconnected:
            "disconnected"
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

}
#endif
