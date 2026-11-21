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
                // Lazy: a bare "/" lists every command and skill, and only about six fit.
                LazyVStack(spacing: 0) {
                    ForEach(commands) { command in
                        SlashCommandRow(command: command) { onPick(command) }
                    }
                }
            }
            .frame(maxHeight: 276)
            .scrollIndicators(.hidden)
        }
    }
}
#endif
