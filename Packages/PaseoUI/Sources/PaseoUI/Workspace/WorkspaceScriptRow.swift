#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One configured `paseo.json` script: status, subtitle, the service link, "View" for its
/// terminal, and start/stop.
struct WorkspaceScriptRow: View {
    let script: WorkspaceScript
    let isBusy: Bool
    /// Whether the script's terminal is one of the workspace's current terminals.
    let canShowTerminal: Bool
    let onOpenService: (URL) -> Void
    let onShowTerminal: (String) -> Void
    let onToggle: () -> Void
    let onRestart: () -> Void

    var body: some View {
        let serviceURL = script.lifecycle == .running ? script.preferredURL.flatMap(URL.init(string:)) : nil
        HStack(spacing: Space.md) {
            StatusDot(dotKind)
            VStack(alignment: .leading, spacing: 2) {
                Text(script.scriptName)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let serviceURL {
                Button {
                    onOpenService(serviceURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.glyph(.regular, weight: .regular))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: 36, height: 36)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View service \(script.scriptName)")
                .contextMenu {
                    Button("View service", systemImage: "arrow.up.right.square") {
                        onOpenService(serviceURL)
                    }
                    Button("Copy URL", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = serviceURL.absoluteString
                        Haptics.light()
                    }
                }
            }
            if canShowTerminal, let terminalId = script.terminalId {
                Button {
                    Haptics.selection()
                    onShowTerminal(terminalId)
                } label: {
                    Text("View")
                        .font(.paseo(.footnote, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(minHeight: 30)
                        .padding(.horizontal, Space.md)
                        .overlay { Capsule().strokeBorder(Palette.cardBorder, lineWidth: 0.5) }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show terminal for \(script.scriptName)")
            }
            WorkspaceScriptActionButton(script: script, isBusy: isBusy, action: onToggle)
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: 48)
        .contextMenu {
            Button("Restart", systemImage: "arrow.clockwise", action: onRestart)
            let urlTargets = ScriptURLTarget.targets(for: script)
            if !urlTargets.isEmpty {
                Menu("Choose URL", systemImage: "link") {
                    ForEach(urlTargets) { target in
                        Button {
                            UIPasteboard.general.string = target.url
                            Haptics.light()
                        } label: {
                            VStack(alignment: .leading) {
                                Text("Copy \(target.title) URL")
                                Text(target.hostLabel)
                                    .font(.paseo(.caption))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                }
            }
            if let serviceURL = script.preferredURL {
                Button("Copy URL", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = serviceURL
                    Haptics.light()
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        switch script.lifecycle {
        case .running: parts.append(String(localized: "Running", bundle: #bundle))
        case .stopped: parts.append(String(localized: "Stopped", bundle: #bundle))
        case .unknown: parts.append(String(localized: "Unknown", bundle: #bundle))
        }
        switch script.health {
        case .healthy: parts.append(String(localized: "healthy", bundle: #bundle))
        case .unhealthy: parts.append(String(localized: "unhealthy", bundle: #bundle))
        case .unknown, .none: break
        }
        if let port = script.port { parts.append(":\(port)") }
        if script.lifecycle == .stopped, let code = script.exitCode, code != 0 {
            parts.append(String(localized: "exit \(code)", bundle: #bundle))
        }
        return parts.joined(separator: " · ")
    }

    private var dotKind: StatusDot.State {
        switch script.lifecycle {
        case .running:
            return script.health == .unhealthy ? .failed : .running
        case .stopped:
            return (script.exitCode ?? 0) != 0 ? .failed : .idle
        case .unknown:
            return .idle
        }
    }
}
#endif
