import Foundation
import Testing

@testable import PaseoStore

// G10 C10: standalone file lines become file cards; inline mentions do not.
struct RichStandaloneFileTests {
    private func detected(_ source: String) -> [RichContentBlock] {
        RichContentDetector.detect(in: source)
    }

    @Test("a lone path line is a file card")
    func standaloneLineIsFile() {
        let source = "/tmp/notes.txt"
        #expect(RichStandaloneFile.path(in: detected(source), unitText: source) == "/tmp/notes.txt")
    }

    @Test("surrounding whitespace is fine")
    func surroundingWhitespaceIsFine() {
        let source = "  /tmp/notes.txt\n"
        #expect(RichStandaloneFile.path(in: detected(source), unitText: source) == "/tmp/notes.txt")
    }

    @Test("an inline mention stays inline")
    func inlineStaysInline() {
        let source = "open /tmp/notes.txt please"
        #expect(RichStandaloneFile.path(in: detected(source), unitText: source) == nil)
    }

    @Test("an image path is never a file card")
    func imageIsNotFile() {
        let source = "/tmp/shot.png"
        #expect(RichStandaloneFile.path(in: detected(source), unitText: source) == nil)
    }

    @Test("two paths on one line are not a card")
    func twoPathsAreNotCard() {
        let source = "/tmp/a.txt /tmp/b.txt"
        #expect(RichStandaloneFile.path(in: detected(source), unitText: source) == nil)
    }

    @Test("trailing punctuation breaks the verbatim match")
    func punctuationBreaksMatch() {
        let source = "see /tmp/notes.txt."
        #expect(RichStandaloneFile.path(in: detected(source), unitText: source) == nil)
    }
}
