#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The sheet's three sections (G12 §15: the tab names are upstream's).
enum MediaSheetTab: String, CaseIterable, Identifiable {
    case media
    case links
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .links: "Links"
        case .files: "Files"
        }
    }
}
#endif
