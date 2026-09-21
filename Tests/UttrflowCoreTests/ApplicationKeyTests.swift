// Tests for the one spelling an application is filed under.

import Testing

@testable import UttrflowCore

@Suite("The key an application is filed under")
struct ApplicationKeyTests {
    @Test("files an application under one spelling however macOS spells it")
    func caseDoesNotMakeASecondApplication() {
        #expect(ApplicationKey.of("com.apple.Terminal") == ApplicationKey.of("com.apple.terminal"))
        #expect(ApplicationKey.of("COM.APPLE.TERMINAL") == ApplicationKey.of("com.apple.terminal"))
    }

    @Test("keeps everything but the case, since the rest of an identifier is the identifier")
    func nothingElseIsChanged() {
        #expect(ApplicationKey.of("com.todesktop.230313mzl4w4u92") == "com.todesktop.230313mzl4w4u92")
        #expect(ApplicationKey.of("") == "")
    }

    @Test("says two identifiers name one application whatever their case")
    func sameApplication() {
        #expect(ApplicationKey.same("dev.zed.Zed", as: "dev.zed.zed"))
        #expect(!ApplicationKey.same("dev.zed.zed", as: "dev.zed.zedd"))
    }
}
