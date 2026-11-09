#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension ClaudeChatView {
    // MARK: Find in conversation

    /// The seqEnd of the match currently on screen; nil when the results are empty.
    var findSeq: Int? {
        let locations = store.search.locations
        guard findIndex < locations.count else { return nil }
        return locations[findIndex].seq
    }

    var findBar: some View {
        ClaudeFindBar(
            typography: typography, query: $findQuery,
            isSearching: store.search.isSearching,
            resultCount: store.search.locations.count, currentIndex: findIndex,
            error: store.search.error,
            onStep: stepFind, onCancel: closeFind, focused: $findFocused)
    }

    func openFind() {
        Haptics.selection()
        guard !findOpen else { return }
        findAnchor = lastTrackedTurn // restore at turn granularity; bottom stays bottom
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { findOpen = true }
        findFocused = true
    }

    func closeFind() {
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { findOpen = false }
        findQuery = ""
        findSearchTask?.cancel()
        findSearchTask = nil
        store.search.clear()
        findFocused = false
    }

    func stepFind(_ delta: Int) {
        let locations = store.search.locations
        guard !locations.isEmpty else { return }
        let next = min(max(0, findIndex + delta), locations.count - 1)
        guard next != findIndex else { return }
        findIndex = next
        scrollToFindMatch(animated: true)
    }

    func scrollToFindMatch(animated: Bool) {
        guard let seq = findSeq else { return }
        flash(seq)
        guard let scrollProxy else { return }
        if animated {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                scrollProxy.scrollTo("row:\(seq)", anchor: .center)
            }
        } else {
            scrollProxy.scrollTo("row:\(seq)", anchor: .center)
        }
    }

    func flash(_ seq: Int) {
        findFlash = seq
        let captured = seq
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if findFlash == captured { findFlash = nil }
        }
    }

    func restoreScroll(proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            if let findAnchor, store.turns.contains(where: { $0.id == findAnchor }) {
                // The anchor belongs to this conversation (closing find on an agent switch may
                // leave it pointing at garbage from the previous one).
                proxy.scrollTo(findAnchor, anchor: .top)
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    func scheduleSearch(_ query: String) {
        findSearchTask?.cancel()
        findSearchTask = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            store.search.clear()
            return
        }
        findSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await store.search.search(trimmed)
            findIndex = 0
            scrollToFindMatch(animated: true)
        }
    }

}
#endif
