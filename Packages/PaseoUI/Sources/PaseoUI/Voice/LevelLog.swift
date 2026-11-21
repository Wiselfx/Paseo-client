#if canImport(UIKit)
import AVFoundation
import PaseoStore
import Speech
import SwiftUI

/// One dB line a second from the tap. The tap is not on the main actor, so the throttle is
/// lock-guarded rather than a property of the controller (H1 §1 asks for the raw numbers).
final class LevelLog: @unchecked Sendable {
    private let lock = NSLock()
    private var last: TimeInterval = 0

    func log(rms: Float, eased: Float, at now: TimeInterval = Date.now.timeIntervalSince1970) {
        lock.lock()
        guard now - last >= 1 else {
            lock.unlock()
            return
        }
        last = now
        lock.unlock()
        let db = 20 * log10(max(rms, 1e-5))
        VoiceLog.log.debug(
            "dictation level db=\(db.formatted(.number.precision(.fractionLength(1))), privacy: .public) eased=\(eased.formatted(.number.precision(.fractionLength(3))), privacy: .public)")
    }

    func reset() {
        lock.lock()
        last = 0
        lock.unlock()
    }
}
#endif
