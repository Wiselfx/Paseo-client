// features: F05 F10 F19
// Fixture: the same jobs done the way W6 does them: a binary search, an outward search for the nearest
// built index, one report slot instead of a dictionary, an owned fetch, compare-first flag writes.
import SwiftUI

@MainActor final class GoodHotProbe {
    private var lastReport: (seqEnd: Int, frame: CGRect)?

    func report(_ seqEnd: Int, _ frame: CGRect) {
        if lastReport?.seqEnd != seqEnd || lastReport?.frame != frame {
            lastReport = (seqEnd, frame)
        }
    }

    func frame(of seqEnd: Int) -> CGRect? {
        guard let lastReport, lastReport.seqEnd == seqEnd else { return nil }
        return lastReport.frame
    }
}

struct GoodHotReporter: ViewModifier {
    let seqEnd: Int
    @Environment(\.goodHotProbe) private var probe

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("viewport"))
        } action: { frame in
            probe.report(seqEnd, frame)
        }
    }
}

final class GoodHotJump {
    private var fetch: Task<Void, Never>?

    func scrollToMatch(_ seq: Int) {
        fetch?.cancel()
        fetch = Task { await load(seq) }
    }

    deinit { fetch?.cancel() }
}

func goodHop(all: [Turn], visible: Set<String>, target: Int) -> Int? {
    for distance in 0..<all.count {
        let below = target - distance
        if below >= 0, visible.contains(all[below].id) { return below }
        let above = target + distance
        if distance > 0, above < all.count, visible.contains(all[above].id) { return above }
    }
    return nil
}

func goodWindowStart(_ seq: Int, in turns: [Turn]) -> Int? {
    var low = 0
    var high = turns.count
    while low < high {
        let middle = low + (high - low) / 2
        if (turns[middle].lastSeq ?? Int.min) >= seq { high = middle } else { low = middle + 1 }
    }
    return low < turns.count ? low : nil
}

func goodRequestScroll(controller: GoodController) {
    if controller.isFollowing { controller.isFollowing = false }
    if controller.anchoringToAnswer { controller.anchoringToAnswer = false }
}
