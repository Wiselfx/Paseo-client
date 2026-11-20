#if canImport(UIKit)
import AVFoundation
import Foundation
import OSLog
import PaseoStore

/// The voice lane's logger (E1 §3.4): the app's bundle id, category `voice`. A plain enum, not
/// a static on the engine, so the capture queue can use it without leaving the main actor.
/// Info for milestones, error for failures, nothing per audio buffer.
enum VoiceLog {
    static let log = Logger(subsystem: "com.wiselfx.paseoclient", category: "voice")
}
#endif
