#if canImport(Network)
import Foundation
import Network
import Observation


// NOTE: Apple-platforms only (G2 §12). This file compiles to nothing on Linux: `Network`
// does not exist there, and nothing below the UI reads the live path. The policy that
// consumes it (`MediaFetchPolicy` in PaseoStore) is platform-free and tested on Linux.

/// The §12 network signal: one small `@Observable` over `NWPathMonitor`.
///
/// It publishes the three facts the media policy needs — the interface class, Low Data Mode
/// (`isConstrained`) and cost (`isExpensive`) — and calls `onChange` for non-View owners
/// (the conversation controller mirrors the value into `RichActions`). Updates are rare
/// (only when the path changes) and always hop to the main actor before publishing, so a
/// SwiftUI read never observes a half-written value.
///
/// Assumed cheap and direct until the first update lands, matching today's behaviour.
@MainActor @Observable
public final class NetworkPathMonitor {
    /// The interface class the policy distinguishes.
    public enum Interface: Equatable, Sendable {
        case wifi
        case cellular
        case wired
        case other
    }

    public private(set) var interface: Interface = .wifi
    public private(set) var constrained = false
    public private(set) var expensive = false
    /// No usable path (`path.status != .satisfied`): cards stay cached.
    public private(set) var offline = false

    /// Called on every path change (main actor), after the published values update.
    public var onChange: (@MainActor (Interface, Bool, Bool, Bool) -> Void)?

    /// `NWPathMonitor` is Sendable, so plain `nonisolated` covers both the main-actor
    /// use and the `deinit` cancel.
    nonisolated private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "paseo.network-path", qos: .utility)

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let interface: Interface =
                if path.usesInterfaceType(.cellular) { .cellular }
                else if path.usesInterfaceType(.wifi) { .wifi }
                else if path.usesInterfaceType(.wiredEthernet) { .wired }
                else { .other }
            let constrained = path.isConstrained
            let expensive = path.isExpensive
            let offline = path.status != .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.interface = interface
                self.constrained = constrained
                self.expensive = expensive
                self.offline = offline
                self.onChange?(interface, constrained, expensive, offline)
            }
        }
        monitor.start(queue: queue)
    }

    /// Stops delivery. Called automatically on deallocation.
    public func stop() {
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}
#endif
