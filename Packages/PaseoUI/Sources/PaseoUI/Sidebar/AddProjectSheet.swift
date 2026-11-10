#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Add a project: paste a path to an existing folder, or clone a repository from GitHub
/// (repository search, debounced; destination field; progress state). Both paths end in the new
/// project's workspace being ready: the clone flow creates a `.local` workspace for the freshly
/// registered project before dismissing.
///
/// "Stars" are not on the wire (`GithubRepository` carries id/name/owner/description/visibility/
/// updatedAt), so rows show owner/name, description, a Private chip when applicable, and the
/// last-update age.
struct AddProjectSheet: View {
    let session: HostSession
    /// Called with a toast line once the project (and, for clones, its workspace) is ready.
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .folder
    @State private var path = ""
    @State private var search = ""
    @State private var results: [GithubRepository] = []
    @State private var searchState: SearchState = .idle
    @State private var selected: GithubRepository?
    @State private var destination = ""
    @State private var cloneProtocol: GithubCloneProtocol = .https
    @State private var searchTask: Task<Void, Never>?

    enum Mode: String, CaseIterable, Identifiable {
        case folder
        case github
        var id: String { rawValue }
        var title: String { self == .folder ? "Add folder" : "Clone from GitHub" }
    }

    enum SearchState: Equatable {
        case idle
        case searching
        case empty
        case failed(String)
    }

    private var directory: WorkspaceDirectory { session.workspaceDirectory }
    private var canClone: Bool { directory.supportsGithubClone }
    private var canSearch: Bool { directory.supportsGithubRepositorySearch }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Add project", close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    modePicker
                    switch mode {
                    case .folder: folderMode
                    case .github: githubMode
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            if mode == .folder {
                addButton
            } else if let selected {
                cloneBar(repository: selected)
            }
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Mode picker

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(availableModes) { choice in
                Button {
                    Haptics.selection()
                    mode = choice
                } label: {
                    Text(choice.title)
                        .font(.paseo(.callout, weight: mode == choice ? .medium : .regular))
                        .foregroundStyle(
                            mode == choice ? Palette.background : Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 32)
                        .background(
                            mode == choice ? Palette.ink : Color.clear, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Palette.chip, in: .capsule)
        .padding(.top, 4)
    }

    private var availableModes: [Mode] {
        canClone ? Mode.allCases : [.folder]
    }

    // MARK: Folder mode

    private var folderMode: some View {
        VStack(alignment: .leading, spacing: 12) {
            RowGroup {
                HStack(spacing: 12) {
                    Text("Path")
                        .font(.paseo(.body))
                    Spacer(minLength: 8)
                    TextField(
                        "", text: $path,
                        prompt: Text("~/dev/my-app").foregroundStyle(Palette.secondaryInk)
                    )
                    .font(.paseo(.code))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
            }
            Text("The host registers an existing folder as a project. Nothing is created on disk.")
                .font(.paseo(.caption))
                .foregroundStyle(Palette.captionInk)
                .padding(.leading, 4)
            if let actionError = directory.actionError {
                Text(actionError)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
    }

    private var addButton: some View {
        Button {
            Task { await addFromPath() }
        } label: {
            HStack(spacing: 8) {
                if directory.isAddingProject {
                    ProgressView().controlSize(.small).tint(Palette.background)
                }
                Text(directory.isAddingProject ? "Adding…" : "Add project")
                    .font(.paseo(.callout, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(Palette.background)
            .background(Palette.ink, in: .capsule)
            .opacity(canAdd ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityIdentifier("addProject.confirm")
    }

    private var canAdd: Bool {
        !directory.isAddingProject
            && !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addFromPath() async {
        let target = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        guard let project = await directory.addProject(cwd: target) else { return }
        onDone("Added \(project.projectCustomName ?? project.projectDisplayName)")
        dismiss()
    }

    // MARK: GitHub mode

    private var githubMode: some View {
        VStack(alignment: .leading, spacing: 12) {
            if canSearch {
                searchField
            } else {
                Text("This host cannot search GitHub repositories.")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.vertical, 24)
            }
            if selected == nil {
                resultsSection
            } else {
                destinationSection
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.regular))
                .foregroundStyle(Palette.secondaryInk)
            TextField(
                "", text: $search,
                prompt: Text("Search repositories…").foregroundStyle(Palette.tertiaryInk)
            )
            .font(.paseo(.body))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: search) { _, query in scheduleSearch(query) }
            if searchState == .searching {
                ProgressView().controlSize(.small)
            } else if !search.isEmpty {
                Button {
                    search = ""
                    searchState = .idle
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.glyph(.regular))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Palette.chip, in: .capsule)
        .padding(.top, 2)
    }

    @ViewBuilder private var resultsSection: some View {
        switch searchState {
        case .idle:
            Text("Search your repositories to clone one.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.captionInk)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        case .searching:
            EmptyView()
        case .empty:
            Text("No repositories match “\(search)”.")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        case .failed(let message):
            Text(message)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.failureInk)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        if !results.isEmpty {
            RowGroup {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, repo in
                    resultRow(repo)
                    if index < results.count - 1 { RowDivider() }
                }
            }
        }
    }

    private func resultRow(_ repo: GithubRepository) -> some View {
        Button {
            Haptics.selection()
            selected = repo
            destination = defaultDestination(for: repo)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repo.nameWithOwner)
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if repo.visibility == .private {
                        Text("Private")
                            .font(.paseo(.caption2, weight: .semibold))
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Palette.chip, in: .capsule)
                    }
                    Spacer(minLength: 4)
                    Text(WorkspaceFileFormat.relativeModified(repo.updatedAt))
                        .font(.paseo(.caption2))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                if let description = repo.description, !description.isEmpty {
                    Text(description)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(repo.nameWithOwner), select")
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    Haptics.selection()
                    selected = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.glyph(.small, weight: .semibold))
                        Text("All repositories")
                            .font(.paseo(.footnote, weight: .medium))
                    }
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to search results")
            }
            if let selected {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox")
                        .font(.glyph(.regular))
                        .foregroundStyle(Palette.secondaryInk)
                    Text(selected.nameWithOwner)
                        .font(.paseo(.callout, weight: .medium))
                        .lineLimit(1)
                }
            }
            RowGroup {
                HStack(spacing: 12) {
                    Text("Into")
                        .font(.paseo(.callout))
                    Spacer(minLength: 8)
                    TextField(
                        "", text: $destination,
                        prompt: Text("~/src/repo").foregroundStyle(Palette.secondaryInk)
                    )
                    .font(.paseo(.code))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                RowDivider()
                HStack {
                    Text("Protocol")
                        .font(.paseo(.callout))
                    Spacer(minLength: 8)
                    Picker("Protocol", selection: $cloneProtocol) {
                        Text("HTTPS").tag(GithubCloneProtocol.https)
                        Text("SSH").tag(GithubCloneProtocol.ssh)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
            }
            if let actionError = directory.actionError {
                Text(actionError)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func cloneBar(repository: GithubRepository) -> some View {
        Button {
            Task { await clone(repository) }
        } label: {
            HStack(spacing: 8) {
                if directory.isCloning {
                    ProgressView().controlSize(.small).tint(Palette.background)
                }
                Text(directory.isCloning ? "Cloning…" : "Clone")
                    .font(.paseo(.callout, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(Palette.background)
            .background(Palette.ink, in: .capsule)
            .opacity(canCloneRepository(repository) ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canCloneRepository(repository))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityIdentifier("addProject.clone")
    }

    private func canCloneRepository(_ repository: GithubRepository) -> Bool {
        !directory.isCloning
            && !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repository.nameWithOwner.isEmpty
    }

    private func clone(_ repository: GithubRepository) async {
        let target = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        guard
            let project = await directory.cloneGithubProject(
                repo: repository.nameWithOwner, into: target, protocol: cloneProtocol)
        else { return }
        // The clone produced a project but no workspace; register the local checkout so there is
        // somewhere to land. Failure to do so is not fatal — the project itself was added.
        let created = await directory.createWorkspace(in: project, source: .local)
        let name = project.projectCustomName ?? project.projectDisplayName
        onDone(created == nil ? "Cloned \(name)" : "Cloned \(name) — workspace ready")
        dismiss()
    }

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            searchState = .idle
            return
        }
        searchState = .searching
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let found = await directory.searchGithubRepositories(trimmed, limit: 15)
            guard !Task.isCancelled else { return }
            results = found
            if found.isEmpty {
                if let error = directory.actionError {
                    searchState = .failed(error)
                } else {
                    searchState = .empty
                }
            } else {
                searchState = .idle
            }
        }
    }

    private func defaultDestination(for repo: GithubRepository) -> String {
        let parents = suggestedParents()
        guard let first = parents.first else { return repo.name }
        return first + "/" + repo.name
    }

    /// Parents of known projects, then home-relative candidates.
    private func suggestedParents() -> [String] {
        var parents: [String] = []
        var used = Set<String>()
        for project in directory.projects {
            let root = project.projectRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !root.isEmpty else { continue }
            let parent = (root as NSString).deletingLastPathComponent
            guard !parent.isEmpty, used.insert(parent).inserted else { continue }
            parents.append(parent)
        }
        for fallback in ["~/src", "~/Developer", "~/projects", "~"]
        where used.insert(fallback).inserted {
            parents.append(fallback)
        }
        return parents
    }
}
#endif
