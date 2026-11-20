import Foundation

public struct ClaudeMedia: Identifiable, Equatable, Sendable {
    public var id: String
    public var fileName: String
    public var accessibilityDescription: String
    public var kind: ClaudeMediaKind
    public var aspectRatio: Double
    public init(
        id: String, fileName: String, accessibilityDescription: String = "Photo", aspectRatio: Double = 1,
        kind: ClaudeMediaKind = .image
    ) {
        self.kind = kind
        self.id = id
        self.fileName = fileName
        self.accessibilityDescription = accessibilityDescription
        self.aspectRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
    }
    public var fileExtension: String { (fileName as NSString).pathExtension.uppercased() }
    public var fileStem: String { (fileName as NSString).deletingPathExtension }
    public var displayAspectRatio: Double { aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1 }
}
