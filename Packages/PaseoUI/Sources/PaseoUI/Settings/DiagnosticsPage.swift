#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Settings → Diagnostics: a copyable app report for support bundles. Everything in the report is
/// derived from this device's build info and the daemon's `server_info`, and it is scrubbed by
/// construction: no tokens, no passwords, no full host name (the host appears only as a stable
/// `host-…` digest). The daemon's own diagnostics (`diagnostics.request`) are not reachable from
/// this build's client layer — see the M4e handoff / PARITY row.
struct DiagnosticsPage: View {
    let session: HostSession

    @State private var report = ""
    @State private var copied = false

    private let typography = ClaudeTypography()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("App report")
                RowGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView {
                            Text(report)
                                .font(typography.mono(11.5, relativeTo: .caption))
                                .foregroundStyle(ClaudePalette.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(maxHeight: 300)
                        HStack {
                            Button {
                                Haptics.selection()
                                UIPasteboard.general.string = report
                                copied = true
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    copied = false
                                }
                            } label: {
                                Label(copied ? "Copied" : "Copy",
                                      systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("settings.diagnostics.copy")
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(12)
                }
                Text("Contains no tokens, passwords or host names. The host appears as a stable `host-…` digest. Share it only if support asks for it.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if report.isEmpty { report = Self.makeReport(session: session) }
        }
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

    // MARK: Shared bits

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}
#endif
