import Testing

@testable import UttrflowPredict

@Suite("Which script a suggestion may write")
struct LatinScriptTests {
    @Test(
        "Latin with accents, emoji, symbols and any script's punctuation is Latin text.",
        arguments: [
            "haan theek hai", "café naïve Zoë", "cafe\u{301}", "on my way 🚗 👍🏽 🇮🇳 1️⃣ ❤️ 👨‍👩‍👧",
            "MitoActive™ ®©", "₹500 — “quoted” ½ ²", "ﬁne Ｆｕｌｌ ① 𝐚𝟏", "done।", "ok。", "",
            "git commit -m 'fix'",
        ])
    func latinTextIsLatin(text: String) {
        #expect(LatinScript.writes(text))
    }

    @Test(
        "A letter, mark or digit of any other script makes the text not Latin, however little of it there is.",
        arguments: [
            "नहीं", "ok नहीं", "ज़िंदगी", "abc ०१२", "你好", "こんにちは", "مرحبا", "Привет", "γειά", "٣", "𝛼", "𝐚𝛼",
            "a\u{93C}",
        ])
    func otherScriptsAreNot(text: String) {
        #expect(!LatinScript.writes(text))
    }

    @Test(
        "The person's earlier lines in another script are not part of the situation a suggestion is written from."
    )
    func recentLinesKeepOnlyLatin() {
        let situation = GenerationSituation(
            application: "Chat", recentLines: ["haan bilkul", "नहीं जाना", "kal milte hain", "ok 你好"])
        #expect(situation.recentLines == ["haan bilkul", "kal milte hain"])
        #expect(situation.choosing(["a"]).recentLines == ["haan bilkul", "kal milte hain"])
    }
}
