#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// One generation counter shared by the Files pages: only the newest refresh's result is
/// trusted, so two pages can never render each other's listing. All Files state lives on the
/// main actor.
@MainActor enum WorkspaceFilesRefresh {
    static var generation = 0
}
#endif
