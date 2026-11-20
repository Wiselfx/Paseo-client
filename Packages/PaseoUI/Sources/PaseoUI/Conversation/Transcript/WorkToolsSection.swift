#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Every tool call of a work run as one section. Folded (the default) it is one line: "Called
/// 7 tools" and what they amounted to, or, while a call runs, that call live ("Running npm
/// test"). Folded it builds no step at all. Opened, the calls read as a hairline timeline, each
/// opening onto its own output; a long run keeps its newest steps with the older ones a tap away.
struct WorkToolsSection: View {
    /// The run's tool steps, file calls merged, thoughts left out.
    let steps: [WorkRow]
    let callCount: Int
    let failures: Int
    /// What the calls amounted to, such as "edited 3 files and ran 2 commands".
    let summary: String
    /// The call running right now, when this run is the turn's live tail.
    let live: WorkToolWording?
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?

    @State private var isOpen = false
    @State private var showsEarlier = false
    @State private var liveSince = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Past this many steps the opened run folds its older ones away…
    static let foldThreshold = 8
    /// …and keeps this many of the newest.
    static let keptSteps = 5

    private var title: String {
        callCount == 1 ? "Called 1 tool" : "Called \(PaseoFormat.integer(callCount)) tools"
    }

    private var accessibilityText: String {
        if let live { return [live.verb, live.target].compactMap { $0 }.joined(separator: " ") }
        return [title, summary].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkDigestHeader(
                icon: WorkIcon(kind: .tools, failed: failures > 0 && live == nil), isOpen: isOpen,
                accessibilityLabel: accessibilityText, action: toggle
            ) {
                headerTitle
            }
            // Folded, the line stands for every call; opened, each step anchors itself.
            .rowAnchors(isOpen ? [] : steps.flatMap(\.seqEnds))
            if isOpen {
                WorkToolSteps(
                    steps: steps, showsEarlier: showsEarlier,
                    foldThreshold: Self.foldThreshold, keptSteps: Self.keptSteps,
                    isLiveTail: live != nil, highlightedSeq: highlightedSeq,
                    findTarget: findTarget, onOpenFile: onOpenFile, onShowEarlier: showEarlier)
                    .transition(.opacity)
            }
        }
        .onChange(of: findTarget, initial: true) { _, target in reveal(target) }
    }

    @ViewBuilder private var headerTitle: some View {
        if let live {
            ClaudeSweepLabel(startedAt: liveSince, rest: Palette.tertiaryInk) { ink in
                WorkToolLine(verb: live.verb, target: live.target, ink: ink)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                WorkDigestTitle(text: title, ink: Palette.tertiaryInk)
                    .fixedSize()
                if !summary.isEmpty {
                    Text(summary)
                        .font(.paseo(.process))
                        .foregroundStyle(Palette.captionInk)
                        .lineLimit(1)
                }
                if failures > 0 {
                    Text("\(PaseoFormat.integer(failures)) failed")
                        .font(.paseo(.caption, weight: .medium))
                        .foregroundStyle(Palette.failureInk)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    private func toggle() {
        Haptics.selection()
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            isOpen.toggle()
        }
    }

    private func showEarlier() {
        Haptics.selection()
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            showsEarlier = true
        }
    }

    /// A find match in a call opens the section and, when the call is among the folded older
    /// steps, those too.
    private func reveal(_ target: Int?) {
        guard let target, let index = steps.firstIndex(where: { $0.covers(target) }) else { return }
        let folded =
            steps.count > Self.foldThreshold && index < steps.count - Self.keptSteps
        isOpen = true
        if folded { showsEarlier = true }
    }
}
#endif
