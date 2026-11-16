import Foundation
import Testing

@testable import PaseoStore

// G9 C7: GitHub URL parsing for PR/issue/commit/run/repo links.
struct GitHubURLTests {
    @Test("repo root and tree/blob degrade to the repo")
    func repoRoot() {
        #expect(GitHubURL.parse("https://github.com/getpaseo/paseo")?.kind == .repo)
        #expect(
            GitHubURL.parse("https://github.com/getpaseo/paseo/tree/main/docs")?.kind == .repo)
        #expect(GitHubURL.parse("https://github.com/getpaseo/paseo.git")?.slug == "getpaseo/paseo")
    }

    @Test("pull and issue numbers")
    func numbers() {
        #expect(
            GitHubURL.parse("https://github.com/getpaseo/paseo/pull/42")?.kind == .pull(number: 42))
        #expect(
            GitHubURL.parse("https://github.com/getpaseo/paseo/issues/7/files")?.kind
                == .issue(number: 7))
        // A bare /pulls list is the repo, not a number.
        #expect(GitHubURL.parse("https://github.com/getpaseo/paseo/pulls")?.kind == .repo)
    }

    @Test("commit sha and actions run")
    func commitAndRun() {
        #expect(
            GitHubURL.parse("https://github.com/getpaseo/paseo/commit/abc1234")?.kind
                == .commit(sha: "abc1234"))
        #expect(
            GitHubURL.parse("https://github.com/getpaseo/paseo/actions/runs/987654321")?.kind
                == .actionsRun(id: "987654321"))
    }

    @Test("query strings, fragments and case do not matter")
    func noiseIgnored() {
        #expect(
            GitHubURL.parse("https://github.com/GetPaseo/Paseo/pull/42?diff=split#r1")?.slug
                == "GetPaseo/Paseo")
    }

    @Test("non-GitHub and malformed URLs yield nil")
    func rejectsOthers() {
        #expect(GitHubURL.parse("https://example.com/getpaseo/paseo/pull/1") == nil)
        #expect(GitHubURL.parse("https://github.com/onlyowner") == nil)
        #expect(GitHubURL.parse("not a url") == nil)
        #expect(GitHubURL.parse("") == nil)
    }
}
