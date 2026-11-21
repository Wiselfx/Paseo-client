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
    /// Built when the test tone is first played, not with the page (R-2: nothing to allocate for a page
    /// that is only read).
    @State private var audioEngine: VoiceAudioEngine?
    /// The scrubbed host bundle, remembered per input: the regexes ran twice per body pass.
    @State private var scrubMemo = ScrubMemo()
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
                Text("Ask the host for its support bundle: versions, provider availability and runtime metrics.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            case .unsupported:
                Text("Not supported by this host.")
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
                let scrubbed = scrubMemo.scrubbed(diagnostic)
                ScrollView {
                    Text(scrubbed)
                        .font(.paseo(.codeCaption))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.sm)
                }
                .frame(maxHeight: 300)
                HStack {
                    CopyButton(text: scrubbed)
                        .accessibilityIdentifier("settings.diagnostics.hostCopy")
                    Spacer(minLength: 0)
                }
            case .failed(let message):
                InlineBanner(
                    .failure, title: message,
                    action: ("Try again", { Task { _ = await session.hostSettings.loadDiagnostics() } })
                )
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
                Haptics.light()
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
                let engine = audioEngine ?? VoiceAudioEngine()
                audioEngine = engine
                try await engine.playTestTone()
                testAudioResult = nil
            } catch {
                testAudioResult = "Playback failed: \(error.localizedDescription)"
            }
            testAudioPlaying = false
        }
    }

    // MARK: Privacy scrubber

    /// Scrubs the daemon bundle before display or copy: bearer credentials and
    /// token/password/secret assignments are redacted, and the daemon host's home directory
    /// is shortened to `~`, so no secret or home path leaves the device. The bundle is an
    /// opaque string upstream; this is best-effort on its free text, like the app report's
    /// machine-codes-only rule. JSON `apiKey` values (the speech provider secret) are
    /// redacted too — the app report never includes speech config or keys at all.
    static func scrubHostDiagnostic(_ text: String) -> String {
        // The text comes from the daemon host, so its home directory is not this device's:
        // shorten any macOS/Linux home path (`/Users/<name>`, `/home/<name>`) to `~`.
        var result = text
        for rule in Self.scrubRules {
            guard let regex = rule.regex else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: rule.replacement)
        }
        return result
    }

    /// The four patterns, compiled once, applied in this order.
    private static let scrubRules: [(regex: NSRegularExpression?, replacement: String)] = [
        (try? NSRegularExpression(pattern: #"/(?:Users|home)/[^/\s"']+"#), "~"),
        (try? NSRegularExpression(pattern: #"(?i)\b(Bearer)\s+\S+"#), "$1 [redacted]"),
        (
            try? NSRegularExpression(pattern: #"(?i)"(api[_-]?key)"\s*:\s*"[^"]*""#),
            "\"$1\": \"[redacted]\""
        ),
        (
            try? NSRegularExpression(
                pattern: #"(?i)\b(token|password|passwd|secret|api[_-]?key|access[_-]?key)\s*[:=]\s*[^\s,;]+"#
            ), "$1: [redacted]"
        ),
    ]

    // MARK: Report

    static func makeReport(session: HostSession, now: Date = .now) -> String {
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
        lines.append("Host version: \(session.serverInfo?.version ?? "unknown")")
        lines.append("Protocol: \(session.serverInfo?.protocolVersion.map(String.init) ?? "unknown")")
        if let serverId = session.serverInfo?.serverId, !serverId.isEmpty {
            lines.append("Server ID: \(serverId)")
        }
        lines.append("Features: \(enabledFeatures(session))")
        if let last = lastConnectionError(session) {
            lines.append("Last connection error: \(last)")
        }
        lines.append("Generated: \(now.formatted(.iso8601))")
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
        let hex = String(UInt32(truncatingIfNeeded: hash), radix: 16)
        return "host-" + String(repeating: "0", count: 8 - hex.count) + hex
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
}
#endif
