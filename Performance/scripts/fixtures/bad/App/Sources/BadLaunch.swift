// features: F12 F16
// Fixture: launch-path work.
import SwiftUI

@main
struct BadApp: App {
    init() {
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) } // expect: C39 // hit: H23
        let token = Keychain.read("host") // hit: H23
    }
}
