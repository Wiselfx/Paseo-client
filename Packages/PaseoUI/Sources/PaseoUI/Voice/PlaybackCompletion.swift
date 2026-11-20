#if canImport(UIKit)
import AVFoundation
import Foundation
import OSLog
import PaseoStore

/// Once-only continuation resume for a scheduled buffer (thinking tone, test tone): the
/// render completion and the safety timeout race, and exactly one of them resumes the
/// caller.
final class PlaybackCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func attach(_ cont: CheckedContinuation<Void, Never>) {
        lock.lock()
        if finished { lock.unlock(); cont.resume(); return }
        continuation = cont
        lock.unlock()
    }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}
#endif
