import Foundation
import PaseoKit
import PaseoProtocol
import PaseoStore
import SwiftUI
import UIKit
import XCTest

@testable import PaseoUI

/// A measurement, not a pass/fail test: it scrolls the real transcript engine up through a synthetic
/// history in small steps and writes numbers (report.json, report.md) to `TRANSCRIPT_HARNESS_OUT`.
/// It fails only when the harness itself cannot run.
///
/// The real `TranscriptView` is hosted in a 393x852 window. The conversation is built by production
/// code from a fake daemon's timeline page (`SyntheticHistory`), so turns, cells and layout are the
/// app's own. See the report for how each number is measured.
@MainActor
final class TranscriptHarnessTests: XCTestCase {
    private struct HarnessError: Error, CustomStringConvertible {
        let description: String
    }

    private struct Hosted {
        let window: UIWindow
        let host: UIHostingController<TranscriptView>
        let collectionView: TranscriptCollectionView
        let engine: TranscriptEngine
    }

    private struct CellSample {
        var item: String
        var index: Int
        var screenY: Double
        var cellHeight: Double
        var drawnHeight: Double?
        var onScreen: Bool
    }

    private enum Mode: String {
        /// A finger on the screen: `isDragging`.
        case drag
        /// A flick coasting: `isDecelerating`.
        case flick
    }

    private struct PassSpec {
        var name: String
        var stepSize: CGFloat
        var mode: Mode
    }

    private static let turnHeightKey = "paseo.turnHeights.v1"
    private static let screen = CGRect(x: 0, y: 0, width: 393, height: 852)
    /// The bars over the transcript: status bar and header on top, home indicator and composer below.
    private static let safeArea = UIEdgeInsets(top: 103, left: 0, bottom: 94, right: 0)
    private static let stepPause: Duration = .milliseconds(16)
    private static let maxPassSeconds: TimeInterval = 420
    private static let maxSteps = 8000

    private var notes: [String] = []

    // MARK: Test

    func testScrollUpThroughHistory() async throws {
        let outDirectory =
            ProcessInfo.processInfo.environment["TRANSCRIPT_HARNESS_OUT"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("transcript-harness")
        try FileManager.default.createDirectory(atPath: outDirectory, withIntermediateDirectories: true)

        UserDefaults.standard.removeObject(forKey: Self.turnHeightKey)

        let turnCount = 40
        let client = SyntheticDaemonClient(page: try SyntheticHistory.page(turns: turnCount))
        let session = HostSession(client: client)
        let store = session.conversation(for: SyntheticHistory.agentId)
        var waited = 0
        while store.phase != .ready && waited < 500 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 1
        }
        guard store.phase == .ready else { throw HarnessError(description: "store never became ready: \(store.phase)") }
        guard store.turns.count == turnCount else {
            throw HarnessError(description: "expected \(turnCount) turns, the store built \(store.turns.count)")
        }
        let controller = ChatController(session: session, store: store)

        var labels: [String: String] = [:]
        for (position, turn) in store.turns.enumerated() {
            labels[String(describing: TranscriptItemID.turn(turn.id))] =
                "t\(position) \(SyntheticHistory.kind(position))"
        }
        labels[String(describing: TranscriptItemID.historyStart)] = "historyStart"

        let recorder = HarnessRecorder(labels: labels)
        recorder.install()
        defer { recorder.uninstall() }

        let both = [
            PassSpec(name: "drag12", stepSize: 12, mode: .drag),
            PassSpec(name: "flick40", stepSize: 40, mode: .flick),
        ]
        // A: a cold open, no remembered heights.
        try await runScenario(
            "A-scroll-up", passes: both, store: store, controller: controller, recorder: recorder,
            persistHeightsAfter: true)
        // B: the same store, a new engine and view; the heights A measured are remembered now.
        let remembered = TurnHeightStore.load().count
        notes.append("B started with \(remembered) remembered turn heights")
        try await runScenario(
            "B-reopen", passes: both, store: store, controller: controller, recorder: recorder,
            persistHeightsAfter: false)
        // C: a cold open again, flick only: estimates meet a decelerating scroll.
        try await Task.sleep(for: .milliseconds(500))
        UserDefaults.standard.removeObject(forKey: Self.turnHeightKey)
        try await Task.sleep(for: .milliseconds(200))
        notes.append("C started with \(TurnHeightStore.load().count) remembered turn heights")
        try await runScenario(
            "C-cold-flick", passes: [both[1]], store: store, controller: controller, recorder: recorder,
            persistHeightsAfter: false)

        let device = UIDevice.current
        let deviceNote =
            "Simulator \(device.model) iOS \(device.systemVersion), window \(Int(Self.screen.width))x\(Int(Self.screen.height)), "
            + "safe area top \(Int(Self.safeArea.top)) bottom \(Int(Self.safeArea.bottom)), \(turnCount) synthetic turns. "
            + "Notes: " + notes.joined(separator: "; ") + "."
        let markdown = HarnessReport.markdown(passes: recorder.passes, deviceNote: deviceNote)
        let json = try HarnessReport.json(passes: recorder.passes, deviceNote: deviceNote)
        try markdown.write(toFile: (outDirectory as NSString).appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        try json.write(to: URL(fileURLWithPath: (outDirectory as NSString).appendingPathComponent("report.json")))

        print(markdown)
        let attachment = XCTAttachment(string: markdown)
        attachment.name = "report.md"
        attachment.lifetime = .keepAlways
        add(attachment)
        withExtendedLifetime(session) {}
    }

    // MARK: Scenario

    private func runScenario(
        _ scenario: String, passes: [PassSpec], store: ConversationStore, controller: ChatController,
        recorder: HarnessRecorder, persistHeightsAfter: Bool
    ) async throws {
        recorder.current = nil
        let hosted = try await makeHosted(store: store, controller: controller)
        for (position, spec) in passes.enumerated() {
            if position > 0 { try await returnToEnd(hosted) }
            let pass = PassData(
                scenario: scenario, name: spec.name, stepSize: Double(spec.stepSize), mode: spec.mode.rawValue)
            recorder.begin(pass)
            try await runPass(pass, spec: spec, hosted: hosted, recorder: recorder)
        }
        recorder.current = nil
        if persistHeightsAfter {
            TurnHeightStore.save(hosted.engine.heightMemory.persisted)
            try await Task.sleep(for: .milliseconds(600))
        }
        hosted.window.isHidden = true
        hosted.window.rootViewController = nil
        try await Task.sleep(for: .milliseconds(300))
    }

    private func makeHosted(store: ConversationStore, controller: ChatController) async throws -> Hosted {
        let host = UIHostingController(rootView: TranscriptView(store: store, controller: controller))
        host.additionalSafeAreaInsets = Self.safeArea
        let window = UIWindow(frame: Self.screen)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        var found: TranscriptCollectionView?
        var tries = 0
        while found == nil && tries < 500 {
            found = Self.findCollectionView(in: window)
            if found == nil {
                try await Task.sleep(for: .milliseconds(10))
                tries += 1
            }
        }
        guard let collectionView = found, let engine = collectionView.engine else {
            throw HarnessError(description: "the transcript's collection view never appeared")
        }
        let expected = store.turns.count + 1
        tries = 0
        while engine.items.count < expected && tries < 500 {
            try await Task.sleep(for: .milliseconds(20))
            tries += 1
        }
        guard engine.items.count == expected else {
            throw HarnessError(description: "the engine has \(engine.items.count) items, expected \(expected)")
        }
        // Settle at the end: the first layout pass pins to it; cells near it measure.
        try await Task.sleep(for: .seconds(1))
        guard collectionView.bounds.height > 800 else {
            throw HarnessError(description: "collection view height \(collectionView.bounds.height) is not window sized")
        }
        return Hosted(window: window, host: host, collectionView: collectionView, engine: engine)
    }

    private static func findCollectionView(in view: UIView) -> TranscriptCollectionView? {
        if let collectionView = view as? TranscriptCollectionView { return collectionView }
        for subview in view.subviews {
            if let found = findCollectionView(in: subview) { return found }
        }
        return nil
    }

    private func returnToEnd(_ hosted: Hosted) async throws {
        let collectionView = hosted.collectionView
        for _ in 0..<2 {
            collectionView.contentOffset = CGPoint(x: 0, y: hosted.engine.maxOffsetY)
            try await Task.sleep(for: .milliseconds(700))
        }
        hosted.engine.scrollViewDidEndDragging(collectionView, willDecelerate: false)
    }

    // MARK: Pass

    private func runPass(_ pass: PassData, spec: PassSpec, hosted: Hosted, recorder: HarnessRecorder) async throws {
        let collectionView = hosted.collectionView
        let engine = hosted.engine
        let started = Date()
        notes.append(
            "\(pass.title) starts at offset \(Int(collectionView.contentOffset.y)) of max \(Int(engine.maxOffsetY)), "
                + "min \(Int(engine.minOffsetY)), content \(Int(collectionView.contentSize.height)) pt, inset top \(Int(collectionView.contentInset.top))")

        // The finger (or the flick) takes over, the way the delegate hears it.
        engine.scrollViewWillBeginDragging(collectionView)
        switch spec.mode {
        case .drag: TranscriptProbe.simulatedDragging = true
        case .flick: TranscriptProbe.simulatedDecelerating = true
        }

        var previous = sample(hosted, pass: pass, recorder: recorder, record: false, atRest: false)
        var step = 0
        while collectionView.contentOffset.y > engine.minOffsetY + 0.5 && step < Self.maxSteps {
            if Date().timeIntervalSince(started) > Self.maxPassSeconds {
                notes.append("\(pass.title) stopped at step \(step): time budget")
                break
            }
            step += 1
            pass.currentStep = step
            let before = collectionView.contentOffset.y
            let requested = max(before - spec.stepSize, engine.minOffsetY)
            collectionView.contentOffset = CGPoint(x: 0, y: requested)
            try await Task.sleep(for: Self.stepPause)
            let now = sample(hosted, pass: pass, recorder: recorder, record: true, atRest: false)
            compare(previous: previous, now: now, commanded: Double(before - requested), pass: pass, step: step, recorder: recorder)
            pass.steps.append(
                StepRecord(
                    step: step, requestedOffset: Double(requested), actualOffset: Double(collectionView.contentOffset.y),
                    visibleCells: now.count, onScreenCells: now.values.filter(\.onScreen).count))
            previous = now
        }

        // The finger lifts: the pass ends where the delegate would hear it.
        pass.currentStep = -2
        switch spec.mode {
        case .drag:
            TranscriptProbe.simulatedDragging = false
            engine.scrollViewDidEndDragging(collectionView, willDecelerate: false)
        case .flick:
            TranscriptProbe.simulatedDecelerating = false
            engine.scrollViewDidEndDecelerating(collectionView)
        }
        try await Task.sleep(for: .milliseconds(700))
        let rest = sample(hosted, pass: pass, recorder: recorder, record: true, atRest: true)
        compare(previous: previous, now: rest, commanded: 0, pass: pass, step: -2, recorder: recorder)
        pass.wallSeconds = Date().timeIntervalSince(started)
    }

    /// Unexplained motion: how far a cell moved on screen beyond what the scroll commanded. A cell
    /// that scrolls by exactly the commanded step reads 0, whether or not the engine compensated.
    private func compare(
        previous: [String: CellSample], now: [String: CellSample], commanded: Double, pass: PassData,
        step: Int, recorder: HarnessRecorder
    ) {
        for (key, sample) in now {
            guard let was = previous[key] else { continue }
            let unexplained = (sample.screenY - was.screenY) - commanded
            guard abs(unexplained) > 0.5 else { continue }
            pass.jumps.append(
                JumpRecord(
                    step: step, item: recorder.label(key), amount: unexplained, screenYPrevious: was.screenY,
                    screenYNow: sample.screenY, commandedMotion: commanded, onScreen: sample.onScreen || was.onScreen,
                    context: pass.context(forStep: step)))
        }
    }

    /// Reads every visible cell: where it is on screen, its frame height, and the height SwiftUI would
    /// draw it at right now (`systemLayoutSizeFitting` of the cell's content view at the cell's width with
    /// no height offered: the same measurement the cell reports to the layout, repeated live. The content
    /// is pinned to the cell's top at its natural height, so this is the drawn height).
    private func sample(
        _ hosted: Hosted, pass: PassData, recorder: HarnessRecorder, record: Bool, atRest: Bool
    ) -> [String: CellSample] {
        let collectionView = hosted.collectionView
        let engine = hosted.engine
        let overscan = Double(TranscriptContainerView.overscan)
        let offset = Double(collectionView.contentOffset.y)
        let screenTop = offset + overscan
        let screenBottom = offset + Double(collectionView.bounds.height)
        var out: [String: CellSample] = [:]
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell), engine.items.indices.contains(indexPath.item)
            else { continue }
            let key = String(describing: engine.items[indexPath.item])
            let frame = cell.frame
            let onScreen = Double(frame.maxY) > screenTop && Double(frame.minY) < screenBottom
            var drawn: Double?
            if let transcriptCell = cell as? TranscriptCell, transcriptCell.fixedHeight == nil {
                let fitting = cell.contentView.systemLayoutSizeFitting(
                    CGSize(width: cell.bounds.width, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
                drawn = Double(fitting.height)
            }
            let entry = CellSample(
                item: key, index: indexPath.item, screenY: Double(frame.minY) - offset - overscan,
                cellHeight: Double(cell.bounds.height), drawnHeight: drawn, onScreen: onScreen)
            out[key] = entry
            if record, let drawn {
                pass.mismatchSamples += 1
                if onScreen { pass.mismatchSamplesOnScreen += 1 }
                if abs(entry.cellHeight - drawn) > 0.5 {
                    pass.mismatches.append(
                        MismatchRecord(
                            step: pass.currentStep, item: recorder.label(key), cellHeight: entry.cellHeight,
                            drawnHeight: drawn, onScreen: onScreen, atRest: atRest))
                }
            }
        }
        return out
    }
}
