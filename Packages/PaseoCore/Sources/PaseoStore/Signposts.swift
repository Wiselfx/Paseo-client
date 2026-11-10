// R3: intervals the app can profile in Instruments without code changes. Signposts cost nothing
// when no profiler is recording.
//
// `os` (and `OSSignposter`) exists only in Apple's SDK. Linux, where PaseoCore is built and
// tested, gets a no-op shim with the same call shape, so the call sites compile unchanged. This is
// the one platform branch the R3 ticket allows; both halves are listed in the final message.

#if canImport(os)
import os

public enum PaseoSignpost {
    public static let log = OSSignposter(subsystem: "dev.paseo.client", category: "perf")
}

#else

/// Stand-in for `OSSignpostIntervalState` when signposts are unavailable.
public struct SignpostIntervalState: Sendable {}

/// Stand-in for `OSSignposter` with the same `beginInterval`/`endInterval` labels.
public struct NoopSignposter: Sendable {
    public init() {}

    public func beginInterval(_ name: StaticString) -> SignpostIntervalState {
        SignpostIntervalState()
    }

    public func endInterval(_ name: StaticString, _ state: SignpostIntervalState) {}
}

public enum PaseoSignpost {
    public static let log = NoopSignposter()
}

#endif
