import Testing
import UttrflowAI

/// Each gate is measured on its own, so a pair the key links but the opening letters refuse shows as such.
@Suite("SoundAlikeReach")
struct SoundAlikeReachTests {
    @Test("A pair sharing a key but not its opening letters is stopped by the restraint")
    func keyWithoutOpening() {
        let reach = SoundAlikeReach(heard: "vest", meant: "west")
        #expect(reach.sharesKey)
        #expect(!reach.passesOpening)
        #expect(!reach.entrySpells)
    }

    @Test("A pair with different keys is reached by no gate")
    func differentKeys() {
        let reach = SoundAlikeReach(heard: "rock", meant: "lock")
        #expect(!reach.sharesKey)
        #expect(!reach.passesOpening)
        #expect(!reach.entrySpells)
    }

    @Test("A pair sharing key and opening passes both, and the entry accepts it")
    func keyAndOpening() {
        let reach = SoundAlikeReach(heard: "ship", meant: "sheep")
        #expect(reach.sharesKey)
        #expect(reach.passesOpening)
        #expect(reach.entrySpells)
    }

    @Test("A run of words is read as one against the entry")
    func multiWordRun() {
        let reach = SoundAlikeReach(heard: "post gres", meant: "postgres")
        #expect(reach.sharesKey)
        #expect(reach.entrySpells)
        #expect(reach.isSameSpelling)
    }

    @Test("The same word in other case and spacing is no miss")
    func sameSpelling() {
        #expect(SoundAlikeReach(heard: "Post GreSQL", meant: "PostgreSQL").isSameSpelling)
    }
}
