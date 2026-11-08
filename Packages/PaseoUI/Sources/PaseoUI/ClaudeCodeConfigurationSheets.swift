#if canImport(UIKit)
    import SwiftUI

    struct ClaudeCodeRepositorySheet: View {
        @Binding var state: CodeDraftState
        let action: (CodeDraftAction) -> Void
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            VStack(spacing: 0) {
                SheetHeader(
                    title: "Repositories (\(state.repository == nil ? 0 : 1))", controlDiameter: 44,
                    close: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let selected = state.repository {
                            section("Selected")
                            RowGroup { row(selected, selected: true) }
                        }
                        section("Repositories").padding(.top, 12)
                        RowGroup {
                            ForEach(
                                Array(state.repositories.filter { $0.id != state.repository?.id }.enumerated()),
                                id: \.element.id
                            ) { index, repository in
                                row(repository, selected: false)
                                if index < state.repositories.filter({ $0.id != state.repository?.id }).count - 1 {
                                    RowDivider()
                                }
                            }
                        }
                    }.padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 65)
                }.scrollIndicators(.hidden)
            }.background(ClaudePalette.background).foregroundStyle(ClaudePalette.ink).presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .overlay(alignment: .bottom) {
                    HStack {
                        Button {
                            action(.searchRepositories)
                        } label: {
                            Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .light)).frame(
                                width: 44, height: 44)
                        }.glassEffect(in: .circle).accessibilityLabel("Search repositories").accessibilityIdentifier(
                            "code.repositories.search")
                        Spacer()
                        Button {
                            action(.connectRepositories)
                        } label: {
                            Label("Connect more", systemImage: "plus").font(.system(size: 16)).padding(.horizontal, 16)
                                .frame(height: 44)
                        }.glassEffect(in: .capsule).accessibilityIdentifier("code.repositories.connect")
                    }.padding(.horizontal, 24).padding(.bottom, 0)
                }
        }
        private func section(_ title: String) -> some View {
            Text(title).font(.system(size: 16)).foregroundStyle(ClaudePalette.secondary).padding(.horizontal, 16)
        }
        private func row(_ repository: CodeRepository, selected: Bool) -> some View {
            Button {
                action(.selectRepository(repository.id))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(repository.owner).font(.system(size: 14)).foregroundStyle(ClaudePalette.secondary)
                        Text(repository.name).font(.system(size: 18))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 20, weight: .semibold)).foregroundStyle(.blue)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 14).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("code.repository.\(repository.id)")
        }
    }
#endif
