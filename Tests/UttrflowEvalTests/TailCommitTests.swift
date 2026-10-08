// Agreement between passes and the seam count both commit policies are scored by.
import Testing
import UttrflowEval

@Suite("Tail commit scoring")
struct TailCommitTests {
    private func words(_ text: String) -> [AlignedWord] {
        text.split(separator: " ").enumerated().map {
            AlignedWord(word: String($1), start: Double($0), end: Double($0) + 0.5)
        }
    }

    @Test("two passes agree on their common leading words, ignoring case and punctuation")
    func agreedPrefix() {
        #expect(TailCommit.agreedPrefix(words("we can ship it"), words("We can, ship them")) == 3)
        #expect(TailCommit.agreedPrefix([], words("we can")) == 0)
    }

    @Test("a clean join counts nothing")
    func cleanJoin() {
        let seams = TailCommit.seamArtefacts(
            pieces: ["we can ship it", "without any changes."],
            reference: "We can ship it without any changes.")
        #expect(seams.seams == 1)
        #expect(seams.total == 0)
    }

    @Test("a stop and a capital at a mid-clause cut are each counted")
    func strayStopAndCapital() {
        let seams = TailCommit.seamArtefacts(
            pieces: ["we can ship it without any.", "And changes."],
            reference: "we can ship it without any and changes.")
        #expect(seams.strayStops == 1)
        #expect(seams.strayCapitals == 1)
    }

    @Test("a repeated word at the join is a duplicate unless the reference repeats it")
    func duplicates() {
        let reference = "we can ship it now"
        #expect(
            TailCommit.seamArtefacts(pieces: ["we can ship", "ship it now"], reference: reference)
                .duplicatedWords == 1)
        #expect(
            TailCommit.seamArtefacts(pieces: ["that", "that works"], reference: "that that works")
                .duplicatedWords == 0)
    }

    @Test("a word lost at the join is dropped")
    func dropped() {
        let seams = TailCommit.seamArtefacts(
            pieces: ["we can ship", "now"], reference: "we can ship it now")
        #expect(seams.droppedWords == 1)
    }

    @Test("the word error rate compares normalized words")
    func wordErrorRate() {
        #expect(TailCommit.wordErrorRate(hypothesis: "We can, ship.", reference: "we can ship").rate == 0)
        #expect(TailCommit.normalized("Ship!") == "ship")
    }
}
