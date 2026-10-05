import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Languages Apple's model is asked about")
struct AppleModelLanguagesTests {
    @Test("Hindi is never offered to Apple's model, even if Apple declares it")
    func hindiIsWithheld() {
        #expect(AppleModelLanguages.withheld.contains(.hindi))
        #expect(
            AppleModelLanguages.availability(of: .hindi, declaredByApple: true)
                == .unsupportedLanguage(.hindi))
        #expect(
            AppleModelLanguages.availability(of: .hindi, declaredByApple: false)
                == .unsupportedLanguage(.hindi))
    }

    @Test("a declared language is available and an undeclared one is not")
    func followsApplesList() {
        #expect(AppleModelLanguages.availability(of: .english, declaredByApple: true) == .available)
        #expect(
            AppleModelLanguages.availability(of: .english, declaredByApple: false)
                == .unsupportedLanguage(.english))
    }
}
