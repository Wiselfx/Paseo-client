import Foundation
import Testing

@testable import PaseoStore

// G5: chat artifacts stay offline even when the agent wrote a full document.
struct OfflineCSPTests {
    @Test("a document that already has a CSP is untouched")
    func existingCSPIsUntouched() {
        let html = "<html><head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'\"></head></html>"
        #expect(OfflineCSP.inject(into: html) == html)
    }

    @Test("the meta lands right after <head>, case-insensitively")
    func injectsAfterHead() {
        let html = "<HTML><HEAD lang=\"en\"><title>T</title></HEAD><body></body></HTML>"
        let out = OfflineCSP.inject(into: html)
        #expect(out.contains("<HEAD lang=\"en\">\n" + OfflineCSP.meta))
        #expect(ArtifactTitle.extract(html: out) == "T")
    }

    @Test("a fragment gets a head prepended")
    func fragmentGetsHead() {
        let out = OfflineCSP.inject(into: "<p>hi</p>")
        #expect(out.hasPrefix("<head>\n" + OfflineCSP.meta))
        #expect(out.hasSuffix("<p>hi</p>"))
    }

    @Test("the meta blocks the network")
    func metaBlocksNetwork() {
        #expect(OfflineCSP.meta.contains("connect-src 'none'"))
        #expect(OfflineCSP.meta.contains("form-action 'none'"))
        #expect(!OfflineCSP.meta.contains("http://") && !OfflineCSP.meta.contains("https://"))
    }
}
