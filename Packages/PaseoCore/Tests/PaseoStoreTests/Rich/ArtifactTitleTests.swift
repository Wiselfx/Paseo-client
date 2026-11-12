import Foundation
import Testing

@testable import PaseoStore

// G5 C8: the artifact page titles itself from the document.
struct ArtifactTitleTests {
    @Test("title element wins")
    func titleElementWins() {
        #expect(
            ArtifactTitle.extract(
                html: "<html><head><title>My Viz</title></head><body><h1>Other</h1></body></html>")
                == "My Viz")
    }

    @Test("first h1 is the fallback")
    func h1Fallback() {
        #expect(
            ArtifactTitle.extract(html: "<body><h1>Flow Title</h1><p>x</p></body>")
                == "Flow Title")
    }

    @Test("matching is case-insensitive and spans lines")
    func caseAndLinesIgnored() {
        #expect(
            ArtifactTitle.extract(html: "<TITLE>\n Spaced \n</TITLE>") == "Spaced")
        #expect(
            ArtifactTitle.extract(html: "<H1 class=\"x\">Titled <a href=\"/y\">link</a></H1>")
                == "Titled link")
    }

    @Test("blank or absent is nil")
    func blankOrAbsentIsNil() {
        #expect(ArtifactTitle.extract(html: "<title>   </title>") == nil)
        #expect(ArtifactTitle.extract(html: "<p>no headings here</p>") == nil)
        #expect(ArtifactTitle.extract(html: "") == nil)
    }
}
