#if canImport(UIKit) && arch(arm64)
    import Darwin
    import Foundation
    import os
    import QuartzCore

    /// A sampling profiler for the main thread, standing in for Instruments' Time Profiler (W1).
    ///
    /// The gate has no `xctrace`, so the stall watcher cannot say *what* ran inside a stall. This
    /// thread wakes every millisecond; while the main thread has been inside one run-loop wake for
    /// more than `PerfSampler.after`, it suspends the main thread, walks the frame-pointer chain
    /// into a preallocated buffer (no allocation and no lock while the thread is suspended), resumes
    /// it, and only then symbolicates. Each window line gets the hottest leaf frames and the hottest
    /// first frame inside the app's own code, which is where a fix goes.
    ///
    /// Off with the rest of `PaseoPerf`; started by `PerfMonitor.start()` only under `-paseo-perf`.
    final class PerfSampler: @unchecked Sendable {
        static let shared = PerfSampler()

        /// Sample once the main thread has been busy this long (seconds).
        static let after: Double = 0.004
        private static let maxDepth = 48

        /// One window's histograms, built on the sampler thread so the main thread never pays for
        /// symbolication (a first cut did, and its own stalls were what it measured).
        struct Histogram: Sendable {
            var samples = 0
            var leaf: [String: Int] = [:]
            var own: [String: Int] = [:]
            /// The eight innermost frames with a name, leaf first: who calls the leaf (a protocol
            /// conformance lookup, a `mach_msg` wait) is the part a fix needs.
            var stack: [String: Int] = [:]
        }

        /// The wake the main thread is inside, or 0 when it sleeps. Written by `PerfMonitor`.
        private let busySince = OSAllocatedUnfairLock<Double>(initialState: 0)
        private let collected = OSAllocatedUnfairLock<Histogram>(initialState: Histogram())
        /// Only the sampler thread touches it.
        private var symbolCache: [UInt: Symbol] = [:]

        private var mainThread: mach_port_t = 0
        private var stackLow: UInt = 0
        private var stackHigh: UInt = 0
        private var started = false

        func markBusy(_ since: Double) {
            busySince.withLock { $0 = since }
        }

        /// Call on the main thread.
        func start() {
            guard !started else { return }
            started = true
            let self_ = pthread_self()
            mainThread = pthread_mach_thread_np(self_)
            let top = pthread_get_stackaddr_np(self_)
            let size = pthread_get_stacksize_np(self_)
            stackHigh = UInt(bitPattern: top)
            stackLow = stackHigh &- UInt(size)
            let thread = Thread { [self] in loop() }
            thread.name = "paseo.perf.sampler"
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        /// The window's histograms; resets them.
        func drain() -> Histogram {
            collected.withLock { histogram in
                let out = histogram
                histogram = Histogram()
                return out
            }
        }

        private func loop() {
            let buffer = UnsafeMutablePointer<UInt>.allocate(capacity: Self.maxDepth)
            defer { buffer.deallocate() }
            while true {
                Thread.sleep(forTimeInterval: 0.001)
                let since = busySince.withLock { $0 }
                guard since > 0 else { continue }
                guard CACurrentMediaTime() - since > Self.after else { continue }
                let depth = capture(into: buffer)
                guard depth > 0 else { continue }
                let frames = Array(UnsafeBufferPointer(start: buffer, count: depth))
                record(frames)
            }
        }

        /// Suspends the main thread, copies its frame-pointer chain, resumes it. Nothing in here
        /// may allocate or take a lock the suspended thread could hold.
        private func capture(into buffer: UnsafeMutablePointer<UInt>) -> Int {
            guard thread_suspend(mainThread) == KERN_SUCCESS else { return 0 }
            defer { thread_resume(mainThread) }
            var state = arm_thread_state64_t()
            var count = mach_msg_type_number_t(
                MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
            let result = withUnsafeMutablePointer(to: &state) { pointer in
                pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                    thread_get_state(mainThread, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return 0 }
            var depth = 0
            buffer[depth] = UInt(state.__pc)
            depth += 1
            buffer[depth] = UInt(state.__lr)
            depth += 1
            var frame = UInt(state.__fp)
            while depth < Self.maxDepth {
                guard frame >= stackLow, frame < stackHigh &- 16, frame % 8 == 0 else { break }
                guard let pointer = UnsafePointer<UInt>(bitPattern: frame) else { break }
                let next = pointer[0]
                let returnAddress = pointer[1]
                guard returnAddress != 0 else { break }
                buffer[depth] = returnAddress
                depth += 1
                guard next > frame else { break }
                frame = next
            }
            return depth
        }

        // MARK: Symbols

        private struct Symbol {
            let name: String
            let own: Bool
        }

        private func symbol(for address: UInt) -> Symbol {
            if let cached = symbolCache[address] { return cached }
            var info = Dl_info()
            var result = Symbol(name: "?", own: false)
            if let pointer = UnsafeRawPointer(bitPattern: address), dladdr(pointer, &info) != 0 {
                let image = info.dli_fname.map { String(cString: $0) } ?? ""
                let own = image.hasSuffix("PaseoClient") || image.hasSuffix("PaseoClient.debug.dylib")
                var name = "?"
                if let raw = info.dli_sname {
                    name = Self.demangled(String(cString: raw))
                }
                result = Symbol(name: name, own: own)
            }
            symbolCache[address] = result
            return result
        }

        private static func demangled(_ mangled: String) -> String {
            var text = mangled
            mangled.withCString { raw in
                if let out = swift_demangle(raw, UInt(strlen(raw)), nil, nil, 0) {
                    text = String(cString: out)
                    free(out)
                }
            }
            for prefix in ["PaseoUI.", "PaseoStore.", "SwiftUI."] {
                text = text.replacingOccurrences(of: prefix, with: "")
            }
            text = text.replacingOccurrences(of: " in closure", with: "")
            text = text.replacingOccurrences(
                of: " in _[0-9A-F]{32}", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "(extension in SwiftUI):", with: "")
            return text.count > 60 ? String(text.prefix(60)) : text
        }

        /// Runs on the sampler thread, after the main thread has been resumed.
        private func record(_ frames: [UInt]) {
            guard let first = frames.first else { return }
            let leaf = symbol(for: first).name
            // The innermost three frames of the app's own code, leaf first: the path a fix needs.
            var chain: [String] = []
            for address in frames {
                let resolved = symbol(for: address)
                guard resolved.own, chain.last != resolved.name else { continue }
                chain.append(resolved.name)
                if chain.count == 3 { break }
            }
            let ownName: String? = chain.isEmpty ? nil : chain.joined(separator: " < ")
            // The leaf, then the frames above it that are not the Swift runtime's own plumbing
            // (casts, conformance lookups, metadata): who asked for the work, not how it ran.
            var path: [String] = [String(leaf.prefix(40))]
            for address in frames.dropFirst() {
                let name = symbol(for: address).name
                guard name != "?", path.last != name else { continue }
                if name.hasPrefix("_ZL") || name.hasPrefix("_ZN5swift") || name.hasPrefix("swift_")
                    || name.hasPrefix("tryCast") || name.hasPrefix("mach_msg") || name.hasPrefix("_pthread")
                    || name.hasPrefix("dyld") || name.hasPrefix("_dispatch") || name.hasPrefix("__")
                {
                    continue
                }
                path.append(String(name.prefix(36)))
                if path.count == 9 { break }
            }
            let stackName = path.joined(separator: " < ")
            collected.withLock { histogram in
                histogram.samples += 1
                histogram.leaf[leaf, default: 0] += 1
                if let ownName { histogram.own[ownName, default: 0] += 1 }
                histogram.stack[stackName, default: 0] += 1
            }
        }
    }

    @_silgen_name("swift_demangle")
    private func swift_demangle(
        _ mangledName: UnsafePointer<CChar>?, _ mangledNameLength: UInt,
        _ outputBuffer: UnsafeMutablePointer<CChar>?, _ outputBufferSize: UnsafeMutablePointer<UInt>?,
        _ flags: UInt32
    ) -> UnsafeMutablePointer<CChar>?
#endif
