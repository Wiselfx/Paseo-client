#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The slash-command menu body.
struct SlashMenu: View {
    let controller: ChatController
    let query: String
    let onPick: (AgentSlashCommand) -> Void

    var body: some View {
        ComposerMenuContainer(accessibilityIdentifier: "composer.slashMenu") {
            Group {
                switch controller.slashState {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading commands…")
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .ready:
                    readyRows
                case .idle:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder private var readyRows: some View {
        let commands = controller.filteredSlashCommands(for: query)
        if let error = controller.slashError, controller.slashCommands.isEmpty {
            Text(error)
                .font(.paseo(.caption))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if commands.isEmpty {
            if !controller.slashCommands.isEmpty {
                Text("No matching commands")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(commands) { command in
                        Button {
                            onPick(command)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text("/\(command.name)")
                                        .font(.paseo(.code, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    if !command.argumentHint.isEmpty {
                                        Text(command.argumentHint)
                                            .font(.paseo(.codeCaption))
                                            .foregroundStyle(Palette.tertiaryInk)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if command.kind == .skill {
                                        Image(systemName: "sparkles")
                                            .font(.glyph(.small, weight: .medium))
                                            .foregroundStyle(Palette.secondaryInk)
                                            .accessibilityLabel("Skill")
                                    }
                                }
                                if !command.description.isEmpty {
                                    Text(command.description)
                                        .font(.paseo(.caption))
                                        .foregroundStyle(Palette.secondaryInk)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
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
            }
            .frame(maxHeight: 276)
            .scrollIndicators(.hidden)
        }
    }
}
#endif
