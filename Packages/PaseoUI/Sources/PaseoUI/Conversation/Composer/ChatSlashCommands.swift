#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension ClaudeChatView {
    // MARK: Slash commands (M8a)

    /// Loads the agent's slash commands once per appearance. The store caches them per agent.
    func loadSlashCommands() async {
        guard slashState == .idle else { return }
        slashState = .loading
        let loaded = await session.hostSettings.loadCommands(for: store.agentId)
        slashCommands = loaded
        slashError = session.hostSettings.commandError(for: store.agentId)
        slashState = .ready
    }

    /// The query while the draft is exactly one slash-command token, else nil.
    var slashQuery: String? {
        let text = store.draft
        guard text.hasPrefix("/") else { return nil }
        let body = text.dropFirst()
        if body.contains(where: { $0.isWhitespace }) { return nil }
        return String(body)
    }

    var filteredSlashCommands: [AgentSlashCommand] {
        guard let query = slashQuery, !query.isEmpty else { return slashCommands }
        let lowered = query.lowercased()
        return slashCommands.filter { $0.name.lowercased().hasPrefix(lowered) }
    }

    var composerPrompt: String {
        if !slashCommands.isEmpty { return "Type / for commands" }
        return store.turns.isEmpty ? "Chat with Paseo" : "Reply to Paseo"
    }

    @ViewBuilder var slashMenu: some View {
        if slashQuery != nil {
            ComposerMenuContainer(accessibilityIdentifier: "composer.slashMenu") {
                Group {
                if slashState == .loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading commands…")
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let slashError, slashCommands.isEmpty {
                    Text(slashError)
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if filteredSlashCommands.isEmpty {
                    if !slashCommands.isEmpty {
                        Text("No matching commands")
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(filteredSlashCommands) { command in
                                slashCommandRow(command)
                            }
                        }
                    }
                    .frame(maxHeight: 276)
                    .scrollIndicators(.hidden)
                }
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    func slashCommandRow(_ command: AgentSlashCommand) -> some View {
        Button {
            Haptics.selection()
            store.draft = "/" + command.name + " "
            focused = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("/" + command.name)
                        .font(typography.mono(14, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    if !command.argumentHint.isEmpty {
                        Text(command.argumentHint)
                            .font(typography.mono(11))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if command.kind == .skill {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .accessibilityLabel("Skill")
                    }
                }
                if !command.description.isEmpty {
                    Text(command.description)
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            ["/\(command.name)", command.description]
                .filter { !$0.isEmpty }
                .joined(separator: ", "))
    }

}
#endif
