import Foundation

/// The system's completion handler, carried across the main-actor hop. UserNotifications
/// documents it as callable from any thread, exactly once; the coordinator calls it once.
final class CompletionBox: @unchecked Sendable {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    func call() { handler() }
}
