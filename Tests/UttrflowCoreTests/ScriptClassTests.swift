import Testing

@testable import UttrflowCore

@Suite("The one classifier behind both Latin-script predicates")
struct ScriptClassTests {
    @Test(
        "Each scalar class has one decision, and both predicates read it.",
        arguments: [
            (0x0041, ScriptClass.latin), (0x0037, .latin), (0x00E9, .latin), (0x00B2, .latin),
            (0x0101, .latin), (0x1EA1, .latin), (0x0301, .latin), (0x1AB0, .latin), (0xFE20, .latin),
            (0xFF10, .latin), (0xFF21, .latin), (0x1D400, .latin), (0x1D7CE, .latin), (0x1F1E6, .latin),
            (0x0915, .foreignLetter), (0x093C, .foreignLetter), (0x0370, .foreignLetter),
            (0x4F60, .foreignLetter), (0x3007, .foreignLetter), (0x1D6A8, .foreignLetter),
            (0x0966, .foreignNumber), (0x0660, .foreignNumber), (0x06F3, .foreignNumber),
            (0x0020, .latin), (0x0964, .neutral), (0x3002, .neutral), (0x20B9, .latin),
            (0x2122, .latin), (0x1F697, .neutral), (0x1F44D, .neutral), (0x2014, .neutral),
        ] as [(UInt32, ScriptClass)])
    func table(value: UInt32, expected: ScriptClass) throws {
        let scalar = try #require(Unicode.Scalar(value))
        let text = String(scalar)
        #expect(ScriptClass.of(scalar) == expected)
        #expect(LatinScript.isLatin(text) == (expected != .foreignLetter))
        #expect(LatinScript.writesOnlyLatin(text) == [.latin, .neutral].contains(expected))
    }

    @Test(
        "Latin with accents, emoji, symbols and any script's punctuation is Latin text.",
        arguments: [
            "haan theek hai", "café naïve Zoë", "cafe\u{301}", "on my way 🚗 👍🏽 🇮🇳 1️⃣ ❤️ 👨‍👩‍👧",
            "MitoActive™ ®©", "₹500 — “quoted” ½ ²", "ﬁne Ｆｕｌｌ ① 𝐚𝟏", "done।", "ok。", "",
            "git commit -m 'fix'",
        ])
    func latinTextIsLatin(text: String) {
        #expect(LatinScript.writesOnlyLatin(text))
        #expect(LatinScript.isLatin(text))
    }

    @Test(
        "A letter, mark or digit of any other script makes the text not Latin, however little of it there is.",
        arguments: [
            "नहीं", "ok नहीं", "ज़िंदगी", "abc ०१२", "你好", "こんにちは", "مرحبا", "Привет", "γειά", "٣", "𝛼", "𝐚𝛼",
            "a\u{93C}",
        ])
    func otherScriptsAreNot(text: String) {
        #expect(!LatinScript.writesOnlyLatin(text))
    }

    @Test("Another script's digits are not letters, so only the stricter predicate refuses them.")
    func digitsSplitThePredicates() {
        #expect(LatinScript.isLatin("१२"))
        #expect(!LatinScript.writesOnlyLatin("१२"))
    }

    @Test(
        "Text is mostly in an untranscribed script only when such letters outnumber Latin and Devanagari ones.",
        arguments: [
            ("你好，谢谢观看", true), ("Привет, как дела", true), ("شكرا جزيلا", true), ("สวัสดีครับ", true),
            ("안녕하세요", true), ("Let us meet at the Привет cafe", false), ("हाँ ठीक है", false),
            ("haan theek hai", false), ("", false), ("42 — 7", false),
        ] as [(String, Bool)])
    func untranscribedScript(text: String, expected: Bool) {
        #expect(LatinScript.isMostlyUntranscribedScript(text) == expected)
    }
}
