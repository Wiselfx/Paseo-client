#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Every modal the conversation presents: the agent-controls sheet, the subagents and background
/// work sheets, the prompt index, context usage, the file viewer, and the rewind confirmation
/// that belongs to the timeline. R4 owns the sheet bodies; this only
/// routes to them.
///
/// **Reads:** `store.subagents`, `store.backgroundWork`, `store.agent` (the file viewer's
/// workspace), `store.promptOutline` (the sheet's rows). All of it only while a sheet is open.
struct ChatSheets: ViewModifier {
    @Bindable var store: ConversationStore
    let session: HostSession
    @Bindable var controller: ChatController
    @Namespace private var artifactZoom
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .sheet(item: $controller.sheet) { item in
                ChatSheetRouter(item: item, store: store, session: session, controller: controller)
            }
            .sheet(isPresented: $controller.showContextSheet) {
                ClaudeContextSheet(store: store)
            }
            .sheet(isPresented: $controller.isFileViewerOpen) {
                ChatFileSheet(store: store, session: session, controller: controller)
            }
            .fullScreenCover(item: $controller.inlineImage) { item in
                InlineProseImageViewer(item: item) { controller.inlineImage = nil }
            }
            .sheet(item: $controller.diffDocument) { document in
                SheetScaffold(document.fileName, detents: .large) {
                    ClaudeDiffView(
                        path: document.path, unifiedDiff: document.unifiedDiff,
                        old: document.old, new: document.new, fullHeight: true)
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
            // A managed subagent this chat is showing is marked open so archiving its parent
            // detaches it instead of cascade-archiving the agent the user is looking at. Set when
            // the tab opens (once the snapshot names a parent), cleared when it closes or the app
            // leaves the foreground. Upstream: docs/agent-lifecycle.md:130-134,
            // packages/app/src/subagents/use-open-agent-tab-labels.ts:40-80,
            // packages/app/src/screens/workspace/workspace-screen.tsx:2028-2034.
            .task(id: openAgentTabKey) {
                guard openAgentTabKey != nil, scenePhase == .active else { return }
                await session.agentLifecycle.setOpenAgentTab(agentId: store.agentId, open: true)
            }
            .onChange(of: scenePhase) { _, phase in
                guard isManagedSubagent else { return }
                Task {
                    await session.agentLifecycle.setOpenAgentTab(
                        agentId: store.agentId, open: phase == .active)
                }
            }
            .onDisappear {
                guard isManagedSubagent else { return }
                Task { await session.agentLifecycle.setOpenAgentTab(agentId: store.agentId, open: false) }
            }
    }

    /// True while this conversation is a managed subagent (it names a parent). Provider-managed
    /// children have no agent row or labels and are never marked.
    private var isManagedSubagent: Bool {
        AgentParentLabel.parent(of: store.agent?.labels) != nil
    }

    /// Re-runs the marking task when the snapshot first says this agent is a managed subagent.
    private var openAgentTabKey: String? { isManagedSubagent ? store.agentId : nil }
}
#endif
