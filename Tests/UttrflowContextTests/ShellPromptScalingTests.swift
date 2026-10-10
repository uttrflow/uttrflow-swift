import Testing

@testable import UttrflowContext

@Suite("Reading a terminal line for its prompt costs one pass over a bounded stretch")
struct ShellPromptScalingTests {
    /// The characters one reading of this line takes.
    private static func charactersRead(_ line: String) -> Int {
        let tally = CharacterTally()
        ShellPrompt.$tally.withValue(tally) { _ = ShellPrompt.input(in: line) }
        return tally.count
    }

    /// A line of hashes and chevrons, each a terminator whose evidence is the text before it; two words, so no prompt name.
    private static func terminators(_ length: Int) -> String {
        String(String(repeating: "a b# a > ", count: length / 9 + 1).prefix(length))
    }

    @Test("A line under the limit is read once, a character at a time, however many terminators it holds.")
    func readsEachCharacterOnce() {
        for length in [100, 1_000, 4_000] {
            let read = Self.charactersRead(Self.terminators(length))
            #expect(read == length, "\(length) characters took \(read) reads")
        }
    }

    @Test("A line past the limit costs what the limit costs, so a pasted megabyte reads like four kilobytes.")
    func longLinesCostTheLimit() {
        let limit = ShellPrompt.searchLimit
        for length in [10_000, 100_000, 1_000_000] {
            #expect(Self.charactersRead(Self.terminators(length)) == limit)
        }
    }

    @Test("A prompt is found up to the limit and not past it.")
    func promptsEndInsideTheLimit() {
        let near = String(repeating: "a", count: ShellPrompt.searchLimit - 1) + "$ ls"
        let far = String(repeating: "a", count: ShellPrompt.searchLimit) + "$ ls"

        #expect(ShellPrompt.input(in: near) == "ls")
        #expect(ShellPrompt.input(in: far) == far)
    }
}
