#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Every page in Settings, as one value the navigation stack can push (PLAN §RE).
/// Leaf cases are the root rows; the rest are nested pages, so back always returns to the parent.
enum SettingsRoute: Hashable {
    // App
    case general
    case sidebar
    case terminal
    // Host
    case overview
    case hosts
    case hostDetail(UUID)
    case pairDevice
    case agents
    case metadata
    case metadataModel
    case voice
    case workspaces
    case projects
    case project(String)
    case providers
    case provider(String)
    // About
    case about
    case diagnostics
    case help

    /// The page's navigation title. `nil` when the page titles itself (a host, a project).
    var title: String? {
        switch self {
        case .general: "General"
        case .sidebar: "Sidebar"
        case .terminal: "Terminal"
        case .overview: "Overview"
        case .hosts: "Hosts"
        case .hostDetail: nil
        case .pairDevice: "Pair a device" // en.ts:2916 settings.host.pairDevices.rowTitle
        case .agents: "Agents"
        case .metadata: "Metadata"
        case .metadataModel: "Model"
        case .voice: "Voice"
        case .workspaces: "Workspaces"
        case .projects: "Projects"
        case .project: nil
        case .providers: "Providers"
        case .provider: nil
        case .about: "About"
        case .diagnostics: "Diagnostics"
        case .help: "Help & support"
        }
    }

    /// The row glyph. UX-SPEC §0.3: no `link`, and Model and Providers do not share a symbol.
    var symbol: String? {
        switch self {
        case .general: "gearshape"
        case .sidebar: "sidebar.left"
        case .terminal: "terminal"
        case .overview: "server.rack"
        case .hosts: "network"
        case .hostDetail: nil
        case .pairDevice: "qrcode"
        case .agents: "person.2"
        case .metadata: "wand.and.stars"
        case .metadataModel: "cpu"
        case .voice: "mic"
        case .workspaces: "square.stack"
        case .projects: "folder"
        case .project: nil
        case .providers: "square.stack.3d.up"
        case .provider: nil
        case .about: "info.circle"
        case .diagnostics: "stethoscope"
        case .help: "questionmark.circle"
        }
    }
}
#endif
