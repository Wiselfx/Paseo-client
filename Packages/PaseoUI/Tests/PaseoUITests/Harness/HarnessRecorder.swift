import Foundation
@testable import PaseoUI

/// Receives the engine's probe events and files them under the pass that is running.
@MainActor
final class HarnessRecorder {
    var current: PassData?
    private(set) var passes: [PassData] = []
    private let labels: [String: String]

    init(labels: [String: String]) { self.labels = labels }

    func label(_ item: String) -> String { labels[item] ?? item }

    func begin(_ pass: PassData) {
        passes.append(pass)
        current = pass
    }

    func install() {
        TranscriptProbe.sink = { [unowned self] event in self.record(event) }
    }

    func uninstall() {
        TranscriptProbe.sink = nil
        TranscriptProbe.simulatedDragging = false
        TranscriptProbe.simulatedDecelerating = false
    }

    private func record(_ event: TranscriptProbe.Event) {
        guard let pass = current else { return }
        switch event {
        case .invalidation(let index, let id, let old, let new, let first, let compensated, let branch, let frame, let readerTop):
            let position: String
            if frame.maxY <= readerTop + 0.5 {
                position = "above"
            } else if frame.minY < readerTop - 0.5 {
                position = "straddling"
            } else {
                position = "below"
            }
            pass.invalidations.append(
                InvalidationRecord(
                    step: pass.currentStep, item: label(id), index: index, oldHeight: Double(old),
                    newHeight: Double(new), firstMeasure: first, compensated: compensated,
                    branch: branch.rawValue, position: position, frameMinY: Double(frame.minY),
                    frameMaxY: Double(frame.maxY), readerTop: Double(readerTop)))
        case .offsetWrite(let site, let from, let to):
            pass.offsetWrites.append(
                OffsetWriteRecord(step: pass.currentStep, site: site, from: Double(from), to: Double(to)))
        case .dequeue(let index, let id, let hadMeasured, let height):
            pass.dequeues.append(
                DequeueRecord(
                    step: pass.currentStep, item: label(id), index: index, hadMeasured: hadMeasured,
                    height: Double(height)))
        }
    }
}
