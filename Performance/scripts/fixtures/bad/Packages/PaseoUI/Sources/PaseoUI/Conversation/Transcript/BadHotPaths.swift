// features: F05 F10 F19
// Fixture: the per-tick and per-frame work the find-in-chat pass got wrong before W6, in the shapes the
// checks must catch: a linear scan in a helper, an array of every index per tick, a Task started from a
// method with no handle, a dictionary write from a geometry callback, a flag written with a literal.
import SwiftUI

@MainActor final class BadHotProbe {
    private var frames: [Int: CGRect] = [:]

    func report(_ seqEnd: Int, _ frame: CGRect) { frames[seqEnd] = frame }
}

struct BadHotReporter: ViewModifier {
    let seqEnd: Int
    @Environment(\.badHotProbe) private var probe

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("viewport"))
        } action: { frame in
            probe.report(seqEnd, frame) // hit: H31
        }
    }
}

final class BadHotJump {
    func scrollToMatch(_ seq: Int) {
        Task { // hit: H30
            await load(seq)
        }
    }
}

func badHop(all: [Turn], visible: Set<String>) -> Int? {
    let built = all.indices.filter { visible.contains(all[$0].id) } // expect: C48
    return built.first
}

func badWindowStart(_ seq: Int, in turns: [Turn]) -> Int? {
    turns.firstIndex { ($0.lastSeq ?? Int.min) >= seq } // hit: H29
}

func badRequestScroll(controller: BadController) {
    controller.isFollowing = false // expect: C49
    controller.anchoringToAnswer = false // expect: C49
}
