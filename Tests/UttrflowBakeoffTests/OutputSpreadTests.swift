// Tests that repeated bake-off runs report which cases changed their answer.
import Testing
@testable import uttrflow_bakeoff

struct OutputSpreadTests {
    @Test("a case that wrote the same text every run never flips")
    func stableCase() {
        let spread = OutputSpread()
        for _ in 0..<3 { spread.record("Hello.", forCase: "a") }
        #expect(spread.flipped.isEmpty)
        #expect(spread.stableShare == 1)
    }

    @Test("a case that wrote two texts over three runs flips with two distinct outputs")
    func flippingCase() throws {
        let spread = OutputSpread()
        for text in ["Hello.", "Hello!", "Hello."] { spread.record(text, forCase: "a") }
        for _ in 0..<3 { spread.record("Fine.", forCase: "b") }
        let flip = try #require(spread.flipped.first)
        #expect(spread.flipped.count == 1)
        #expect(flip.id == "a" && flip.distinct == 2 && flip.runs == 3)
        #expect(spread.stableShare == 0.5)
        #expect(spread.lines.first?.contains("1 of 2 cases never flipped over 3 runs") == true)
    }

    @Test("--repeat defaults to one run and refuses zero")
    func repeatOption() throws {
        #expect(try Bakeoff.parse([]).repeatCount == 1)
        #expect(try Bakeoff.parse(["--repeat", "10"]).repeatCount == 10)
        #expect(throws: (any Error).self) { try Bakeoff.parse(["--repeat", "0"]) }
    }
}
