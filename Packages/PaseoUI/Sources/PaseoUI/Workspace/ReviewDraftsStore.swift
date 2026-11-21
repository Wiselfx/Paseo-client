#if canImport(UIKit)
import Foundation
import Observation
import PaseoProtocol
import UIKit

public enum ReviewDraftsStore {
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Paseo/review-drafts.json")
    }
}
#endif
