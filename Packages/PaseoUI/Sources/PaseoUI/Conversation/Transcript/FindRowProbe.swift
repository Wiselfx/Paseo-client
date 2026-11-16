#if canImport(UIKit)
import SwiftUI

/// Where the current find match's row really is, so the jump runner can tell that it arrived.
///
/// Aiming at a row id is a request, not a result: when the stack is mid-layout the request can leave the
/// viewport on the turn's top, thousands of points from the row (a wrap to the far end of a 90 000 pt chat
/// did). Only the row of the current match reports (`FindRowReporter`, on its highlight background), in the
/// transcript viewport's space (where it is on screen now; a frame in content space went stale while the
/// stack re-estimated the rows above it), and only while find is open: a plain reference the transcript reads, never
/// observed. One match is on screen at a time, so the probe keeps one report: a report is a store, with no hashing
/// and no growth, and a scroll frame that moves the match costs nothing more.
@MainActor final class FindRowProbe {
    private var lastReport: (seqEnd: Int, frame: CGRect)?

    func report(_ seqEnd: Int, _ frame: CGRect) { lastReport = (seqEnd, frame) }

    func frame(of seqEnd: Int) -> CGRect? {
        guard let lastReport, lastReport.seqEnd == seqEnd else { return nil }
        return lastReport.frame
    }

    func reset() { lastReport = nil }
}

private struct FindRowProbeKey: EnvironmentKey {
    static let defaultValue: FindRowProbe? = nil
}

extension EnvironmentValues {
    /// The transcript's find row probe; nil outside the transcript.
    var findRowProbe: FindRowProbe? {
        get { self[FindRowProbeKey.self] }
        set { self[FindRowProbeKey.self] = newValue }
    }
}

/// Reports the row's frame, in the transcript viewport's space, when it is the current find match.
struct FindRowReporter: ViewModifier {
    let seqEnd: Int
    let isTarget: Bool
    @Environment(\.findRowProbe) private var probe

    func body(content: Content) -> some View {
        if isTarget, let probe {
            content.onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named(TranscriptScrollTrack.viewportSpace))
            } action: { frame in
                probe.report(seqEnd, frame)
            }
        } else {
            content
        }
    }
}

extension View {
    /// See `FindRowReporter`.
    func reportsFindRow(_ seqEnd: Int, isTarget: Bool) -> some View {
        modifier(FindRowReporter(seqEnd: seqEnd, isTarget: isTarget))
    }
}
#endif
