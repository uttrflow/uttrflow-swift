import Testing

@testable import UttrflowCore
@testable import UttrflowDictionary

/// A Hindi noun inside a Hindi sentence stays romanised Hindi, even when it sounds like an English word of the person's own. See `Docs/latin-output.md`.
@Suite("Hindi nouns are not restored")
struct HindiNounRestorationTests {
    /// The words of a Devanagari sentence after restoration, with `personal` as the person's dictionary.
    static func restored(_ spoken: String, personal: [String]) -> [String] {
        LoanwordRestoration(personal: personal).restoring(Draft(romanising: Transcription(text: spoken)))
            .words.map(\.text)
    }

    @Test(
        "keeps a Hindi noun that sounds like a personal English word",
        arguments: [
            ("मेरा फल कहाँ है", "file", "phal"),
            ("तेल का दाम क्या है", "tell", "tel"),
            ("उसकी बात सुनो ना", "bat", "baat"),
            ("मेरा नाम क्या है", "name", "naam"),
            ("ये दाल किसकी है", "doll", "daal"),
        ])
    func hindiNounStays(spoken: String, personal: String, noun: String) {
        let words = Self.restored(spoken, personal: [personal])
        #expect(words.contains(noun))
        #expect(!words.contains(personal))
    }

    @Test("restores the same personal word in an English sentence")
    func englishSentenceRestores() {
        #expect(
            Self.restored("please open the फ़ाइल", personal: ["file"]) == ["please", "open", "the", "file"])
        #expect(
            Self.restored("can you send the फ़ोटो", personal: ["photo"]) == [
                "can", "you", "send", "the", "photo",
            ])
    }

    @Test("restores a name in a Hindi sentence, which no Hindi word is")
    func nameInHindiSentenceRestores() {
        let words = Self.restored("ये फ़ोटो ओरवांटा पर भेज दो", personal: ["Orvanta"])
        #expect(words.contains("Orvanta"))
    }
}
