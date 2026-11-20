#if canImport(UIKit)
import PaseoStore
import SafariServices
import SwiftUI
import UIKit
import WebKit

/// The checkout a file preview reads its relative references from.
struct PreviewFileSource {
    let files: WorkspaceFiles
    let workspaceId: String
}
#endif
