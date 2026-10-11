// Pins that a seed alone sets the generator's whole sequence.
import Testing
import UttrflowCore

@Suite("A seeded generator")
struct SeededGeneratorTests {
    @Test("the same seed gives the same sequence, and another seed another one")
    func seedSetsTheSequence() {
        var first = SeededGenerator(seed: 7)
        var second = SeededGenerator(seed: 7)
        var other = SeededGenerator(seed: 8)

        let values = (0..<4).map { _ in first.next() }

        #expect(values == (0..<4).map { _ in second.next() })
        #expect(values != (0..<4).map { _ in other.next() })
    }
}
