#if canImport(UIKit)
import Foundation

/// Which cue a moment plays: Pop when an agent starts waiting, Tink when it finishes.
public enum SoundCueKind: Sendable, Equatable {
    case permission
    case completion
}
#endif
