#if canImport(UIKit)
import Foundation

/// The app target's door to notification thumbnails (§11). `MediaPipeline` is internal to
/// PaseoUI; this is the one public, read-only probe the notification coordinator needs.
/// It never fetches: nil means nothing is cached and the notification posts without an image.
public enum NotificationThumbnails {
    public static func cachedData(
        remoteURL: String? = nil, daemonPath: String? = nil, workspaceID: String? = nil
    ) -> Data? {
        MediaPipeline.cachedNotificationThumbnail(
            remoteURL: remoteURL, daemonPath: daemonPath, workspaceID: workspaceID)
    }
}
#endif
