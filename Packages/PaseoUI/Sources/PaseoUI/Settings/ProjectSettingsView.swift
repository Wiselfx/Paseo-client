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
    @State private var iconMemo = ProjectIconImageMemo()
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
    /// Why the last picked photo or file could not be read, shown in the icon group.
    @State private var iconLoadError: String?
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
            "Remove script?",
            item: $pendingDeleteScript
        ) { script in
            Button("Remove", role: .destructive) {
                scripts.removeAll { $0.id == script.id }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
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
        .paseoFeedback(.success, trigger: savedPulse) { _, new in new }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if store.phase == .failed && store.config == nil && store.sendError != nil {
            ProjectLoadFailure(
                message: store.error?.userMessage ?? store.sendError ?? "Something went wrong. Try again."
            ) {
                Task {
                    await store.load(repoRoot: project.projectRootPath)
                    seed()
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ProjectHero(title: title, path: project.projectRootPath, image: iconImage)
                    ProjectNameGroup(session: session, project: project) {
                        renameText = project.projectCustomName ?? project.projectDisplayName
                        renaming = true
                    }
                    ProjectIconGroup(
                        icons: icons,
                        projectId: project.projectId,
                        hasCustomIcon: $hasCustomIcon,
                        photoItem: $photoItem,
                        pickingFile: $pickingFile,
                        loadError: iconLoadError
                    )
                    WorktreeCommandsGroup(
                        hasUncommittedChanges: store.hasUncommittedWorktreeSetupChanges,
                        setup: $setupText,
                        teardown: $teardownText
                    )
                    ProjectScriptsGroup(
                        scripts: scripts,
                        issue: scriptsIssue,
                        onAdd: {
                            let draft = ProjectScriptDraft(name: "", command: "")
                            scripts.append(draft)
                            editingScript = draft
                        },
                        onEdit: { editingScript = $0 },
                        onRemove: { pendingDeleteScript = $0 }
                    )
                    ProjectConfigCallouts(
                        store: store,
                        onSave: { Task { await save() } },
                        onReload: { Task { await reloadFromHost() } }
                    )
                    HStack {
                        if let error = session.workspaceDirectory.actionError {
                            Text(error)
                                .font(.paseo(.footnote))
                                .foregroundStyle(Palette.failureInk)
                                .padding(.leading, Space.lg)
                        }
                    }
                    ProjectRemoveButton { confirmRemove = true }
                        // On the trigger, not the page, so the dialog animates from the button.
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
                    ProjectSaveButton(isSaving: store.isSaving, savedPulse: savedPulse) {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
                .padding(.horizontal, Space.lg)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.xxl)
            }
            .scrollIndicators(.hidden)
            .overlay {
                if store.phase == .loading && !didSeed {
                    ProgressView()
                }
            }
        }
    }

    /// Decoded once per icon: the page re-evaluates for every keystroke in its text fields.
    private var iconImage: UIImage? {
        icons.iconData.flatMap { iconMemo.image(for: $0) }
    }

    private var scriptsIssue: String? {
        let names = scripts.map { $0.name.trimmingCharacters(in: .whitespaces) }
        if names.contains(where: \.isEmpty) { return "Every script needs a name." }
        if let first = names.first(where: { name in names.count(where: { $0 == name }) > 1 }) {
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
            savedPulse = true
            seed()
            try? await Task.sleep(for: .seconds(1.5))
            savedPulse = false
        } else {
            Haptics.failure()
        }
    }

    private func setUpload(fromPhotoItem item: PhotosPickerItem) async {
        iconLoadError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                iconLoadError = "That photo couldn't be read."
                Haptics.failure()
                return
            }
            await setUpload(data: data)
        } catch {
            iconLoadError = error.localizedDescription
            Haptics.failure()
        }
    }

    private func setUpload(fromFileURL url: URL) async {
        iconLoadError = nil
        // Read off the main actor: an icon picked from an iCloud Drive folder still has to
        // download, and this ran that read on the main actor (`PickedFileLoader`).
        switch await PickedFileLoader.load(url, maxBytes: ConversationUpload.maxBytes) {
        case .success(let file):
            await setUpload(data: file.data)
        case .failure(let failure):
            if case .tooLarge = failure {
                iconLoadError = "That file is too large for a project icon."
            } else {
                iconLoadError = "That file couldn't be read."
            }
            Haptics.failure()
        }
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
}
#endif
