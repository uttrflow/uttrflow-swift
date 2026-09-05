import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

/// The joined text of pieces the tidier has already finished, laid out for one destination.
private func joined(_ pieces: [String], _ destination: Destination) -> String {
    PieceJoiner.laidOut(pieces, under: .standard(for: destination))
}

/// A piece carrying only its cleaned words, for the tests that are about the layout.
private func piece(
    _ text: String, heard: String? = nil, by producedBy: TransformerKind = .rules,
    corrections: [DictationCorrection] = [], language: DetectedLanguage? = nil,
    segments: [TranscriptionSegment] = [], duration: Duration = .zero
) -> Piece {
    let spoken = heard ?? text
    return Piece(
        heard: Transcription(
            text: spoken, detectedLanguage: language, segments: segments, audioDuration: duration),
        corrected: CorrectedTranscript(text: spoken, corrections: corrections),
        cleaned: TransformationResult(text: text, producedBy: producedBy))
}

@Suite("PieceJoiner lists")
struct PieceJoinerListTests {
    @Test("makes a list of a spoken sequence across pieces, where the place allows one")
    func listInADocument() {
        let text = joined(
            ["First, we need to fix the build.", "Second, we should review the PR.", "Third, ship it."],
            .document)
        #expect(text == "- We need to fix the build\n- We should review the PR\n- Ship it")
    }

    @Test("counts a list in cardinals as readily as in ordinals")
    func cardinalList() {
        #expect(
            joined(["One, fix the build.", "Two, review the PR."], .email)
                == "- Fix the build\n- Review the PR")
    }

    @Test("reads the number of an item through the word that announces it")
    func numberedList() {
        #expect(
            joined(["Number one, fix the build.", "Number two, review the PR."], .document)
                == "- Fix the build\n- Review the PR")
        #expect(
            joined(["Point one, fix the build.", "Point two, review the PR."], .document)
                == "- Fix the build\n- Review the PR")
    }

    @Test("leaves the list prose where the place has no lists")
    func chatKeepsProse() {
        let pieces = ["First, we need to fix the build.", "Second, we should review the PR."]
        #expect(
            joined(pieces, .messaging)
                == "First, we need to fix the build.\n\nSecond, we should review the PR.")
        #expect(
            joined(pieces, .spreadsheet)
                == "First, we need to fix the build. Second, we should review the PR.")
    }

    @Test("keeps the prose a list is introduced with, above the items")
    func leadInStaysProse() {
        let text = joined(
            ["There are two things to do.", "First, fix the build.", "Second, review the PR."], .document)
        #expect(text == "There are two things to do.\n- Fix the build\n- Review the PR")
    }

    @Test("one sequence word is prose, however plainly it counts")
    func oneItemIsProse() {
        #expect(
            joined(["First, we fix the build.", "Then we ship it."], .document)
                == "First, we fix the build. Then we ship it.")
    }

    @Test("a sequence that stops before the end is prose, since the speaker went on without it")
    func brokenSequenceIsProse() {
        let text = joined(
            ["First, fix the build.", "Second, review the PR.", "And then the other thing."], .document)
        #expect(text == "First, fix the build.\n\nSecond, review the PR. And then the other thing.")
    }

    @Test("a sequence that does not start at one is prose, since the first item is not a piece")
    func sequenceMustStartAtOne() {
        #expect(
            joined(["Second, review the PR.", "Third, ship it."], .document)
                == "Second, review the PR.\n\nThird, ship it.")
    }

    @Test("an item naming a thing rather than saying something about it is prose")
    func bareNounsAreProse() {
        #expect(joined(["First, milk.", "Second, eggs."], .document) == "First, milk.\n\nSecond, eggs.")
        #expect(
            joined(["First, the milk and the eggs.", "Second, the bread."], .document)
                == "First, the milk and the eggs.\n\nSecond, the bread.")
    }

    @Test("counts ordinals and cardinals as different sequences, so a mixed one is prose")
    func mixedSequenceIsProse() {
        #expect(
            joined(["First, fix the build.", "Two, review the PR."], .document)
                == "First, fix the build. Two, review the PR.")
    }
}

@Suite("PieceJoiner paragraphs")
struct PieceJoinerParagraphTests {
    @Test("opens a paragraph where the next piece opens a topic")
    func topicWordStartsAParagraph() {
        #expect(
            joined(["Thanks for the update.", "Also, I'll send the deck tomorrow."], .email)
                == "Thanks for the update.\n\nAlso, I'll send the deck tomorrow.")
        #expect(
            joined(["We shipped the build.", "Moving on to the release notes."], .document)
                == "We shipped the build.\n\nMoving on to the release notes.")
        #expect(
            joined(["That is the plan.", "Okay so the other thing is the schema."], .document)
                == "That is the plan.\n\nOkay so the other thing is the schema.")
    }

    @Test("joins with a space where the next piece carries the same thought on")
    func plainContinuationIsASpace() {
        #expect(
            joined(["The build passed.", "We can ship it this afternoon."], .document)
                == "The build passed. We can ship it this afternoon.")
    }

    @Test("never breaks a line in a cell")
    func spreadsheetStaysOnOneLine() {
        #expect(
            joined(["Thanks for the update.", "Also, the deck is ready."], .spreadsheet)
                == "Thanks for the update. Also, the deck is ready.")
    }

    @Test("leaves a place that keeps the speaker's own line breaks to join with a space")
    func codeJoinsWithASpace() {
        #expect(
            joined(["let total = 0", "Next, we sum the rows"], .codeEditor)
                == "let total = 0 Next, we sum the rows")
    }
}

@Suite("PieceJoiner restatements")
struct PieceJoinerRestatementTests {
    @Test("drops the half the speaker replaced when the correction straddles the cut")
    func restatementAcrossTheCut() {
        #expect(joined(["Let's meet at four.", "No, sorry, at five."], .document) == "Let's meet at five.")
    }

    @Test("matches two numbers across the cut the way the pass does inside one piece")
    func numbersAcrossTheCut() {
        #expect(joined(["Coffee at 2.", "Actually 3."], .document) == "Coffee at 3.")
    }

    @Test("keeps both halves when the piece after the trigger says something else")
    func unmatchedTriggerKeepsEverything() {
        #expect(
            joined(["The build passed.", "Actually I should check the tests."], .document)
                == "The build passed. Actually I should check the tests.")
    }

    @Test("drops the half a piece restates with no trigger at all")
    func untriggeredRestatementAcrossTheCut() {
        #expect(
            joined(["Let's meet on tuesday.", "On wednesday afternoon."], .document)
                == "Let's meet on wednesday afternoon.")
    }

    @Test("keeps both pieces when the repeat opens a clause rather than restating one")
    func untriggeredRepeatThatIsAClause() {
        #expect(
            joined(["I like tea.", "I like coffee, both are fine."], .document)
                == "I like tea. I like coffee, both are fine.")
    }

    @Test("never opens a paragraph on a piece whose opening it swallowed")
    func aRestatementIsNeverAParagraph() {
        #expect(
            joined(["We ship on the third.", "No, sorry, on the fourth."], .document)
                == "We ship on the fourth.")
    }
}

@Suite("PieceJoiner whole")
struct PieceJoinerWholeTests {
    @Test("a lone piece is its own whole")
    func onePiece() {
        let only = piece("Ship it.")
        #expect(PieceJoiner.join([only], under: .standard(for: .document)).cleaned.text == "Ship it.")
    }

    @Test("no pieces at all join to nothing")
    func noPieces() {
        let whole = PieceJoiner.join([], under: .standard(for: .document))
        #expect(whole.cleaned.text.isEmpty)
        #expect(whole.heard.text.isEmpty)
    }

    @Test("carries the language of the first piece, every segment, and the whole audio")
    func heardIsTheWholeDictation() {
        let first = piece(
            "One.", language: .init(code: .hindi, confidence: 1),
            segments: [TranscriptionSegment(text: "one", start: .zero, end: .seconds(1))],
            duration: .seconds(1))
        let second = piece(
            "Two.", language: .init(code: .english, confidence: 1),
            segments: [TranscriptionSegment(text: "two", start: .zero, end: .seconds(2))],
            duration: .seconds(2))
        let whole = PieceJoiner.join([first, second], under: .standard(for: .document))
        #expect(whole.heard.text == "One. Two.")
        #expect(whole.heard.detectedLanguage?.code == .hindi)
        #expect(whole.heard.segments.count == 2)
        #expect(whole.heard.audioDuration == .seconds(3))
    }

    @Test("one piece the model left to the rules makes the whole a rules result")
    func oneRulesPieceDecidesTheWhole() {
        let model = piece("Ship it.", by: .foundationModels)
        #expect(
            PieceJoiner.join([model, model], under: .standard(for: .document)).cleaned.producedBy
                == .foundationModels)
        #expect(
            PieceJoiner.join([model, piece("Ship it.")], under: .standard(for: .document)).cleaned
                .producedBy == .rules)
    }

    @Test("moves each correction's words past the pieces before it")
    func correctionsShift() {
        let entry = UUID()
        let correction = DictationCorrection(
            heard: "cubernetes", wrote: "Kubernetes", wordRange: 1..<2, entryID: entry,
            reason: "dictionary", heardConfidence: 0.3)
        let whole = PieceJoiner.join(
            [
                piece("First, we deploy it.", heard: "first we deploy it"),
                piece(
                    "Second, cubernetes restarts.", heard: "second cubernetes restarts",
                    corrections: [correction]),
            ], under: .standard(for: .document))
        #expect(whole.corrected.corrections.map(\.wordRange) == [5..<6])
    }

    @Test("leaves a correction pointing at its own word after the layout took words out")
    func correctionsSurviveTheLayout() {
        let entry = UUID()
        let correction = DictationCorrection(
            heard: "peeair", wrote: "PR", wordRange: 3..<4, entryID: entry, reason: "dictionary",
            heardConfidence: 0.3)
        let whole = PieceJoiner.join(
            [
                piece("First, fix the build.", heard: "first fix the build"),
                piece(
                    "Second, review the PR.", heard: "second review the peeair",
                    corrections: [correction]),
            ], under: .standard(for: .document))
        // The words the joiner drops are the tidied ones; a range indexes what was heard.
        #expect(whole.cleaned.text == "- Fix the build\n- Review the PR")
        let words = whole.heard.text.split(separator: " ")
        let range = try? #require(whole.corrected.corrections.first?.wordRange)
        #expect(range == 7..<8)
        #expect(words[7] == "peeair")
    }
}
