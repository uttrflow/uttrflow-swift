import Testing

@testable import UttrflowLocalModel

/// A vocabulary small enough to name every token: 0 " l", 1 " log", 2 "og", 3 newline, 4 " commit", 5 nothing, 6 "x", 7 a lone space.
private let vocabulary = TokenHealing.Vocabulary(
    texts: [" l", " log", "og", "\n", " commit", "", "x", " "], ending: [3])

/// A healing for a word still being typed, which is the common case.
private func healing(owing owed: String) -> TokenHealing {
    TokenHealing(vocabulary: vocabulary, owed: owed, wordComplete: false)
}

@Suite("Holding the first tokens to the word being typed")
struct TokenHealingTests {
    @Test(
        "While a word is owed, only tokens that keep to it may be produced, whether shorter or longer than it."
    )
    func onlyTheOwedWordIsAllowed() {
        let allowed = vocabulary.allowed(owing: Array(" l".utf8), wordComplete: false)
        // The lone space is the start of the owed word, so it may be spelt on its own.
        #expect(allowed == [true, true, false, false, false, false, false, true])
    }

    @Test(
        "A word the person finished is written exactly, never lengthened, and what follows it begins with a space."
    )
    func aFinishedWordIsNeverLengthened() {
        #expect(
            vocabulary.allowed(owing: Array(" l".utf8), wordComplete: true) == [
                true, false, false, false, false, false, false, true,
            ])
        #expect(
            vocabulary.allowed(owing: Array("".utf8), wordComplete: true) == [
                true, true, false, false, true, false, false, false,
            ])
    }

    @Test(
        "With the word complete, any token that adds a character is allowed, but not one that ends the line.")
    func aFinishedWordMustBeContinued() {
        let allowed = vocabulary.allowed(owing: Array("".utf8), wordComplete: false)
        #expect(allowed == [true, true, true, false, true, false, true, false])
    }

    @Test("A token longer than what is owed finishes the word and frees the model at once.")
    func aLongerTokenFreesTheModel() {
        var healing = healing(owing: " l")
        healing.took(" log")
        #expect(healing.isFree && healing.owed.isEmpty)
    }

    @Test(
        "A token that only reaches the end of the word leaves one more character owed before the model is free."
    )
    func anExactTokenStillOwesAContinuation() {
        var healing = healing(owing: " l")
        healing.took(" l")
        #expect(!healing.isFree && healing.owed.isEmpty)
        // A lone space is not the character owed, so the model is still held.
        healing.took(" ")
        #expect(!healing.isFree)
        healing.took("og")
        #expect(healing.isFree)
    }

    @Test(
        "A token the mask should have refused frees the model rather than holding it to a word it has left.")
    func aStrayTokenFreesTheModel() {
        var healing = healing(owing: " log")
        healing.took(" commit")
        #expect(healing.isFree && healing.owed.isEmpty)
    }

    @Test(
        "The mask adds nothing to allowed tokens, removes the rest and the padding past the vocabulary, and is gone once the model is free."
    )
    func theMaskFollowsTheAllowance() {
        var healing = healing(owing: " l")
        let mask = healing.mask(width: 8)
        #expect(mask?[0] == 0 && mask?[1] == 0)
        #expect(mask?[2] == -.infinity && mask?[5] == -.infinity)
        #expect(mask?.count == 8)
        healing.took(" log")
        #expect(healing.mask(width: 8) == nil)
    }

    @Test("A word no token can keep to leaves the logits untouched, so the pass runs on instead of failing.")
    func anUnmatchableWordLeavesTheModelFree() {
        #expect(healing(owing: "zzz").mask(width: 7) == nil)
    }

    @Test("A vocabulary narrower than the model's head never allows a token in the padding.")
    func thePaddingIsNeverAllowed() {
        let mask = healing(owing: "").mask(width: 10)
        #expect(mask?[8] == -.infinity && mask?[9] == -.infinity && mask?[6] == 0 && mask?[7] == -.infinity)
    }

    @Test("A piece writes its bytes: the word-start mark as a space, a byte piece as the one byte it names.")
    func piecesWriteBytes() {
        #expect(TokenHealing.Vocabulary.bytes(of: "\u{2581}log") == Array(" log".utf8))
        #expect(TokenHealing.Vocabulary.bytes(of: "<0x0A>") == [0x0A])
        #expect(TokenHealing.Vocabulary.bytes(of: "<0xF0>") == [0xF0])
        #expect(TokenHealing.Vocabulary.bytes(of: "<0xZZ>") == Array("<0xZZ>".utf8))
    }

    @Test(
        "A word spelt in byte tokens, such as an emoji, is owed byte by byte, so the mark is held to as any word is."
    )
    func bytePiecesSpellAnOwedEmoji() {
        let spelt = TokenHealing.Vocabulary(
            bytes: [[0xF0], [0x9F], [0x91], [0x8D], Array(" ok".utf8), [0x0A]], ending: [5])
        var healing = TokenHealing(vocabulary: spelt, owed: " \u{1F44D}", wordComplete: true)
        #expect(
            spelt.allowed(owing: healing.owed, wordComplete: true) == [
                false, false, false, false, false, false,
            ])
        healing.took(" ")
        #expect(
            spelt.allowed(owing: healing.owed, wordComplete: true) == [
                true, false, false, false, false, false,
            ])
        for byte in [[0xF0], [0x9F], [0x91], [0x8D]] as [[UInt8]] { healing.took(byte) }
        #expect(healing.owed.isEmpty && !healing.isFree)
        #expect(spelt.allowed(owing: [], wordComplete: true) == [false, false, false, false, true, false])
    }
}
