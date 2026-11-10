#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// One project's settings: rename, icon, and the `paseo.json` sections the host honors
/// (worktree setup/teardown, scripts), edited as local drafts and written through
/// `read_project_config_request` / `write_project_config_request` with `expectedRevision`.
///
/// A stale write shows "This file changed on the host." + Reload; unknown keys in paseo.json
/// round-trip untouched. Remove project is available here too, with the same confirmation the
/// Projects list uses.
struct ProjectSettingsView: View {
    let session: HostSession
    let project: WorkspaceProjectDescriptor

    @Environment(\.dismiss) private var dismiss
    @State private var setupText = ""
    @State private var teardownText = ""
    @State private var scripts: [ProjectScriptDraft] = []
    @State private var editingScript: ProjectScriptDraft?
    @State private var pendingDeleteScript: ProjectScriptDraft?
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmRemove = false
    @State private var savedPulse = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pickingFile = false
    @State private var hasCustomIcon: Bool
    @State private var didSeed = false

    private let store: ProjectConfigStore
    private let icons: ProjectIconStore

    init(session: HostSession, project: WorkspaceProjectDescriptor) {
        self.session = session
        self.project = project
        self.store = session.projectConfig
        self.icons = session.projectIcons
        _hasCustomIcon = State(initialValue: project.projectCustomIconRevision != nil)
    }

    private var title: String {
        project.projectCustomName ?? project.projectDisplayName
    }

    var body: some View {
        content
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .background(Palette.background)
        .alert("Rename project", isPresented: $renaming) {
            TextField("Project name", text: $renameText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let text = renameText
                Task {
                    let ok = await session.workspaceDirectory.renameProject(
                        project.projectId, to: text)
                    if ok { Haptics.success() } else { Haptics.failure() }
                }
            }
        } message: {
            Text("Empty restores the folder name.")
        }
        .confirmationDialog(
            "Remove project?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    let ok = await session.workspaceDirectory.removeProject(project.projectId)
                    if ok {
                        Haptics.success()
                        dismiss()
                    } else {
                        Haptics.failure()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The project and its workspaces will be unregistered on this host. Files on disk will not be changed.")
        }
        .confirmationDialog(
            "Remove script?",
            isPresented: Binding(
                get: { pendingDeleteScript != nil },
                set: { if !$0 { pendingDeleteScript = nil } })
        ) {
            Button("Remove", role: .destructive) {
                guard let script = pendingDeleteScript else { return }
                pendingDeleteScript = nil
                scripts.removeAll { $0.id == script.id }
            }
            Button("Cancel", role: .cancel) { pendingDeleteScript = nil }
        } message: {
            Text("This only removes the script from paseo.json when you save.")
        }
        .sheet(item: $editingScript) { script in
            ScriptEditSheet(script: script) { saved in
                if let index = scripts.firstIndex(where: { $0.id == saved.id }) {
                    scripts[index] = saved
                }
                editingScript = nil
            } onCancel: {
                // A just-added script that was never filled in is dropped on cancel.
                if let index = scripts.firstIndex(where: { $0.id == script.id }) {
                    let entry = scripts[index]
                    if entry.name.trimmingCharacters(in: .whitespaces).isEmpty
                        && entry.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        scripts.remove(at: index)
                    }
                }
                editingScript = nil
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            Task { await setUpload(fromFileURL: url) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await setUpload(fromPhotoItem: item) }
            photoItem = nil
        }
        .task {
            await store.load(repoRoot: project.projectRootPath)
            await icons.load(projectId: project.projectId)
            seed()
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if store.phase == .failed && store.config == nil && store.sendError != nil {
            loadFailure
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    nameGroup
                    iconGroup
                    worktreeGroup
                    scriptsGroup
                    staleCallout
                    writeFailedCallout
                    storeErrors
                    removeButton
                    saveButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .overlay {
                if store.phase == .loading && !didSeed {
                    ProgressView()
                }
            }
        }
    }

    private var loadFailure: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.glyph(.xlarge, weight: .light))
                .foregroundStyle(Palette.warning)
            Text("Couldn't read paseo.json")
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(store.error?.userMessage ?? store.sendError ?? "Something went wrong. Try again.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    await store.load(repoRoot: project.projectRootPath)
                    seed()
                }
            } label: {
                Text("Try again")
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 44)
                    .background(Palette.ink, in: .capsule)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Palette.chip)
                    .frame(width: 60, height: 60)
                if let image = iconImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else {
                    Text(String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.paseo(.largeTitle))
                        .foregroundStyle(Palette.ink)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.paseo(.title))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(project.projectRootPath)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
    }

    private var iconImage: UIImage? {
        icons.iconData.flatMap(UIImage.init(data:))
    }

    // MARK: Name

    private var nameGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Name")
            RowGroup {
                HStack(spacing: 14) {
                    Button {
                        renameText = project.projectCustomName ?? project.projectDisplayName
                        renaming = true
                    } label: {
                        HStack(spacing: 14) {
                            Text(title)
                                .font(.paseo(.body))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if project.projectCustomName == nil {
                                Image(systemName: "chevron.right")
                                    .font(.glyph(.regular))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 51)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename project")
                    if project.projectCustomName != nil {
                        Button {
                            Task {
                                let ok = await session.workspaceDirectory.renameProject(
                                    project.projectId, to: nil)
                                if ok { Haptics.success() } else { Haptics.failure() }
                            }
                        } label: {
                            Text("Reset")
                                .font(.paseo(.footnote, weight: .medium))
                                .foregroundStyle(Palette.secondaryInk)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 30)
                                .background(Palette.chip, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset to the folder name")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Icon

    private var iconGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Icon")
            RowGroup {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Icon")
                            .font(.paseo(.body))
                            .foregroundStyle(Palette.ink)
                        Text(hasCustomIcon ? "Custom" : "Automatic")
                            .font(.paseo(.footnote))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    if icons.isSaving {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 51)
                RowDivider()
                HStack(spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Photos", systemImage: "photo")
                            .font(.paseo(.footnote, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Palette.chip, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!icons.supportsCustomIcon)
                    .opacity(icons.supportsCustomIcon ? 1 : 0.45)
                    .accessibilityLabel("Choose a photo for the project icon")
                    Button {
                        pickingFile = true
                    } label: {
                        Label("Files", systemImage: "doc")
                            .font(.paseo(.footnote, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Palette.chip, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!icons.supportsCustomIcon)
                    .opacity(icons.supportsCustomIcon ? 1 : 0.45)
                    .accessibilityLabel("Choose a file for the project icon")
                    if hasCustomIcon {
                        Button {
                            Task {
                                let ok = await icons.reset(projectId: project.projectId)
                                if ok {
                                    hasCustomIcon = false
                                    Haptics.success()
                                } else {
                                    Haptics.failure()
                                }
                            }
                        } label: {
                            Text("Reset")
                                .font(.paseo(.footnote, weight: .medium))
                                .foregroundStyle(Palette.secondaryInk)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .background(Palette.chip, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .disabled(!icons.supportsCustomIcon)
                        .accessibilityLabel("Reset the project icon to automatic")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 51)
                if !icons.supportsCustomIcon {
                    Text("This host can't set project icons.")
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                if let error = icons.error {
                    Text(error)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: Worktree

    private var worktreeGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Worktree")
            if store.hasUncommittedWorktreeSetupChanges {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(Palette.warning)
                    Text("This worktree setup has uncommitted changes.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            RowGroup {
                configField(title: "Setup", text: $setupText, placeholder: "npm install")
                RowDivider()
                configField(title: "Teardown", text: $teardownText, placeholder: "docker compose down")
            }
            Text("One command per line, run in order. Saved to paseo.json on this host.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.tertiaryInk)
                .padding(.leading, 16)
        }
    }

    private func configField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.paseo(.code))
                        .foregroundStyle(Palette.tertiaryInk)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: text)
                    .font(.paseo(.code))
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 64, maxHeight: 160)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Scripts

    private var scriptsGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("Scripts")
                Spacer()
                Button {
                    let draft = ProjectScriptDraft(name: "", command: "")
                    scripts.append(draft)
                    editingScript = draft
                } label: {
                    Image(systemName: "plus")
                        .font(.glyph(.regular, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 30, height: 30)
                        .frame(width: 44, height: 44)
                        .background(Palette.chip, in: .circle)
                }
                .padding(.trailing, 16)
                .accessibilityLabel("Add script")
            }
            RowGroup {
                if scripts.isEmpty {
                    Text("No scripts. Scripts run on demand from the workspace panel.")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                } else {
                    ForEach(Array(scripts.enumerated()), id: \.element.id) { index, script in
                        scriptRow(script)
                        if index < scripts.count - 1 { RowDivider() }
                    }
                }
            }
            if let issue = scriptsIssue {
                Text(issue)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .padding(.leading, 16)
            }
        }
    }

    private func scriptRow(_ script: ProjectScriptDraft) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(script.name.isEmpty ? "Unnamed script" : script.name)
                    .font(.paseo(.code, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(script.command.isEmpty ? "No command" : script.command)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Menu {
                Button("Edit", systemImage: "pencil") { editingScript = script }
                Button("Remove", systemImage: "trash", role: .destructive) {
                    pendingDeleteScript = script
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 36, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Script actions")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 51)
    }

    // MARK: Save / errors

    private var staleCallout: some View {
        Group {
            if store.stale, store.error != nil {
                callout(
                    title: "This file changed on the host.",
                    detail: "Your edits were not saved. Reloading shows the latest paseo.json.",
                    actionLabel: "Reload") {
                        Task { await reloadFromHost() }
                    }
            }
        }
    }

    private var writeFailedCallout: some View {
        Group {
            if !store.stale, let error = store.error {
                callout(
                    title: "The change couldn't be saved.",
                    detail: error.userMessage,
                    actionLabel: "Try again") {
                        Task { await save() }
                    }
            } else if let sendError = store.sendError {
                callout(
                    title: "The change couldn't be saved.",
                    detail: sendError,
                    actionLabel: "Reload") {
                        Task { await reloadFromHost() }
                    }
            }
        }
    }

    private var storeErrors: some View {
        HStack {
            if let error = session.workspaceDirectory.actionError {
                Text(error)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .padding(.leading, 16)
            }
        }
    }

    private func callout(
        title: String, detail: String, actionLabel: String, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(Palette.failureInk)
            Text(detail)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Text(actionLabel)
                    .font(.paseo(.footnote, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 34)
                    .background(Palette.chip, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.quoteWash, in: .rect(cornerRadius: Radius.lg))
    }

    private var removeButton: some View {
        Button {
            confirmRemove = true
        } label: {
            Text("Remove project…")
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.failureInk)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove project")
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Group {
                if store.isSaving {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                } else if savedPulse {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("Saved")
                    }
                    .font(.paseo(.callout, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                } else {
                    Text("Save changes")
                        .font(.paseo(.callout, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
            }
            .foregroundStyle(Palette.background)
            .background(
                Palette.ink.opacity(canSave ? 1 : 0.35), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .accessibilityLabel("Save project settings")
    }

    private var scriptsIssue: String? {
        let names = scripts.map { $0.name.trimmingCharacters(in: .whitespaces) }
        if names.contains(where: \.isEmpty) { return "Every script needs a name." }
        if let first = names.first(where: { name in names.filter { $0 == name }.count > 1 }) {
            return "Duplicate script name: \(first)."
        }
        if scripts.contains(where: { $0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Every script needs a command."
        }
        return nil
    }

    private var canSave: Bool {
        !store.isSaving && scriptsIssue == nil
    }

    // MARK: Actions

    private func seed() {
        didSeed = true
        let (setup, teardown) = ProjectConfigEditor.worktreeCommands(store.config)
        setupText = ProjectConfigEditor.text(from: setup)
        teardownText = ProjectConfigEditor.text(from: teardown)
        scripts = ProjectConfigEditor.scripts(store.config)
    }

    private func reloadFromHost() async {
        await store.load(repoRoot: project.projectRootPath)
        store.clearErrors()
        seed()
    }

    private func save() async {
        let ok = await store.save(
            repoRoot: project.projectRootPath,
            setup: ProjectConfigEditor.commands(from: setupText),
            teardown: ProjectConfigEditor.commands(from: teardownText),
            scripts: scripts)
        if ok {
            Haptics.success()
            savedPulse = true
            seed()
            try? await Task.sleep(for: .seconds(1.5))
            savedPulse = false
        } else {
            Haptics.failure()
        }
    }

    private func setUpload(fromPhotoItem item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            Haptics.failure()
            return
        }
        await setUpload(data: data)
    }

    private func setUpload(fromFileURL url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            Haptics.failure()
            return
        }
        await setUpload(data: data)
    }

    private func setUpload(data: Data) async {
        let ok = await icons.setUpload(projectId: project.projectId, data: data)
        if ok {
            hasCustomIcon = true
            Haptics.success()
        } else {
            Haptics.failure()
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.paseo(.callout))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 16)
    }
}

/// Name + command editor for one script.
private struct ScriptEditSheet: View {
    @State var script: ProjectScriptDraft
    var onSave: (ProjectScriptDraft) -> Void
    var onCancel: () -> Void


    private var canSave: Bool {
        !script.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !script.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: script.command.isEmpty && script.name.isEmpty ? "New script" : "Script", close: onCancel)
            VStack(alignment: .leading, spacing: 18) {
                field(title: "Name", text: $script.name, placeholder: "start-ios", mono: true)
                field(title: "Command", text: $script.command, placeholder: "npm run dev", mono: true)
                Button {
                    guard canSave else { return }
                    var saved = script
                    saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                    onSave(saved)
                    Haptics.light()
                } label: {
                    Text("Save")
                        .font(.paseo(.callout, weight: .semibold))
                        .foregroundStyle(Palette.background)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(
                            Palette.ink.opacity(canSave ? 1 : 0.35), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .padding(.top, 4)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Palette.background)
        .presentationDetents([.medium, .large])
    }

    private func field(title: String, text: Binding<String>, placeholder: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            ZStack(alignment: .leading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.paseo(.code))
                        .foregroundStyle(Palette.tertiaryInk)
                        .allowsHitTesting(false)
                }
                TextField("", text: text)
                    .font(.paseo(.code))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Palette.chip, in: .rect(cornerRadius: Radius.md))
        }
    }
}
#endif
