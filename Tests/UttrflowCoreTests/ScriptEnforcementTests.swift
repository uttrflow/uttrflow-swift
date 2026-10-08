import Testing

@testable import UttrflowCore

@Suite("Script enforcement counts the words each conversion wrote")
struct ScriptEnforcementTests {
    @Test("Latin text is unchanged and counts nothing")
    func latinCountsNothing() {
        let result = LatinScript.enforcement(of: "send the report today")
        #expect(
            result
                == ScriptEnforcement(text: "send the report today", wordsRomanised: 0, wordsTransliterated: 0)
        )
    }

    @Test("Devanagari words are counted as romanised")
    func devanagariIsRomanised() {
        let result = LatinScript.enforcement(of: "मुझे report भेजो")
        #expect(result.wordsRomanised == 2)
        #expect(result.wordsTransliterated == 0)
        #expect(LatinScript.isLatin(result.text))
    }

    @Test("Other scripts are counted as transliterated")
    func otherScriptIsTransliterated() {
        let result = LatinScript.enforcement(of: "hello мир")
        #expect(result.wordsRomanised == 0)
        #expect(result.wordsTransliterated == 1)
        #expect(LatinScript.isLatin(result.text))
    }

    @Test("enforced is the text of enforcement")
    func enforcedMatches() {
        for text in ["मुझे report भेजो", "hello мир", "plain", "١٢٣ items"] {
            #expect(LatinScript.enforced(text) == LatinScript.enforcement(of: text).text)
        }
    }
}
