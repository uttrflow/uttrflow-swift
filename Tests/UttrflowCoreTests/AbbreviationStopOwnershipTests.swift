// Canonical abbreviation ownership stays distinct from the public dotted-shape fallback.

import Testing
@testable import UttrflowCore

@Suite("Registered abbreviation stop ownership")
struct AbbreviationStopOwnershipTests {
    @Test("registered lead-ins and times own their dot in either case", arguments: ["e.g", "i.e", "p.m"])
    func registeredForms(word: String) {
        #expect(Abbreviations.ownsStop(word))
        #expect(Abbreviations.ownsRegisteredStop(word))
        #expect(Abbreviations.ownsStop(word.uppercased()))
        #expect(Abbreviations.ownsRegisteredStop(word.uppercased()))
    }

    @Test(
        "the public dotted fallback remains unchanged while registry ownership excludes file-shaped tokens",
        arguments: ["a.py", "ab.py", "xy.js", "ui.ts"])
    func dottedFallback(word: String) {
        #expect(Abbreviations.ownsStop(word))
        #expect(!Abbreviations.ownsRegisteredStop(word))
    }

    @Test("ambiguous words and stopless symbols acquire no registered stop", arguments: ["no", "co", "ms"])
    func wordsAndSymbols(word: String) {
        #expect(!Abbreviations.ownsStop(word))
        #expect(!Abbreviations.ownsRegisteredStop(word))
    }
}
