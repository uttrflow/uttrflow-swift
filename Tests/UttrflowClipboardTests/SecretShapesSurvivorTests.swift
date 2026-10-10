// Tests that fail when a credential rule in SecretShapes is loosened; each case killed a surviving mutant.

import Testing

@testable import UttrflowCore

/// Each case decides a mask on its own rule alone, so no other rule can mask it in that rule's place.
@Suite("Secret shapes that only one rule decides")
struct SecretShapesSurvivorTests {
    @Test("masks a generated token handed over as a URL's username")
    func tokenUserinfo() {
        #expect(SecretShapes.matches("https://Zx9kLmQ2rT7pWq4N@git.example.com/repo.git"))
    }

    @Test("leaves a repetitive URL username that only looks like a token")
    func repetitiveUserinfo() {
        #expect(!SecretShapes.matches("https://aaaa1111bbbb@git.example.com/repo.git"))
    }

    @Test(
        "masks one generated word by its randomness alone",
        arguments: [
            "Zx9kLmQ2rT7pWq4N",
            "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
        ])
    func generatedWord(_ text: String) {
        #expect(SecretShapes.matches(text))
    }

    @Test("masks a generated word cut into a UUID's group lengths when its groups are not hexadecimal")
    func notQuiteUUID() {
        #expect(SecretShapes.matches("Zx9kLmQ2-rT7p-Wq4N-b8Vc-3Hj6Fd1Sa0Ge"))
        #expect(!SecretShapes.matches("550e8400-e29b-41d4-a716-446655440000"))
    }
}
