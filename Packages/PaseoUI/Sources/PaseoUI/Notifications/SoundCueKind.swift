#if canImport(UIKit)
import AVFoundation
import Foundation
import PaseoStore

/// Which cue a moment plays: Pop when an agent starts waiting, Tink when it finishes.
public enum SoundCueKind: Sendable, Equatable {
    case permission
    case completion
}
#endif
