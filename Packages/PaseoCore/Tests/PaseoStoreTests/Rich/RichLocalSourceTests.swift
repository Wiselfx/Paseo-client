import Foundation
import Testing

@testable import PaseoStore

// J2: destinations that point at local files, and the file-path pattern's number rule.
struct RichLocalSourceTests {
    @Test("local shapes: absolute, home, dot-relative, relative with an extension")
    func localShapes() {
        #expect(RichLocalSource.filePath("/m/a.png", home: nil) == "/m/a.png")
        #expect(RichLocalSource.filePath("~/m/a.png", home: "/home/agent") == "/home/agent/m/a.png")
        #expect(RichLocalSource.filePath("~/m/a.png", home: nil) == "~/m/a.png")
        #expect(RichLocalSource.filePath("./a.png", home: "/home/agent") == "/home/agent/a.png")
        #expect(RichLocalSource.filePath("./a.png", home: nil) == "./a.png")
        #expect(RichLocalSource.filePath("../shots/a.png", home: "/home/agent") == "/home/agent/../shots/a.png")
        #expect(RichLocalSource.filePath("docs/a.pdf", home: "/home/agent") == "/home/agent/docs/a.pdf")
    }

    @Test("not local: schemes, anchors, queries, extensionless words, directories")
    func notLocal() {
        #expect(RichLocalSource.filePath("https://example.com/a.png", home: nil) == nil)
        #expect(RichLocalSource.filePath("mailto:a@example.com", home: nil) == nil)
        #expect(RichLocalSource.filePath("#anchor", home: nil) == nil)
        #expect(RichLocalSource.filePath("/m/a.png?raw=1", home: nil) == nil)
        #expect(RichLocalSource.filePath("paseo-file://file?path=a", home: nil) == nil)
        #expect(RichLocalSource.filePath("README", home: nil) == nil)
        #expect(RichLocalSource.filePath("notes/", home: nil) == nil)
        #expect(RichLocalSource.filePath("", home: nil) == nil)
    }

    @Test("images: local paths and remote image URLs")
    func images() {
        #expect(RichLocalSource.image("/m/a.png", home: nil) == .file(path: "/m/a.png"))
        #expect(
            RichLocalSource.image("https://example.com/a.png", home: nil)
                == .remoteImage(url: "https://example.com/a.png"))
        #expect(
            RichLocalSource.image("https://example.com/a.png?w=200", home: nil)
                == .remoteImage(url: "https://example.com/a.png?w=200"))
        #expect(RichLocalSource.image("data:image/png;base64,AAAA", home: nil) == nil)
        #expect(RichLocalSource.image("https://example.com/page", home: nil) == nil)
        #expect(RichLocalSource.image("", home: nil) == nil)
    }

    @Test("links: a scheme-less web URL becomes https")
    func schemeLessWebURLs() {
        #expect(
            RichLocalSource.link("example.com/guide", home: nil)
                == .file(path: "https://example.com/guide"))
        #expect(
            RichLocalSource.link("https://example.com/guide", home: nil)
                == .file(path: "https://example.com/guide"))
        #expect(RichLocalSource.link("docs/a.pdf", home: nil) == .file(path: "docs/a.pdf"))
        #expect(RichLocalSource.link("README", home: nil) == nil)
        #expect(RichLocalSource.link("bareLabel", home: nil) == nil)
        // A `bareHosts` name (a documentation placeholder) qualifies alone, and with a port.
        #expect(RichLocalSource.link("example.com", home: nil) == .file(path: "https://example.com"))
        #expect(
            RichLocalSource.link("example.com:8080", home: nil)
                == .file(path: "https://example.com:8080"))
    }

    // MARK: - The file-path pattern's number rule (J2 §5)

    /// `FilePathLinks.pathPattern` (PaseoUI) with J2's fix: the extension must start
    /// with a letter. Pinned here so the table rendering (`98.5` blue) cannot come back.
    @Test("table numbers are not file paths")
    func numbersAreNotPaths() {
        let pattern =
            #"(?<![\w/~@.-])(?:@)?(?:~?/|\.{1,2}/)?(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.[A-Za-z][A-Za-z0-9]{0,7}(?![\w/~.-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            Issue.record("pattern does not compile")
            return
        }
        func matches(_ text: String) -> [String] {
            let ns = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range) }
        }
        // Not paths: the numbers and versions the old extension rule accepted.
        #expect(matches("98.5") == [])
        #expect(matches("87.2") == [])
        #expect(matches("1.2.3") == [])
        #expect(matches("v2.0") == [])
        #expect(matches("12.5%") == [])
        #expect(matches("| 98.5 | 87.2 |") == [])
        // Still paths.
        #expect(matches("see src/app.py now") == ["src/app.py"])
        #expect(matches("/m/clip.MP4") == ["/m/clip.MP4"])
        #expect(matches("~/notes.txt") == ["~/notes.txt"])
        #expect(matches("@src/a.swift") == ["@src/a.swift"])
        #expect(matches("./a-b_c.md") == ["./a-b_c.md"])
    }
}
