import Foundation
import Testing

@testable import PaseoStore

/// E3b: the workspace HTML preview serves its own files through `paseo-file://`. The resolver is
/// the security boundary — an escaping path must never reach the checkout's file read.
@Suite struct PreviewFileSchemeTests {
    private func resolve(_ string: String) -> String? {
        guard let url = URL(string: string) else { return nil }
        return PreviewFileScheme.resolve(url)?.path
    }

    @Test func resolvesAnOrdinaryReference() throws {
        #expect(resolve("paseo-file://ws_1/assets/app.css") == "assets/app.css")
        let url = try #require(URL(string: "paseo-file://ws_1/a/b.png"))
        let resolved = try #require(PreviewFileScheme.resolve(url))
        #expect(resolved.workspaceId == "ws_1")
        #expect(resolved.path == "a/b.png")
    }

    @Test func rootRelativePathsAndDotSegments() {
        #expect(resolve("paseo-file://ws_1/logo.png") == "logo.png")
        #expect(PreviewFileScheme.relativePath("/./assets//app.js") == "assets/app.js")
        #expect(PreviewFileScheme.relativePath("a/../b.css") == "b.css")
        #expect(PreviewFileScheme.relativePath("a/./b/../c") == "a/c")
    }

    @Test func neverEscapesTheWorkspace() {
        #expect(PreviewFileScheme.relativePath("../secret") == nil)
        #expect(PreviewFileScheme.relativePath("a/../../secret") == nil)
        #expect(PreviewFileScheme.relativePath("/../etc/passwd") == nil)
        #expect(resolve("paseo-file://ws_1/../etc/passwd") == nil)
    }

    @Test func encodedDotSegmentsCannotEscape() {
        // `URL.path` decodes once, so these arrive here as `../`: the pop must still refuse.
        #expect(resolve("paseo-file://ws_1/%2e%2e/secret") == nil)
        #expect(resolve("paseo-file://ws_1/%2e%2e%2fsecret") == nil)
        #expect(resolve("paseo-file://ws_1/a/%2e%2e/%2e%2e/secret") == nil)
    }

    @Test func encodedNamesArriveDecodedExactlyOnce() {
        #expect(resolve("paseo-file://ws_1/my%20file.css") == "my file.css")
        #expect(resolve("paseo-file://ws_1/assets/%E2%9C%93.svg") == "assets/✓.svg")
        // A literal `%` survives: decoding twice would turn `100%.txt` into `100..txt`.
        #expect(resolve("paseo-file://ws_1/100%25.txt") == "100%.txt")
    }

    @Test func rejectsOtherSchemesAndMissingHosts() {
        #expect(resolve("https://ws_1/app.css") == nil)
        #expect(resolve("paseo-file:///app.css") == nil)
        #expect(PreviewFileScheme.relativePath("") == nil)
        #expect(PreviewFileScheme.relativePath("/") == nil)
        #expect(PreviewFileScheme.relativePath(".") == nil)
        #expect(PreviewFileScheme.relativePath("a/..") == nil)
    }

    @Test func ignoresQueryAndFragment() {
        #expect(resolve("paseo-file://ws_1/app.js?v=1#top") == "app.js")
    }

    @Test func backslashIsAPlainFilenameCharacter() {
        // A POSIX host treats `\` as part of a name; it is not a separator, so it is not an escape.
        #expect(PreviewFileScheme.relativePath("a\\..\\..\\x") == "a\\..\\..\\x")
    }

    @Test func baseHrefIsTheFilesDirectory() {
        #expect(
            PreviewFileScheme.baseHref(workspaceId: "ws_1", filePath: "docs/index.html")
                == "paseo-file://ws_1/docs/")
        #expect(
            PreviewFileScheme.baseHref(workspaceId: "ws_1", filePath: "index.html")
                == "paseo-file://ws_1/")
        #expect(
            PreviewFileScheme.baseHref(workspaceId: "ws_1", filePath: "my docs/index.html")
                == "paseo-file://ws_1/my%20docs/")
    }
}
