import Testing

@testable import UttrflowDictionary

/// Regression for issue 217: the shared restraint, tested where it lives.
@Suite("Issue 217: the restraint a sound key cannot supply itself")
struct ReadingRestraintTests {
    @Test("a reading has to open like what was heard")
    func opensAlike() {
        #expect(ReadingRestraint.opensAlike("Cache", heard: "cash"))
        #expect(!ReadingRestraint.opensAlike("mod", heard: "made"))
        #expect(!ReadingRestraint.opensAlike("bot", heard: "but"))
        #expect(!ReadingRestraint.opensAlike("main", heard: "mean"))
    }

    /// The spelling branch is what "payment sheet" reaches `PaymentSheet` through, and it closes spaces up.
    @Test("reads a spoken run and a closed-up spelling as opening the same way")
    func readsAClosedUpSpelling() {
        #expect(ReadingRestraint.opensAlike("PaymentSheet", heard: "payment sheet"))
        #expect(ReadingRestraint.opensAlike("amount", heard: "a mount"))
    }

    @Test("a reading worth offering sounds alike, opens alike, and is another spelling")
    func isWorthOffering() {
        #expect(ReadingRestraint.isWorthOffering("Cache", for: "cash"))
        #expect(!ReadingRestraint.isWorthOffering("Cache", for: "cache"))
        #expect(!ReadingRestraint.isWorthOffering("mod", for: "made"))
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
        #expect(!ReadingRestraint.bothOrdinary("Cache", heard: "cash"))
        #expect(ReadingRestraint.isWorthOffering("Cache", for: "cash"))
        #expect(ReadingRestraint.isWorthOffering("Kestrel", for: "kestral"))
        #expect(ReadingRestraint.isWorthOffering("Maine", for: "main"))
    }

    @Test("a word too short to have an opening is a reading only if it is the same spelling")
    func handlesShortWords() {
        #expect(ReadingRestraint.opensAlike("a", heard: "a"))
        #expect(!ReadingRestraint.opensAlike("a", heard: "at"))
        #expect(!ReadingRestraint.isWorthOffering("", for: "cash"))
    }
}
