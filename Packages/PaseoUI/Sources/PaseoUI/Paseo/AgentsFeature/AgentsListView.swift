import PaseoStore
import SwiftUI

/// Every agent on the host, newest activity first, like a list of chats.
public struct AgentsListView: View {
    var session: HostSession
    var onOpen: (AgentSnapshot) -> Void

    public init(session: HostSession, onOpen: @escaping (AgentSnapshot) -> Void) {
        self.session = session
        self.onOpen = onOpen
    }

    public var body: some View {
        List {
            if let banner = connectionBanner {
                Label(banner, systemImage: "wifi.exclamationmark")
                    .font(Typeset.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .listRowBackground(Color.clear)
            }
            ForEach(session.agents) { agent in
                Button {
                    Haptics.selection()
                    onOpen(agent)
                } label: {
                    AgentRow(agent: agent, project: session.projects[agent.id])
                }
                .buttonStyle(.plain)
                .listRowBackground(Palette.background)
                .listRowSeparatorTint(Palette.hairline)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .refreshable { await session.refreshAgents() }
        .overlay {
            if session.agents.isEmpty {
                if let error = session.agentsError {
                    ContentUnavailableView("Couldn't load agents", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ContentUnavailableView("No agents", systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
        .navigationTitle(session.serverInfo?.hostname ?? "Agents")
    }

    private var connectionBanner: String? {
        switch session.connection {
        case .reconnecting(let attempt, _): "Reconnecting… (attempt \(attempt))"
        case .failed: "Disconnected"
        default: nil
        }
    }
}

struct AgentRow: View {
    let agent: AgentSnapshot
    let project: ProjectPlacement?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderAvatar(provider: agent.provider, isRunning: agent.status == .running)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.title ?? "New agent")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = PaseoDate.parse(agent.updatedAt) {
                        Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                            .font(Typeset.caption)
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
                Text(subtitle)
                    .font(Typeset.chrome)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
            }
            if agent.requiresAttention == true {
                Circle().fill(Palette.accent).frame(width: 9, height: 9).padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let name = project?.projectName { parts.append(name) }
        parts.append(agent.model ?? agent.provider)
        if agent.status == .running { parts.append("working") }
        if agent.status == .error { parts.append("error") }
        return parts.joined(separator: " · ")
    }
}

/// Initial-letter avatar with a breathing ring while the agent works.
struct ProviderAvatar: View {
    let provider: String
    let isRunning: Bool
    @State private var breathe = false

    var body: some View {
        Text(provider.prefix(1).uppercased())
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Self.color(for: provider), in: Circle())
            .overlay {
                if isRunning {
                    Circle()
                        .strokeBorder(Palette.accent, lineWidth: 2)
                        .padding(-4)
                        .opacity(breathe ? 0.25 : 1)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathe)
                        .onAppear { breathe = true }
                }
            }
    }

    static func color(for provider: String) -> Color {
        switch provider {
        case "claude": Color(red: 0.85, green: 0.47, blue: 0.34)
        case "opencode": Color(red: 0.25, green: 0.45, blue: 0.85)
        case "pi", "omp": Color(red: 0.45, green: 0.36, blue: 0.80)
        case "codex": Color(red: 0.20, green: 0.20, blue: 0.22)
        default: Color(red: 0.45, green: 0.47, blue: 0.50)
        }
    }
}
