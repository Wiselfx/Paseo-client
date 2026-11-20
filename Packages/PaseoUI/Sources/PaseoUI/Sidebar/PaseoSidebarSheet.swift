#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

enum PaseoSidebarSheet: Identifiable {
    case settings
    case schedules
    case history
    case search
    case newWorkspace
    case addProject
    case importSession
    case usage
    case newLabel(WorkspaceDescriptor)
    case labelsManager
    case project(WorkspaceProjectDescriptor)

    var id: String {
        switch self {
        case .settings: "settings"
        case .schedules: "schedules"
        case .history: "history"
        case .search: "search"
        case .newWorkspace: "newWorkspace"
        case .addProject: "addProject"
        case .importSession: "importSession"
        case .usage: "usage"
        case .newLabel(let target): "newLabel:\(target.id)"
        case .labelsManager: "labelsManager"
        case .project(let target): "project:\(target.projectId)"
        }
    }
}
#endif
