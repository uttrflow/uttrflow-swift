import Testing

@testable import UttrflowPredict

@Suite("Suggestion text safety")
struct SuggestionTextSafetyTests {
    @Test("a family emoji joined by zero-width joiners is allowed")
    func familyEmoji() {
        #expect(SuggestionTextSafety.allows("great work 👨\u{200D}👩\u{200D}👧"))
    }

    @Test("a flag built from tag scalars is allowed")
    func flagSequence() {
        let scotland = "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        #expect(SuggestionTextSafety.allows("go \(scotland)"))
    }

    @Test("a bare or stray joiner is rejected")
    func bareJoiner() {
        #expect(!SuggestionTextSafety.allows("a\u{200D}b"))
        #expect(!SuggestionTextSafety.allows("\u{200D}👧"))
        #expect(!SuggestionTextSafety.allows("👧\u{200D}"))
        #expect(!SuggestionTextSafety.allows("a\u{E0067}\u{E007F}"))
        #expect(!SuggestionTextSafety.allows("🏴\u{E0067}"))
    }

    @Test("invisible controls and bidi marks are still rejected")
    func invisibles() {
        for scalar in ["\u{200B}", "\u{202E}", "\u{2066}", "\u{FEFF}", "\u{1B}", "\u{FFFD}"] {
            #expect(!SuggestionTextSafety.allows("ok \(scalar)"), "\(scalar.unicodeScalars.first!.value)")
        }
        #expect(SuggestionTextSafety.allows("plain words"))
    }
}
