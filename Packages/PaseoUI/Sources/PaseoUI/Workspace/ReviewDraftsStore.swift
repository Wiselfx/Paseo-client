#if canImport(UIKit)
import Foundation
import Observation
import PaseoProtocol
import UIKit

public enum ReviewDraftsStore {
    public static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("Paseo/review-drafts.json")
    }
}
#endif
