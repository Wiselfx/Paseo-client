#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

enum ClaudeChatSheet: String, Identifiable {
    case controls
    case subagents
    case backgroundWork
    case turnNav
    case media
    var id: String { rawValue }
}

/// A rewind awaiting the can't-undo confirmation (M7d).
struct PendingRewind: Identifiable {
    let messageId: String
    let scope: RewindScope
    var id: String { "\(messageId)/\(scope)" }
}

/// What kind of rewind-based action is pending confirmation (M7h).
enum MessageActionKind: String {
    case edit
    case rerun
}

/// A message action awaiting the can't-undo confirmation (M7h).
struct PendingMessageAction: Identifiable {
    let messageId: String
    let text: String
    let kind: MessageActionKind
    var id: String { "\(kind.rawValue)/\(messageId)" }
}

/// Every modal the conversation presents: the agent-controls sheet, the subagents and background
/// work sheets, the prompt index, context usage, the file viewer, and the two confirmations that
/// belong to the timeline (message actions and rewinds). R4 owns the sheet bodies; this only
/// routes to them.
///
/// **Reads:** `store.subagents`, `store.backgroundWork`, `store.agent` (the file viewer's
/// workspace), `store.promptOutline` (the sheet's rows). All of it only while a sheet is open.
struct ChatSheets: ViewModifier {
    @Bindable var store: ConversationStore
    let session: HostSession
    @Bindable var controller: ChatController
    @Namespace private var artifactZoom

    func body(content: Content) -> some View {
        content
            .sheet(item: $controller.sheet) { item in
                sheet(item)
            }
            .sheet(isPresented: $controller.showContextSheet) {
                ClaudeContextSheet(store: store)
            }
            .sheet(isPresented: openFilePathBinding) {
                fileSheetContent
            }
            .fullScreenCover(item: $controller.inlineImage) { item in
                InlineProseImageViewer(item: item) { controller.inlineImage = nil }
            }
            .sheet(item: $controller.diffDocument) { document in
                SheetScaffold(document.fileName, detents: .large) {
                    ClaudeDiffView(
                        path: document.path, unifiedDiff: document.unifiedDiff,
                        old: document.old, new: document.new)
                }
            }
            .sheet(item: $controller.pushedSubagent) { subagent in
                SheetScaffold(subagent.title ?? "Subagent", detents: .large) {
                    ChatSubagentTimelineView(subagents: store.subagents, subagent: subagent)
                }
            }
            .environment(\.artifactZoomNamespace, artifactZoom)
            .fullScreenCover(item: $controller.artifactDocument) { document in
                ArtifactPage(
                    document: document,
                    sourceID: document.id,
                    namespace: artifactZoom,
                    onClose: { controller.artifactDocument = nil })
            }
            .confirmationDialog(
                controller.messageActionTitle,
                isPresented: messageActionBinding,
                titleVisibility: .visible,
                presenting: controller.pendingMessageAction
            ) { action in
                Button(action.kind == .edit ? "Rewind and edit" : "Rewind and rerun", role: .destructive) {
                    controller.pendingMessageAction = nil
                    Task { await controller.performMessageAction(action) }
                }
                Button("Cancel", role: .cancel) { controller.pendingMessageAction = nil }
            } message: { action in
                Text(controller.messageActionDescription(for: action))
            }
    }

    @ViewBuilder private func sheet(_ item: ClaudeChatSheet) -> some View {
        switch item {
        case .controls:
            ClaudeAgentControlsSheet(session: session, store: store)
        case .subagents:
            ChatSubagentsSheet(
                session: session, parentAgentId: store.agentId, subagents: store.subagents,
                hiddenIds: $controller.hiddenSubagentIds,
                onOpenAgent: { agentId in
                    controller.sheet = nil
                    controller.onOpenAgent?(agentId)
                })
        case .backgroundWork:
            ChatBackgroundWorkSheet(backgroundWork: store.backgroundWork)
        case .media:
            ChatMediaSheet(store: store)
        case .turnNav:
            ChatTurnNavSheet(
                store: store, items: controller.outlineItems,
                activeSeq: store.promptOutline.activeSeq
            ) { seq in
                controller.sheet = nil
                controller.jumpToPrompt(seq)
            }
        }
    }

    private var openFilePathBinding: Binding<Bool> {
        Binding(
            get: { controller.openFilePath != nil },
            set: { if !$0 { controller.openFilePath = nil } })
    }

    private var messageActionBinding: Binding<Bool> {
        Binding(
            get: { controller.pendingMessageAction != nil },
            set: { if !$0 { controller.pendingMessageAction = nil } })
    }

    @ViewBuilder private var fileSheetContent: some View {
        if let agent = store.agent,
            let workspaceId = agent.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        {
            NavigationStack {
                WorkspaceFileViewer(
                    checkout: session.checkout(for: workspace),
                    relPath: controller.openFilePath ?? "",
                    onBack: { controller.openFilePath = nil },
                    backLabel: "Files")
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        } else {
            // The agent's workspace isn't loaded (rare: directory fetch pending).
            EmptyState(
                systemImage: "exclamationmark.triangle", title: "Workspace not available",
                message: nil,
                action: (title: "Close", run: { controller.openFilePath = nil }))
                .presentationDetents([.height(240)])
        }
    }
}

/// An inline prose image the reader tapped (H5 round 2). A workspace path arrives already
/// decoded; a remote source is left to the viewer, which loads it through `MediaPipeline`.
struct InlineProseImage: Identifiable {
    let markdown: MarkdownImage
    let uiImage: UIImage?

    var id: String { markdown.source }
}

/// One file's diff, opened from the turn changes card (G6 C11): the tool call's own
/// unified diff when this conversation has one, else the file viewer.
struct ClaudeDiffDocument: Identifiable {
    var id: String { path }
    let path: String
    let unifiedDiff: String?
    let old: String?
    let new: String?

    /// The file name for the sheet title.
    var fileName: String {
        (path as NSString).lastPathComponent
    }
}

/// The full-screen viewer for an image tapped inside a sentence — the same `MediaViewerView`
/// the image cards use, so zoom, share and the chrome look identical everywhere.
struct InlineProseImageViewer: View {
    let item: InlineProseImage
    let onClose: () -> Void

    @Namespace private var zoom

    private var source: String {
        item.markdown.source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isRemote: Bool {
        let lower = source.lowercased()
        return ["http://", "https://", "data:", "blob:"].contains { lower.hasPrefix($0) }
    }

    private var fileName: String {
        let base = isRemote
            ? URL(string: source)?.lastPathComponent
            : (source as NSString).lastPathComponent
        guard let base, !base.isEmpty else { return "image" }
        return base
    }

    var body: some View {
        MediaViewerView(
            items: [
                MediaViewerItem(
                    id: "inline:\(source)",
                    thumbnail: item.uiImage,
                    fullSource: isRemote
                        ? MediaPipeline.target(for: source).map(MediaSource.remote) : nil,
                    fileName: fileName,
                    alt: item.markdown.alt.isEmpty ? fileName : item.markdown.alt,
                    filePath: isRemote ? nil : source)
            ],
            sourceID: "inline:\(source)",
            namespace: zoom,
            onClose: onClose,
            selection: .constant(0))
    }
}

#endif
