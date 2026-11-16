import Foundation
import Testing

@testable import PaseoStore

// J2 §1: an agent's several images on one line are a gallery, not "▧ alt" text.
struct RichImageGroupingInlineTests {
    @Test("one image is one image")
    func singleImage() {
        let images = RichImageGrouping.imagesOnly(unit: "![one](/abs/media/one.png)")
        #expect(images == [RichImage(source: .local(path: "/abs/media/one.png"), alt: "one")])
    }

    @Test("two local images on one line")
    func twoLocal() {
        #expect(
            RichImageGrouping.imagesOnly(unit: "![a](/m/a.png) ![b](/m/b.png)") == [
                RichImage(source: .local(path: "/m/a.png"), alt: "a"),
                RichImage(source: .local(path: "/m/b.png"), alt: "b"),
            ])
    }

    @Test("four mixed local and remote, as the agent wrote them")
    func mixedLocalRemote() {
        let unit =
            "![one](/abs/media/one.png) ![two](/abs/media/two.png) "
            + "![three](/abs/media/three.png) ![remote](https://example.com/x.png)"
        let images = RichImageGrouping.imagesOnly(unit: unit)
        #expect(images?.count == 4)
        #expect(images?.first?.source == .local(path: "/abs/media/one.png"))
        #expect(images?.last?.source == .remote(url: "https://example.com/x.png"))
        #expect(images?.map(\.alt) == ["one", "two", "three", "remote"])
    }

    @Test("line breaks and surrounding whitespace separate images too")
    func lineBreaks() {
        let unit = "\n  ![a](/m/a.png)\n![b](https://example.com/b.png)  \n"
        #expect(
            RichImageGrouping.imagesOnly(unit: unit) == [
                RichImage(source: .local(path: "/m/a.png"), alt: "a"),
                RichImage(source: .remote(url: "https://example.com/b.png"), alt: "b"),
            ])
    }

    @Test("titles and angle brackets are allowed and alt is kept verbatim")
    func titleAndAngles() {
        #expect(
            RichImageGrouping.imagesOnly(unit: "![A garden](</m/g.png> \"Caption\")") == [
                RichImage(source: .local(path: "/m/g.png"), alt: "A garden")
            ])
    }

    @Test("home and relative sources expand when a home is known")
    func homeExpansion() {
        #expect(
            RichImageGrouping.imagesOnly(unit: "![a](~/shots/a.png)", home: "/home/agent") == [
                RichImage(source: .local(path: "/home/agent/shots/a.png"), alt: "a")
            ])
        #expect(
            RichImageGrouping.imagesOnly(unit: "![a](./a.png)", home: "/home/agent") == [
                RichImage(source: .local(path: "/home/agent/a.png"), alt: "a")
            ])
        #expect(
            RichImageGrouping.imagesOnly(unit: "![a](~/shots/a.png)") == [
                RichImage(source: .local(path: "~/shots/a.png"), alt: "a")
            ])
    }

    // MARK: - Negatives

    @Test("prose before or after the images keeps the unit text")
    func proseAroundImages() {
        #expect(RichImageGrouping.imagesOnly(unit: "Here: ![a](/m/a.png)") == nil)
        #expect(RichImageGrouping.imagesOnly(unit: "![a](/m/a.png) done") == nil)
    }

    @Test("a link among the images is not an image-only unit")
    func linkAmongImages() {
        #expect(RichImageGrouping.imagesOnly(unit: "![a](/m/a.png) [b](/m/b.png)") == nil)
    }

    @Test("a code span is not an image")
    func codeSpan() {
        #expect(RichImageGrouping.imagesOnly(unit: "`![a](/m/a.png)`") == nil)
        #expect(RichImageGrouping.imagesOnly(unit: "![a](/m/a.png) `x`") == nil)
    }

    @Test("an empty unit and a list marker are not galleries")
    func emptyAndList() {
        #expect(RichImageGrouping.imagesOnly(unit: "   \n ") == nil)
        #expect(RichImageGrouping.imagesOnly(unit: "- ![a](/m/a.png)") == nil)
    }

    @Test("a non-image source is not an image for the gallery")
    func nonImageSource() {
        // `mailto:` and a fragment are not image sources at all.
        #expect(RichImageGrouping.imagesOnly(unit: "![a](mailto:x@example.com)") == nil)
        #expect(RichImageGrouping.imagesOnly(unit: "![a](#anchor)") == nil)
        // A remote *page* URL is a valid image source (a picture may be served by a
        // page path without an extension), but a second one that is not an image keeps
        // it out only when it is not a URL at all.
        #expect(RichImageGrouping.imagesOnly(unit: "![a](https://example.com/x.png)") != nil)
    }

    @Test("a bare URL is not a markdown image")
    func bareURLNotImage() {
        #expect(RichImageGrouping.imagesOnly(unit: "https://example.com/a.png") == nil)
    }
}
