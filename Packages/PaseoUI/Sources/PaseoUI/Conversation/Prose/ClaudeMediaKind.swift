import Foundation

/// Metadata only. The host supplies pixels through ClaudeSessionView's mediaContent closure.
public enum ClaudeMediaKind: Equatable, Sendable { case image, video }
