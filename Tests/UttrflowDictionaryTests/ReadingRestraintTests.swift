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

    @Test("a word too short to have an opening is a reading only if it is the same spelling")
    func handlesShortWords() {
        #expect(ReadingRestraint.opensAlike("a", heard: "a"))
        #expect(!ReadingRestraint.opensAlike("a", heard: "at"))
        #expect(!ReadingRestraint.isWorthOffering("", for: "cash"))
    }
}
