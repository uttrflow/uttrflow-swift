import Testing
import UttrflowCore

@testable import UttrflowDictionary

/// Regression for issue 217: the shared restraint, tested where it lives.
@Suite("Issue 217: the restraint a sound key cannot supply itself")
struct ReadingRestraintTests {
    @Test("a reading has to sound within one phoneme of what was heard, a vowel for a vowel costing half")
    func soundsNear() {
        #expect(ReadingRestraint.soundsNear("Cache", heard: "cash"))
        #expect(ReadingRestraint.soundsNear("mod", heard: "made"))
        #expect(ReadingRestraint.soundsNear("bot", heard: "but"))
        #expect(!ReadingRestraint.soundsNear("elephant", heard: "cash"))
        #expect(!ReadingRestraint.soundsNear("kestrel", heard: "cash"))
    }

    /// The spelling branch is what "payment sheet" reaches `PaymentSheet` through, and it closes spaces up.
    @Test("reads a spoken run and a closed-up spelling as sounding the same way")
    func readsAClosedUpSpelling() {
        #expect(ReadingRestraint.soundsNear("PaymentSheet", heard: "payment sheet"))
        #expect(ReadingRestraint.soundsNear("amount", heard: "a mount"))
    }

    @Test("a reading worth offering shares a sound key, sounds within one phoneme, and is another spelling")
    func isWorthOffering() {
        #expect(ReadingRestraint.isWorthOffering("Cache", for: "cash"))
        #expect(!ReadingRestraint.isWorthOffering("Cache", for: "cache"))
        #expect(ReadingRestraint.isWorthOffering("mod", for: "made"))
        #expect(!ReadingRestraint.isWorthOffering("elephant", for: "cash"))
    }

    /// Two ordinary words on one sound key is a collision, so a screen full of `main` says nothing about a spoken "mean".
    @Test("refuses one ordinary word as a reading of another")
    func vetoesTwoOrdinaryWords() {
        #expect(ReadingRestraint.bothOrdinary("main", heard: "man"))
        #expect(!ReadingRestraint.isWorthOffering("main", for: "man"))
        #expect(!ReadingRestraint.isWorthOffering("man", for: "main"))
        #expect(!ReadingRestraint.isWorthOffering("mean", for: "main"))
    }

    /// The veto asks that both be ordinary, so a term the screen shows is still a reading of a word everybody knows.
    @Test("keeps a reading only one side of which is an ordinary word")
    func keepsAHalfOrdinaryReading() {
        #expect(!ReadingRestraint.bothOrdinary("Kestrel", heard: "kestral"))
        #expect(ReadingRestraint.isWorthOffering("Cache", for: "cash"))
        #expect(ReadingRestraint.isWorthOffering("Kestrel", for: "kestral"))
        #expect(ReadingRestraint.isWorthOffering("Maine", for: "main"))
    }


    /// Regression for issue 1572: a homophone is a reading even when its spelling opens differently.
    @Test("offers a homophone whose opening letters differ")

    func offersAListedHomophoneThatOpensDifferently() {
        #expect(ReadingRestraint.soundsNear("cell", heard: "sell"))
        #expect(ReadingRestraint.isWorthOffering("cell", for: "sell"))
        #expect(ReadingRestraint.isWorthOffering("weight", for: "wait"))
        #expect(GeneralVocabulary.wordsSounding(like: "write").contains("right"))
    }

    @Test("a one-letter word is a reading of itself and not of a word a whole phoneme longer")
    func handlesShortWords() {
        #expect(ReadingRestraint.soundsNear("a", heard: "a"))
        #expect(!ReadingRestraint.soundsNear("a", heard: "at"))
        #expect(!ReadingRestraint.isWorthOffering("", for: "cash"))
    }

    /// The two forms must ask the same question, or a caller that prepares its words gets different answers.
    @Test(
        "answers a prepared pair exactly as it answers two strings",
        arguments: [
            ("Marcie", "marcy"), ("kubectl", "cube cuttle"), ("there", "their"),
            ("pgvector", "pg vector"), ("hello", "hello"), ("cat", "dog"),
        ]
    )
    func preparedAgreesWithStrings(reading: String, heard: String) {
        #expect(
            ReadingRestraint.isWorthOffering(ReadingKey(reading), for: ReadingKey(heard))
                == ReadingRestraint.isWorthOffering(reading, for: heard))
    }

    @Test("works the spelling and the sound out once, at the key rather than at every comparison")
    func keyCarriesWhatTheCheckAsks() {
        let key = ReadingKey("Payment Sheet")

        #expect(key.word == "Payment Sheet")
        #expect(key.closed == ReadingRestraint.closedUp("Payment Sheet"))
        #expect(key.sound == WordSound(of: "Payment Sheet"))
    }
}
