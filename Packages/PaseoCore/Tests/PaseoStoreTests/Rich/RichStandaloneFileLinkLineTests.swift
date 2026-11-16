import Foundation
import Testing

@testable import PaseoStore

// J2 §2: a unit whose every line is a file (bare, or an authored link to one) becomes one
// card per file instead of a run of blue links.
struct RichStandaloneFileLinkLineTests {
    @Test("the four authored link lines from the report")
    func fourAuthoredLinks() {
        let unit = """
            [clip.mp4](/abs/media/clip.mp4)
            [tone.m4a](/abs/media/tone.m4a)
            [doc.pdf](/abs/media/doc.pdf)
            [stats.py](/abs/media/stats.py)
            """
        #expect(
            RichStandaloneFile.linkLines(unit: unit) == [
                "/abs/media/clip.mp4", "/abs/media/tone.m4a",
                "/abs/media/doc.pdf", "/abs/media/stats.py",
            ])
    }

    @Test("one authored link line counts, like one bare path")
    func singleLinkLine() {
        #expect(RichStandaloneFile.linkLines(unit: "[clip.mp4](/m/clip.mp4)") == ["/m/clip.mp4"])
        #expect(RichStandaloneFile.linkLines(unit: "/m/clip.mp4") == ["/m/clip.mp4"])
    }

    @Test("bare paths, one per line")
    func barePaths() {
        let unit = "/m/a.mp4\n\n~/b.m4a\n  ./c.pdf  \n"
        #expect(RichStandaloneFile.linkLines(unit: unit) == ["/m/a.mp4", "~/b.m4a", "./c.pdf"])
    }

    @Test("mixed bare paths and authored links keep their order")
    func mixed() {
        let unit = "/m/a.mp4\n[tone](/m/b.m4a)\n/m/c.pdf"
        #expect(RichStandaloneFile.linkLines(unit: unit) == ["/m/a.mp4", "/m/b.m4a", "/m/c.pdf"])
    }

    @Test("home expansion when a home is known")
    func home() {
        #expect(
            RichStandaloneFile.linkLines(unit: "[a](~/x/a.mp4)\n./b.pdf", home: "/home/agent")
                == ["/home/agent/x/a.mp4", "/home/agent/b.pdf"])
    }

    @Test("a link title and angle brackets are fine")
    func title() {
        #expect(
            RichStandaloneFile.linkLines(unit: "[doc](</m/doc.pdf> \"The doc\")") == ["/m/doc.pdf"])
    }

    // MARK: - Negatives

    @Test("a remote URL among the lines keeps the unit as links")
    func remoteURL() {
        #expect(RichStandaloneFile.linkLines(unit: "/m/a.mp4\nhttps://example.com/a.mp4") == nil)
        #expect(RichStandaloneFile.linkLines(unit: "[a](https://example.com/a.mp4)") == nil)
    }

    @Test("prose is prose")
    func prose() {
        #expect(RichStandaloneFile.linkLines(unit: "see /m/a.mp4 for the clip") == nil)
        #expect(RichStandaloneFile.linkLines(unit: "[the clip](/m/a.mp4) is ready") == nil)
    }

    @Test("two links on one line are not one link")
    func twoLinksOnLine() {
        #expect(RichStandaloneFile.linkLines(unit: "[a](/m/a.pdf) [b](/m/b.pdf)") == nil)
    }

    @Test("anchors and mailto are not files")
    func anchorsAndMailto() {
        #expect(RichStandaloneFile.linkLines(unit: "[top](#top)") == nil)
        #expect(RichStandaloneFile.linkLines(unit: "[mail](mailto:a@example.com)") == nil)
    }

    @Test("an empty unit has no lines")
    func empty() {
        #expect(RichStandaloneFile.linkLines(unit: "  \n \n") == nil)
    }

    // MARK: - List units (J2 §4)

    @Test("list markers at depth 0-3 are lists")
    func listMarkers() {
        #expect(RichStandaloneFile.isListUnit("- a\n- b"))
        #expect(RichStandaloneFile.isListUnit("* a"))
        #expect(RichStandaloneFile.isListUnit("+ a"))
        #expect(RichStandaloneFile.isListUnit("1. a"))
        #expect(RichStandaloneFile.isListUnit("12) a"))
        #expect(RichStandaloneFile.isListUnit("  - indented"))
        #expect(RichStandaloneFile.isListUnit("\n\n1. after blanks"))
    }

    @Test("prose, headings and deeper indents are not lists")
    func notLists() {
        #expect(!RichStandaloneFile.isListUnit("-not a marker"))
        #expect(!RichStandaloneFile.isListUnit("Just prose"))
        #expect(!RichStandaloneFile.isListUnit("    - code block, not a list"))
        #expect(!RichStandaloneFile.isListUnit("# Heading"))
        #expect(!RichStandaloneFile.isListUnit(""))
        #expect(!RichStandaloneFile.isListUnit("2.5 is a number"))
    }
}
