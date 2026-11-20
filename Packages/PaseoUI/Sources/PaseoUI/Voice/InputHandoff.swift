#if canImport(UIKit)
import AVFoundation
import Foundation
import OSLog
import PaseoStore

/// One-buffer handoff: the converter keeps asking for input until the output is full, so
/// the second request must report end of stream.
final class InputHandoff {
    private var used = false
    func take(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard !used else { return nil }
        used = true
        return buffer
    }
}
#endif
