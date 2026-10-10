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
        #expect(vocabulary.allowedIDs(owing: Array(" l".utf8), wordComplete: false) == [0, 1, 7])
        #expect(vocabulary.allowedIDs(owing: Array(" l".utf8), wordComplete: true) == [0, 7])
    }

    @Test("The indexed allowed ids match the full predicate for every mask state")
    func indexedAllowedIdsMatchReferencePredicate() {
        for owed in [Array(" l".utf8), Array("log".utf8), Array("x".utf8), []] {
            for wordComplete in [false, true] {
                let reference = vocabulary.allowed(owing: owed, wordComplete: wordComplete)
                    .enumerated().compactMap { $0.element ? $0.offset : nil }
                #expect(vocabulary.allowedIDs(owing: owed, wordComplete: wordComplete) == reference)
            }
        }
    }

    @Test("Large vocabularies reuse compact indexes for every prefix length")
    func prefixIndexIsBuiltLazilyOnce() {
        let texts = [" l", " log", "og", "x"] + (0..<2_000).map { "unrelated-\($0)" }
        let largeVocabulary = TokenHealing.Vocabulary(texts: texts, ending: [])

        #expect(largeVocabulary.prefixIndexBuilds == 0)
        #expect(largeVocabulary.ids(startingWith: Array(" l".utf8)) == [0, 1])
        #expect(largeVocabulary.prefixIndexBuilds == 1)
        #expect(largeVocabulary.ids(startingWith: Array(" lo".utf8)) == [1])
        #expect(largeVocabulary.prefixIndexBuilds == 1)
        #expect(largeVocabulary.ids(startingWith: Array(" l".utf8)) == [0, 1])
        #expect(largeVocabulary.prefixIndexBuilds == 1)
        #expect(largeVocabulary.ids(startingWith: Array(" log".utf8)) == [1])
        #expect(largeVocabulary.prefixIndexBuilds == 1)
    }

    @Test("Prefix lookup keeps duplicate tokens and excludes shorter tokens")
    func prefixIndexKeepsDuplicateAndBoundaryMatches() {
        let vocabulary = TokenHealing.Vocabulary(
            bytes: [[], Array("a".utf8), Array("ab".utf8), Array("a".utf8)], ending: [])

        #expect(vocabulary.ids(startingWith: Array("a".utf8)) == [1, 2, 3])
        #expect(vocabulary.prefixIndexBuilds == 1)
        #expect(vocabulary.ids(startingWith: Array("ab".utf8)) == [2])
        #expect(vocabulary.prefixIndexBuilds == 2)
        #expect(vocabulary.ids(startingWith: Array("abc".utf8)).isEmpty)
        #expect(vocabulary.prefixIndexBuilds == 2)
    }

    @Test("Variable-width prefix index preserves prefix boundaries and duplicate tokens")
    func variableWidthPrefixIndexPreservesBoundariesAndDuplicates() {
        let vocabulary = TokenHealing.Vocabulary(
            bytes: [
                Array("abc".utf8), Array("a".utf8), Array("ab".utf8), Array("b".utf8),
                Array("aa".utf8), Array("a".utf8), [],
            ], ending: [])

        #expect(vocabulary.ids(startingWith: Array("a".utf8)) == [0, 1, 2, 4, 5])
        #expect(vocabulary.ids(startingWith: Array("ab".utf8)) == [0, 2])
        #expect(vocabulary.ids(startingWith: Array("abc".utf8)) == [0])
        #expect(vocabulary.prefixIndexBuilds == 2)
        #expect(vocabulary.ids(startingWith: Array("b".utf8)) == [3])
        #expect(vocabulary.prefixIndexBuilds == 2)
        #expect(vocabulary.ids(startingWith: Array("c".utf8)).isEmpty)
        #expect(vocabulary.prefixIndexBuilds == 2)
    }

    @Test("A reloaded vocabulary reuses prefix indexes for the same tokenizer")
    func prefixIndexSurvivesVocabularyReload() {
        let prefixIndex = TokenHealing.Vocabulary.PrefixIndex()
        let bytes = [Array(" l".utf8), Array(" log".utf8), Array("og".utf8)]

        var firstLoad: TokenHealing.Vocabulary? = TokenHealing.Vocabulary(
            bytes: bytes, ending: [], prefixIndex: prefixIndex)
        #expect(firstLoad?.ids(startingWith: Array(" l".utf8)) == [0, 1])
        #expect(firstLoad?.prefixIndexBuilds == 1)
        firstLoad = nil

        let reloaded = TokenHealing.Vocabulary(bytes: bytes, ending: [], prefixIndex: prefixIndex)
        #expect(reloaded.ids(startingWith: Array(" l".utf8)) == [0, 1])
        #expect(reloaded.prefixIndexBuilds == 1)
        #expect(reloaded.ids(startingWith: Array(" log".utf8)) == [1])
        #expect(reloaded.prefixIndexBuilds == 1)
        #expect(reloaded.ids(startingWith: Array(" l".utf8)) == [0, 1])
        #expect(reloaded.prefixIndexBuilds == 1)
    }

    @Test("An emptied prefix index is rebuilt from nothing by the next vocabulary")
    func emptiedPrefixIndexIsRebuilt() {
        let prefixIndex = TokenHealing.Vocabulary.PrefixIndex()
        let bytes = [Array(" l".utf8), Array(" log".utf8), Array("og".utf8)]

        let firstLoad = TokenHealing.Vocabulary(bytes: bytes, ending: [], prefixIndex: prefixIndex)
        #expect(firstLoad.ids(startingWith: Array("o".utf8)) == [2])
        #expect(firstLoad.ids(startingWith: Array(" l".utf8)) == [0, 1])
        #expect(prefixIndex.builds == 2)

        prefixIndex.forget()
        #expect(prefixIndex.builds == 0)

        let reloaded = TokenHealing.Vocabulary(bytes: bytes, ending: [], prefixIndex: prefixIndex)
        #expect(reloaded.ids(startingWith: Array(" log".utf8)) == [1])
        #expect(reloaded.prefixIndexBuilds == 1)
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

    @Test("GPT byte-level spellings write their original bytes, including spaces, line breaks and controls.")
    func byteLevelPiecesWriteBytes() {
        #expect(TokenHealing.Vocabulary.bytes(of: "Ġhello") == Array(" hello".utf8))
        #expect(TokenHealing.Vocabulary.bytes(of: "Ċ") == [0x0A])
        #expect(TokenHealing.Vocabulary.bytes(of: "ĠĠ") == [0x20, 0x20])
        #expect(TokenHealing.Vocabulary.bytes(of: "Ā") == [0x00])
        #expect(TokenHealing.Vocabulary.bytes(of: "ĠÃ©") == [0x20, 0xC3, 0xA9])
        #expect(TokenHealing.Vocabulary.bytes(of: "<|im_end|>") == Array("<|im_end|>".utf8))
        #expect(TokenHealing.Vocabulary.bytes(of: "<|stopĊ|>") == Array("<|stop\n|>".utf8))
        #expect(TokenHealing.Vocabulary.bytes(of: "▁word") == Array(" word".utf8))
    }

    @Test(
        "A vocabulary marker selects byte decoding for ordinary and multibyte pieces without a model download."
    )
    func vocabularySelectsByteLevelDecoding() {
        let byteLevel = TokenHealing.Vocabulary(texts: ["Ġ", "Ã©", "<|im_end|>"], ending: [])
        #expect(byteLevel.bytes == [[0x20], [0xC3, 0xA9], Array("<|im_end|>".utf8)])
        let sentencePiece = TokenHealing.Vocabulary(texts: ["▁", "é"], ending: [])
        #expect(sentencePiece.bytes == [Array(" ".utf8), Array("é".utf8)])
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

    @Test(
        "Anything but a letter or digit at a token's front starts something new, a space of any width included."
    )
    func onlyALetterOrDigitLengthensTheWord() {
        let marks = TokenHealing.Vocabulary(
            texts: ["og", "2x", " l", "\u{A0}l", "-l", ".", "\u{E9}t", ""], ending: [])
        #expect(marks.startsNewWord == [false, false, true, true, true, true, false, false])
    }

    @Test(
        "The person is inside a word only where the last thing they typed is a letter or digit with no space after it."
    )
    func onlyALetterOrDigitLeavesThePersonInsideAWord() {
        #expect(healing(owing: " l").isMidWord)
        #expect(healing(owing: " l2").isMidWord)
        #expect(!healing(owing: " l.").isMidWord)
        #expect(!healing(owing: "").isMidWord)
        #expect(!TokenHealing(vocabulary: vocabulary, owed: " l", wordComplete: true).isMidWord)
    }

    @Test(
        "At the step after a word the person stopped inside, a token that starts a new word is priced below one that lengthens it."
    )
    func aNewWordIsPricedBelowLengtheningTheTypedOne() {
        var healing = healing(owing: " l")
        healing.took(" l")
        let mask = healing.mask(width: 8)
        // "og" and "x" lengthen the word, so they keep the whole of the model's own preference.
        #expect(mask?[2] == 0 && mask?[6] == 0)
        #expect(mask?[0] == -TokenHealing.newWordPenalty && mask?[1] == -TokenHealing.newWordPenalty)
        #expect(mask?[4] == -TokenHealing.newWordPenalty)
        // The penalty prices a break down; it never rules one out, so a word the model is sure of still breaks.
        #expect(TokenHealing.newWordPenalty.isFinite && TokenHealing.newWordPenalty > 0)
        #expect(mask?[3] == -.infinity && mask?[7] == -.infinity)
    }

    @Test("A word the person finished with a space is followed by a new word at no cost.")
    func aFinishedWordIsFollowedAtNoCost() {
        var finished = TokenHealing(vocabulary: vocabulary, owed: " l", wordComplete: true)
        finished.took(" l")
        let mask = finished.mask(width: 8)
        #expect(mask?[0] == 0 && mask?[1] == 0 && mask?[4] == 0)
    }

    @Test(
        "While the word is still owed, lengthening it and breaking it are not yet the choice, so nothing is priced down."
    )
    func nothingIsPricedDownWhileTheWordIsOwed() {
        let mask = healing(owing: " l").mask(width: 8)
        #expect(mask?[0] == 0 && mask?[1] == 0 && mask?[7] == 0)
    }

    @Test(
        "A word that closes the line frees the model once written, so a finished sentence can be left alone.")
    func aClosingWordMayEndTheLine() {
        var closing = TokenHealing(vocabulary: vocabulary, owed: " l", wordComplete: false, mayEnd: true)
        closing.took(" l")
        #expect(closing.isFree)
        var open = healing(owing: " l")
        open.took(" l")
        #expect(!open.isFree)
    }
}
