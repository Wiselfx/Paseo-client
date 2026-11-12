import Foundation
import Testing

@testable import PaseoStore

// G5: chat artifacts stay offline even when the agent wrote a full document.
struct OfflineCSPTests {
    @Test("an author's own permissive CSP cannot opt out: ours is added too")
    func permissiveAuthorCSPStillGetsOurs() {
        let html = "<html><head><meta http-equiv=\"Content-Security-Policy\" content=\"connect-src *\"></head></html>"
        let out = OfflineCSP.inject(into: html)
        #expect(out.contains(OfflineCSP.meta))
        #expect(out.contains("connect-src *"))
    }

    @Test("injection is idempotent")
    func idempotent() {
        let once = OfflineCSP.inject(into: "<html><head></head><body></body></html>")
        #expect(OfflineCSP.inject(into: once) == once)
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
