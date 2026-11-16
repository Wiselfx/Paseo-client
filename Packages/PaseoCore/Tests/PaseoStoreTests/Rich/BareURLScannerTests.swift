import Foundation
import Testing

@testable import PaseoStore

// J2 §3: bare URLs inside plain text become links (swift-markdown has no autolink).
struct BareURLScannerTests {
    private func urls(_ text: String) -> [String] {
        BareURLScanner.ranges(in: text).map { String(text[$0]) }
    }

    @Test("a bare URL in a sentence")
    func bareURL() {
        #expect(urls("see https://swift.org/blog/ for more") == ["https://swift.org/blog/"])
        #expect(urls("http://example.com") == ["http://example.com"])
    }

    @Test("trailing punctuation is not part of the URL")
    func trailingPunctuation() {
        #expect(urls("Go to https://swift.org.") == ["https://swift.org"])
        #expect(urls("Is it https://swift.org?" ) == ["https://swift.org"])
        #expect(urls("(https://swift.org); next") == ["https://swift.org"])
        #expect(urls("https://swift.org, https://github.com!") == ["https://swift.org", "https://github.com"])
    }

    @Test("balanced parens stay, the sentence's closing one does not")
    func parentheses() {
        #expect(
            urls("https://en.wikipedia.org/wiki/Rotating_earth_(large)")
                == ["https://en.wikipedia.org/wiki/Rotating_earth_(large)"])
        #expect(
            urls("(see https://en.wikipedia.org/wiki/Foo_(bar))")
                == ["https://en.wikipedia.org/wiki/Foo_(bar)"])
        #expect(urls("(https://swift.org)") == ["https://swift.org"])
    }

    @Test("query strings and fragments")
    func queryAndFragment() {
        #expect(
            urls("https://example.com/a?b=1&c=2#d") == ["https://example.com/a?b=1&c=2#d"])
    }

    @Test("two URLs in one text keep their order and ranges")
    func twoURLs() {
        let text = "a https://one.example/x b https://two.example/y"
        #expect(urls(text) == ["https://one.example/x", "https://two.example/y"])
        let ranges = BareURLScanner.ranges(in: text)
        #expect(ranges.count == 2)
        if ranges.count == 2 {
            #expect(ranges[0].upperBound <= ranges[1].lowerBound)
        }
    }

    @Test("no URL, no ranges")
    func none() {
        #expect(BareURLScanner.ranges(in: "plain text, no links").isEmpty)
        #expect(BareURLScanner.ranges(in: "").isEmpty)
        #expect(BareURLScanner.ranges(in: "ftp://example.com").isEmpty)
        #expect(BareURLScanner.ranges(in: "https://").isEmpty)
    }

    @Test("a URL in brackets or quotes stops before them")
    func stopsAtBrackets() {
        #expect(urls("[https://swift.org]") == ["https://swift.org"])
        #expect(urls("<https://swift.org>") == ["https://swift.org"])
        #expect(urls("\"https://swift.org\"") == ["https://swift.org"])
    }
}
