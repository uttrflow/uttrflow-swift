import Foundation
import Testing

@testable import UttrflowCore

@Suite("LanguageCode")
struct LanguageCodeTests {
    @Test(
        "normalises any BCP-47 identifier to its lowercase primary subtag",
        arguments: [
            ("en", "en"),
            ("EN", "en"),
            ("en-US", "en"),
            ("en_GB", "en"),
            ("zh-Hant-TW", "zh"),
            ("  hi-IN", "hi"),
            ("HI", "hi"),
        ]
    )
    func normalisesIdentifier(input: String, expected: String) {
        #expect(LanguageCode(input)?.value == expected)
    }

    @Test(
        "rejects identifiers with no alphabetic primary subtag",
        arguments: ["", "   ", "-", "-en", "1", "e1", "en1", "_", "123-US"]
    )
    func rejectsInvalidIdentifier(input: String) {
        #expect(LanguageCode(input) == nil)
    }

    @Test("treats differently-spelled identifiers for one language as equal")
    func equatesEquivalentSpellings() {
        #expect(LanguageCode("en-US") == LanguageCode("EN"))
        #expect(LanguageCode("en") != LanguageCode("hi"))
    }

    @Test("exposes well-known languages without going through validation")
    func wellKnownConstants() {
        #expect(LanguageCode.english.value == "en")
        #expect(LanguageCode.hindi.value == "hi")
    }

    @Test("describes itself as its normalised value")
    func description() {
        #expect(LanguageCode("en-US")?.description == "en")
        #expect("\(LanguageCode.hindi)" == "hi")
    }

    @Test("round-trips through Codable as a plain string")
    func codableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(LanguageCode.hindi)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"hi\"")
        #expect(try JSONDecoder().decode(LanguageCode.self, from: encoded) == .hindi)
    }

    @Test("normalises while decoding")
    func decodingNormalises() throws {
        let decoded = try JSONDecoder().decode(LanguageCode.self, from: Data("\"en-US\"".utf8))
        #expect(decoded == .english)
    }

    @Test("fails to decode an identifier that is not a language")
    func decodingRejectsInvalid() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LanguageCode.self, from: Data("\"123\"".utf8))
        }
    }

    @Test("hashes equal values identically so it can key a dictionary")
    func hashable() {
        let byLanguage: [LanguageCode: String] = [.english: "en", .hindi: "hi"]
        #expect(byLanguage[LanguageCode("en-GB") ?? .hindi] == "en")
    }
}
