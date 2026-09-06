import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("SpacingPass")
struct SpacingPassTests {
    private let sut = SpacingPass()

    @Test(
        "fixes a stray mark onto the word before it and collapses doubled marks",
        arguments: [
            ("hello , there", "hello, there"),
            ("wait .", "wait."),
            ("milk,, eggs", "milk, eggs"),
            ("hello ... there", "hello... there"),
            ("hello there", "hello there"),
            (", hello", ", hello"),
        ]
    )
    func spacing(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("records the moved mark against the word that took it")
    func provenance() {
        let draft = sut.apply(Draft(text: "hello ,"))
        #expect(draft.words[0].state == .replaced(by: SpacingPass.id, from: "hello"))
        #expect(draft.words[1].state == .removed(by: SpacingPass.id))
    }
}
