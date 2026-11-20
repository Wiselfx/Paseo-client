import Foundation

public struct ClaudeMediaState: Equatable, Sendable {
    public var recent: [ClaudeMedia] = []
    public var draft: [ClaudeMedia] = []
    public private(set) var selectedIDs: [String] = []
    public private(set) var viewer: ClaudeMedia?
    public private(set) var controlsVisible = true
    public init() {}
    public var selected: [ClaudeMedia] { selectedIDs.compactMap { id in recent.first(where: { $0.id == id }) } }
    public mutating func reduce(_ action: ClaudeMediaAction) {
        switch action {
        case .beginSelection, .cancelSelection: selectedIDs = []
        case .toggleRecent(let id):
            guard recent.contains(where: { $0.id == id }) else { return }
            if selectedIDs.contains(id) { selectedIDs.removeAll { $0 == id } } else { selectedIDs.append(id) }
        case .attachSelected:
            for item in selected where !draft.contains(where: { $0.id == item.id }) { draft.append(item) }
            selectedIDs = []
        case .removeDraft(let id):
            draft.removeAll { $0.id == id }
            if viewer?.id == id { viewer = nil }
        case .open(let item):
            viewer = item
            controlsVisible = true
        case .close:
            viewer = nil
            controlsVisible = true
        case .toggleControls: if viewer?.kind == .image { controlsVisible.toggle() }
        case .requestPhotos, .copyFileName, .edit, .share, .download, .videoViewerAppeared, .videoViewerDisappeared:
            break
        }
    }
}
