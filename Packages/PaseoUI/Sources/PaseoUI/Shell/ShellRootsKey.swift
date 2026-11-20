#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// See `ShellView.rootsKey`.
struct ShellRootsKey: Equatable {
    let session: ObjectIdentifier
    let selectedAgentId: String?
    let conversation: ObjectIdentifier?
    let draft: ObjectIdentifier?
    let homeSettled: Bool
    let panelTerminalId: String?
    let workspaceId: String?
    let directoryLoaded: Bool
    let directoryFailed: Bool
    let dynamicTypeSize: DynamicTypeSize
    let reduceMotion: Bool
    let codeSizeStep: Int
    let pureBlack: Bool
    let accent: ClaudeAccent
    let hostSwitch: ObjectIdentifier?
}
#endif
