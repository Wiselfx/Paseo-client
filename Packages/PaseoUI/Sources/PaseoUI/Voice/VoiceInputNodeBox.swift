#if canImport(UIKit)
import AVFoundation

/// Carries the voice input node across to the cooperative pool for `VoiceAudioEngine`'s
/// voice-processing switch. `AVAudioInputNode` is not `Sendable`, but the caller only starts that
/// switch on a stopped engine and touches nothing else on the graph until it returns (see
/// `VoiceAudioEngine.enableVoiceProcessingOffMain`). A top-level type, so it does not inherit the
/// main-actor isolation of `VoiceAudioEngine`.
struct VoiceInputNodeBox: @unchecked Sendable {
    let node: AVAudioInputNode
}
#endif
