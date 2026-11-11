import Foundation
import Testing

@testable import PaseoStore

// G2 §12: the full etiquette table as a parameterised test. Each row names the §12 line it
// comes from, so a policy change has to argue with the table, not just the code.
struct MediaFetchPolicyTests {
    struct Case: Sendable {
        let name: String
        let kind: MediaKind
        let knownBytes: Int64?
        let condition: MediaLinkCondition
        let expected: MediaFetchPolicy
    }

    static let kb: Int64 = 1024
    static let mb: Int64 = 1024 * 1024

    static let cases: [Case] = [
        // Wi-Fi / Ethernet, not constrained: thumbs + images ≤ 5 MB auto; the rest waits;
        // YouTube and link previews auto.
        Case(
            name: "wifi thumbnail auto", kind: .thumbnail, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi), expected: .automatic),
        Case(
            name: "wifi small image auto", kind: .daemonImage, knownBytes: 200 * kb,
            condition: MediaLinkCondition(interface: .wifi), expected: .automatic),
        Case(
            name: "wifi unknown image auto (cap enforces)", kind: .remoteImage, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi), expected: .automatic),
        Case(
            name: "wifi 5 MB image auto", kind: .daemonImage, knownBytes: 5 * mb,
            condition: MediaLinkCondition(interface: .wifi), expected: .automatic),
        Case(
            name: "wifi large image tap", kind: .daemonImage, knownBytes: 6 * mb,
            condition: MediaLinkCondition(interface: .wired), expected: .tapToDownload),
        Case(
            name: "wifi video tap", kind: .video, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi), expected: .tapToDownload),
        Case(
            name: "wifi audio tap", kind: .audio, knownBytes: 3 * mb,
            condition: MediaLinkCondition(interface: .wifi), expected: .tapToDownload),
        Case(
            name: "wifi youtube auto", kind: .youTube, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi), expected: .automatic),
        Case(
            name: "wifi link preview auto", kind: .linkPreview, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi), expected: .automatic),
        // Cellular, not constrained: same as Wi-Fi, with the size shown on the tap box.
        Case(
            name: "cellular small image auto", kind: .daemonImage, knownBytes: 4 * mb,
            condition: MediaLinkCondition(interface: .cellular), expected: .automatic),
        Case(
            name: "cellular large image tap", kind: .daemonImage, knownBytes: 20 * mb,
            condition: MediaLinkCondition(interface: .cellular), expected: .tapToDownload),
        Case(
            name: "cellular video tap", kind: .video, knownBytes: nil,
            condition: MediaLinkCondition(interface: .cellular), expected: .tapToDownload),
        Case(
            name: "cellular youtube auto", kind: .youTube, knownBytes: nil,
            condition: MediaLinkCondition(interface: .cellular), expected: .automatic),
        // Low Data Mode: thumbnails auto; everything else waits, including metadata.
        Case(
            name: "constrained thumbnail auto", kind: .thumbnail, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi, constrained: true),
            expected: .automatic),
        Case(
            name: "constrained small image tap", kind: .daemonImage, knownBytes: 100 * kb,
            condition: MediaLinkCondition(interface: .wifi, constrained: true),
            expected: .tapToDownload),
        Case(
            name: "constrained youtube tap", kind: .youTube, knownBytes: nil,
            condition: MediaLinkCondition(interface: .cellular, constrained: true),
            expected: .tapToDownload),
        Case(
            name: "constrained link preview tap", kind: .linkPreview, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi, constrained: true),
            expected: .tapToDownload),
        // Relay: thumbnails auto; images ≤ 1 MB auto else tap; video/audio tap;
        // YouTube and link previews auto (they never use the relay).
        Case(
            name: "relay thumbnail auto", kind: .thumbnail, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi, isRelay: true),
            expected: .automatic),
        Case(
            name: "relay 1 MB image auto", kind: .daemonImage, knownBytes: 1 * mb,
            condition: MediaLinkCondition(interface: .wifi, isRelay: true),
            expected: .automatic),
        Case(
            name: "relay 2 MB image tap", kind: .daemonImage, knownBytes: 2 * mb,
            condition: MediaLinkCondition(interface: .wifi, isRelay: true),
            expected: .tapToDownload),
        Case(
            name: "relay unknown image tap", kind: .daemonImage, knownBytes: nil,
            condition: MediaLinkCondition(interface: .cellular, isRelay: true),
            expected: .tapToDownload),
        // A remote https image never touches the relay: the host link is irrelevant.
        Case(
            name: "relay remote unknown image auto", kind: .remoteImage, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi, isRelay: true),
            expected: .automatic),
        Case(
            name: "relay remote large image tap", kind: .remoteImage, knownBytes: 20 * mb,
            condition: MediaLinkCondition(interface: .cellular, isRelay: true),
            expected: .tapToDownload),
        Case(
            name: "relay daemon small image auto", kind: .daemonImage, knownBytes: 500 * kb,
            condition: MediaLinkCondition(interface: .wifi, isRelay: true),
            expected: .automatic),
        Case(
            name: "relay video tap", kind: .video, knownBytes: 500 * kb,
            condition: MediaLinkCondition(interface: .wifi, isRelay: true),
            expected: .tapToDownload),
        Case(
            name: "relay youtube auto", kind: .youTube, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi, isRelay: true),
            expected: .automatic),
        Case(
            name: "relay link preview auto", kind: .linkPreview, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi, isRelay: true),
            expected: .automatic),
        // Offline: everything stays cached.
        Case(
            name: "offline image cacheOnly", kind: .daemonImage, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi, offline: true),
            expected: .cacheOnly),
        Case(
            name: "offline thumbnail cacheOnly", kind: .thumbnail, knownBytes: nil,
            condition: MediaLinkCondition(interface: .cellular, offline: true),
            expected: .cacheOnly),
        Case(
            name: "offline youtube cacheOnly", kind: .youTube, knownBytes: nil,
            condition: MediaLinkCondition(interface: .wifi, offline: true),
            expected: .cacheOnly),
    ]

    @Test("the §12 table", arguments: cases)
    func policyTable(_ c: Case) {
        #expect(
            mediaFetchPolicy(kind: c.kind, knownBytes: c.knownBytes, condition: c.condition)
                == c.expected)
    }

    @Test("in-flight caps")
    func caps() {
        let wifi = MediaLinkCondition(interface: .wifi)
        let cellular = MediaLinkCondition(interface: .cellular)
        let relay = MediaLinkCondition(interface: .wifi, isRelay: true)
        let constrained = MediaLinkCondition(interface: .wifi, constrained: true)
        let offline = MediaLinkCondition(interface: .wifi, offline: true)
        #expect(mediaDownloadCap(kind: .daemonImage, condition: wifi) == 5 * Self.mb)
        #expect(mediaDownloadCap(kind: .daemonImage, condition: cellular) == 5 * Self.mb)
        #expect(mediaDownloadCap(kind: .daemonImage, condition: relay) == 1 * Self.mb)
        #expect(mediaDownloadCap(kind: .remoteImage, condition: wifi) == 5 * Self.mb)
        #expect(mediaDownloadCap(kind: .remoteImage, condition: relay) == 5 * Self.mb)
        #expect(mediaDownloadCap(kind: .daemonImage, condition: constrained) == nil)
        #expect(mediaDownloadCap(kind: .daemonImage, condition: offline) == nil)
        #expect(mediaDownloadCap(kind: .thumbnail, condition: wifi) == nil)
        #expect(mediaDownloadCap(kind: .video, condition: wifi) == nil)
        #expect(mediaDownloadCap(kind: .youTube, condition: wifi) == nil)
        #expect(mediaDownloadCap(kind: .linkPreview, condition: wifi) == nil)
    }
}

extension MediaFetchPolicyTests.Case: CustomTestStringConvertible {
    var testDescription: String { name }
}
