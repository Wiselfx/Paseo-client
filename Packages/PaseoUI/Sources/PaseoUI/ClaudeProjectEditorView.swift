#if canImport(UIKit)
    import SwiftUI

    struct ClaudeProjectEditorView: View {
        @Binding var state: ProjectState
        let typography: ClaudeTypography
        let action: (ProjectAction) -> Void
        @State private var notice: String?
        @State private var destination: String?
        @FocusState private var nameFocused: Bool
        var body: some View {
            Group {
                if destination == "icons" {
                    ClaudeProjectIconPicker(
                        initialSymbol: state.draft.icon, initialColor: state.draft.iconColor,
                        back: { destination = nil }
                    ) { symbol, color in
                        action(.selectIcon(symbol))
                        action(.selectIconColor(color))
                        destination = nil
                    }
                } else {
                    form
                }
            }.foregroundStyle(ClaudePalette.ink).background(ClaudePalette.background).buttonStyle(.plain)
                .onAppear {
                    if state.editor == .introduction { action(.continueIntroduction) }
                }
                .presentationDetents([.large]).presentationDragIndicator(.hidden)
                .alert(
                    "UI reference needed",
                    isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
                ) {
                    Button("OK") { notice = nil }
                } message: {
                    Text(notice ?? "")
                }
        }
        private var closeButton: some View {
            Button {
                action(.cancel)
            } label: {
                Image(systemName: "xmark").font(.system(size: 23, weight: .light)).frame(width: 44, height: 44)
            }.glassEffect(in: .circle).accessibilityLabel("Cancel new project").accessibilityIdentifier(
                "project.cancel")
        }
        private var form: some View {
            VStack(spacing: 0) {
                ZStack {
                    Text("New project").font(.system(size: 17, weight: .semibold))
                    HStack {
                        closeButton
                        Spacer()
                        Button {
                            if let draft = state.validatedDraft { action(.create(draft)) }
                        } label: {
                            Image(systemName: "checkmark").font(.system(size: 23, weight: .light)).frame(
                                width: 44, height: 44
                            ).background(.white.opacity(state.canCreate ? 1 : 0.35), in: .circle).foregroundStyle(
                                state.canCreate ? .black : .white)
                        }.disabled(!state.canCreate).accessibilityLabel("Create project").accessibilityIdentifier(
                            "project.create")
                    }
                }.frame(height: 48).padding(.horizontal, 16).padding(.top, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Name")
                            HStack(spacing: 8) {
                                Button {
                                    nameFocused = false
                                    action(.openIconPicker)
                                    destination = "icons"
                                } label: {
                                    Group {
                                        if state.draft.icon == "rectangle.stack" {
                                            ProjectOutlineIcon()
                                        } else {
                                            Image(systemName: state.draft.icon).resizable().scaledToFit()
                                        }
                                    }.frame(width: 22, height: 22).foregroundStyle(
                                        ProjectIconColors.value(state.draft.iconColor)
                                    ).frame(width: 34, height: 34).background(
                                        .white.opacity(0.03), in: .rect(cornerRadius: 12))
                                }.accessibilityLabel("Project icon").accessibilityIdentifier("project.icon")
                                TextField(
                                    "Project name...",
                                    text: Binding(get: { state.draft.name }, set: { action(.editName($0)) })
                                ).font(.system(size: 18)).focused($nameFocused).submitLabel(.done).onSubmit {
                                    nameFocused = false
                                }.accessibilityIdentifier("project.name")
                            }.padding(.horizontal, 16).frame(height: 62).background(
                                ClaudePalette.panel, in: .rect(cornerRadius: 28))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Goal (optional)")
                            ZStack(alignment: .topLeading) {
                                if state.draft.goal.isEmpty {
                                    Text("Finalize the Q3 launch plan").font(.system(size: 18)).foregroundStyle(
                                        ClaudePalette.secondary.opacity(0.65)
                                    ).padding(16).allowsHitTesting(false)
                                }
                                TextEditor(text: Binding(get: { state.draft.goal }, set: { action(.editGoal($0)) }))
                                    .font(.system(size: 18)).scrollContentBackground(.hidden).padding(10)
                                    .accessibilityIdentifier("project.goal")
                            }.frame(height: 96).background(ClaudePalette.panel, in: .rect(cornerRadius: 28))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Context (optional)")
                            Menu {
                                Button {
                                    action(.openContextSource("Repository"))
                                    notice = "The Projects repository picker has not been captured yet."
                                } label: {
                                    Label {
                                        Text("Repository")
                                    } icon: {
                                        CodeReferenceIcons.image(.branch)
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus").font(.system(size: 23, weight: .light))
                                    Text("Add context")
                                    Spacer()
                                }.padding(.horizontal, 20).frame(height: 54).background(
                                    ClaudePalette.panel, in: .capsule
                                ).contentShape(Capsule())
                            }.menuOrder(.fixed).accessibilityIdentifier("project.context")
                            ForEach(state.draft.context, id: \.self) { item in
                                HStack {
                                    CodeReferenceIcons.image(.branch).frame(width: 20, height: 20)
                                    Text(item).lineLimit(1)
                                    Spacer()
                                    Button {
                                        action(.removeContext(item))
                                    } label: {
                                        Image(systemName: "xmark").frame(width: 30, height: 44)
                                    }.accessibilityLabel("Remove " + item)
                                }.padding(.horizontal, 20).background(ClaudePalette.panel, in: .capsule)
                            }
                            if !state.suggestedRepository.isEmpty
                                && !state.draft.context.contains(state.suggestedRepository)
                            {
                                Button {
                                    action(.addContext(state.suggestedRepository))
                                } label: {
                                    HStack(spacing: 12) {
                                        CodeReferenceIcons.image(.branch).frame(width: 20, height: 20)
                                        Text(state.suggestedRepository).lineLimit(1)
                                        Spacer()
                                        Image(systemName: "plus").font(.system(size: 20, weight: .light))
                                    }.padding(.horizontal, 20).frame(height: 54).overlay {
                                        Capsule().stroke(
                                            ClaudePalette.ink.opacity(0.09),
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    }.contentShape(Capsule())
                                }.foregroundStyle(ClaudePalette.secondary).accessibilityIdentifier(
                                    "project.suggested-repository")
                            }
                        }
                        Menu {
                            ForEach(state.environments, id: \.self) { environment in
                                Button {
                                    action(.selectEnvironment(environment))
                                } label: {
                                    Label(environment, systemImage: "cloud")
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "cloud").font(.system(size: 21, weight: .light))
                                Text("Environment")
                                Spacer()
                                Text(state.draft.environment ?? "Choose").foregroundStyle(ClaudePalette.secondary)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(
                                    ClaudePalette.secondary)
                            }.padding(.horizontal, 20).frame(height: 54).background(ClaudePalette.panel, in: .capsule)
                                .contentShape(Capsule())
                        }.menuOrder(.fixed).accessibilityIdentifier("project.environment")
                    }.font(.system(size: 18)).padding(.horizontal, 16).padding(.top, 32).padding(.bottom, 20)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        private func fieldLabel(_ title: String) -> some View {
            Text(title).font(.system(size: 16)).foregroundStyle(ClaudePalette.secondary).padding(.horizontal, 16)
        }
    }
#endif
