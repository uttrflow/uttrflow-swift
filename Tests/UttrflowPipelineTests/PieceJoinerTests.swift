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
    segments: [TranscriptionSegment] = [], duration: Duration = .zero, entriesTaken: [UUID] = []
) -> Piece {
    let spoken = heard ?? text
    return Piece(
        heard: Transcription(
            text: spoken, detectedLanguage: language, segments: segments, audioDuration: duration),
        corrected: CorrectedTranscript(text: spoken, corrections: corrections),
        cleaned: TransformationResult(text: text, producedBy: producedBy, entriesTaken: entriesTaken))
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

    @Test("reads a marker split by a pause once, as the one marker it is")
    func markerSplitAcrossPieces() {
        #expect(
            joined(["Number", "one, fix the build.", "Number two, review the PR."], .document)
                == "- Fix the build\n- Review the PR")
    }

    @Test("keeps an item body across pieces and ends the list before a closing sentence")
    func sequenceWordOnItsOwnPiece() {
        let text = joined(
            ["Step 1", "Unplug it.", "and keep holding it.", "Step 2", "Plug it in.", "Done."],
            .document)
        #expect(text == "- Unplug it and keep holding it\n- Plug it in\n\nDone.")
    }

    @Test("recognizes numeric ordinal list markers")
    func numericOrdinalList() {
        #expect(
            joined(["1st, clean the data.", "2nd, train the model.", "3rd, evaluate it."], .document)
                == "- Clean the data\n- Train the model\n- Evaluate it")
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

    @Test("ordinal paragraph layout is independent of where pieces are cut")
    func ordinalParagraphsIgnorePieceCuts() {
        let layouts = [
            ["We need a plan. First, finish onboarding. Second, fix login. Third, review design."],
            ["We need a plan. First, finish onboarding.", "Second, fix login. Third, review design."],
            ["We need a plan. First, finish onboarding. Second, fix login.", "Third, review design."],
            ["We need a plan.", "First, finish onboarding. Second, fix login. Third, review design."],
        ].map { joined($0, .messaging) }

        #expect(layouts.allSatisfy { $0 == layouts[0] })
        #expect(
            layouts[0]
                == "We need a plan. First, finish onboarding.\n\nSecond, fix login.\n\nThird, review design.")
    }

    @Test("ordinal list layout is independent of where pieces are cut")
    func ordinalListsIgnorePieceCuts() {
        let layouts = [
            ["First, finish onboarding. Second, fix login. Third, review design."],
            ["First, finish onboarding.", "Second, fix login. Third, review design."],
            ["First, finish onboarding. Second, fix login.", "Third, review design."],
        ].map { joined($0, .document) }

        #expect(layouts.allSatisfy { $0 == layouts[0] })
        #expect(layouts[0] == "- Finish onboarding\n- Fix login\n- Review design")
    }

    @Test(
        "lays out a spoken sequence the same at every cut between its sentences",
        arguments: [Destination.document, .messaging, .email],
        [
            ["We need a plan.", "First, finish onboarding.", "Second, fix login.", "Third, review design."],
            ["First, milk.", "Second, eggs."],
            ["First place went to Sam.", "Second place went to Priya.", "Third place went to Lee."],
            ["There are two things to do.", "First, fix the build.", "Second, review the PR."],
            ["Second, review the PR.", "Third, ship it."],
        ])
    func sequenceLayoutHoldsAtEveryCut(destination: Destination, sentences: [String]) {
        let cuts = (0..<(1 << (sentences.count - 1))).map { mask in
            sentences.indices.dropFirst().reduce(into: [sentences[0]]) { pieces, index in
                if mask & (1 << (index - 1)) != 0 {
                    pieces.append(sentences[index])
                } else {
                    pieces[pieces.count - 1] += " " + sentences[index]
                }
            }
        }
        let layouts = Set(cuts.map { joined($0, destination) })
        #expect(layouts.count == 1, "\(layouts)")
    }

    @Test("keeps the prose a list is introduced with, above the items")
    func leadInStaysProse() {
        let text = joined(
            ["There are two things to do.", "First, fix the build.", "Second, review the PR."], .document)
        #expect(text == "There are two things to do.\n- Fix the build\n- Review the PR")
    }

    @Test("keeps a bullet line break that begins a paused piece")
    func bulletBreakAtPieceHead() {
        let whole = PieceJoiner.join(
            [piece("Agenda"), piece("\n- budget"), piece("\n- hiring"), piece("\n- roadmap")],
            under: .standard(for: .document))

        #expect(whole.cleaned.text == "Agenda.\n- Budget\n- Hiring\n- Roadmap")
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

    @Test("keeps ordinal subjects and decimal points in prose")
    func ordinalAndDecimalSubjectsAreProse() {
        #expect(
            joined(["First place went to Sam.", "Second place went to Priya."], .document)
                == "First place went to Sam.\n\nSecond place went to Priya.")
        #expect(
            joined(["I came first. Second place is fine."], .document)
                == "I came first. Second place is fine.")
        #expect(
            joined(["I came first. Third time is fine."], .document)
                == "I came first. Third time is fine.")
        #expect(
            joined(["Point one seconds of lag is fine.", "Point two seconds is not."], .document)
                == "Point one seconds of lag is fine. Point two seconds is not.")
    }

    /// "One person came" counts the people; a bare cardinal announces an item only where the speaker set it off, and an ordinal never counts.
    @Test("a bare cardinal counting what follows it is prose, however the pieces line up")
    func anAmountIsNotAnItem() {
        #expect(
            joined(["One person came to the review.", "Two people left before the end."], .document)
                == "One person came to the review. Two people left before the end.")
        #expect(
            joined(["One hundred people came.", "Two hundred left."], .document)
                == "One hundred people came. Two hundred left.")
        #expect(
            joined(["One bug is still open.", "Two tests are still red."], .document)
                == "One bug is still open. Two tests are still red.")
    }

    @Test("continues an ordered list when a later ordinal has no spoken mark")
    func unmarkedLaterOrdinalContinuesList() {
        #expect(
            joined(["First, buy milk.", "second call mom."], .document)
                == "- Buy milk\n- Call mom")
    }

    @Test("an announcing word says an item as plainly as the mark does")
    func announcedItemNeedsNoMark() {
        #expect(
            joined(["Number one fix the build.", "Number two review the PR."], .document)
                == "- Fix the build\n- Review the PR")
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
    @Test("turns spoken layout commands at a piece boundary into layout")
    func layoutCommandsAtPieceBoundary() {
        #expect(
            joined(["Guide.", "New paragraph the next review is Friday."], .email)
                == "Guide.\n\nThe next review is Friday.")
        #expect(
            joined(["Guide.", "Bullet point who owns the icon refresh"], .document)
                == "Guide.\n- Who owns the icon refresh")
        #expect(
            joined(["Guide.", "Bullet point, do we need support team?"], .document)
                == "Guide.\n- Do we need support team?")
    }

    @Test("recognizes punctuation between the words of a layout command at a piece boundary")
    func punctuatedLayoutCommandsAtPieceBoundary() {
        #expect(
            joined(["Guide.", "New. Paragraph open questions."], .email)
                == "Guide.\n\nOpen questions.")
        #expect(
            joined(["Guide.", "New, line check the build."], .email)
                == "Guide.\nCheck the build.")
    }

    @Test("breaks a line in a place that runs the text only where the speaker asked for one")
    func executingPlaceGetsOnlySpokenLines() {
        let topics = ["List the files.", "Then we can talk about lunch plans tomorrow."]
        for destination in Destination.allCases {
            let consequence = DestinationFormatter.standard(for: destination).consequence
            guard consequence == .executes else { continue }
            let unasked = joined(topics, destination)
            #expect(!unasked.contains("\n"), "\(destination)")
            #expect(joined(["ls new line", "pwd"], destination) == "ls\npwd", "\(destination)")
        }
    }

    @Test("does not capitalize the next piece when a layout command ends its piece")
    func layoutCommandWithoutBodyInItsPiece() {
        #expect(
            joined(["Guide.", "New paragraph", "open questions."], .email)
                == "Guide.\n\nopen questions.")
        #expect(
            joined(["First item new line", "second item"], .document)
                == "First item\nsecond item.")
    }

    @Test("keeps a named new line at the end of a piece as words")
    func mentionedLineCommandAtPieceEnd() {
        #expect(
            joined(["Please add a new line.", "Of products to the catalogue."], .document)
                == "Please add a new line of products to the catalogue.")
        #expect(
            joined(["We launched a new line.", "Of shoes last spring."], .document)
                == "We launched a new line of shoes last spring.")
        #expect(
            joined(["The product line.", "Is growing fast."], .document)
                == "The product line is growing fast.")
    }

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

    @Test("keeps a seam restatement when self-corrections are switched off")
    func selfCorrectionOffKeepsBothPieces() {
        let pieces = [
            piece("We shipped the build on Monday."), piece("Actually shipped the build on Tuesday."),
        ]
        let steps = CleaningSteps.default.setting(.selfCorrection, isOn: false)

        #expect(
            PieceJoiner.join(pieces, under: .standard(for: .document)).cleaned.text
                == "We shipped the build on Tuesday.")

        let whole = PieceJoiner.join(
            pieces, under: .standard(for: .document), steps: steps)

        #expect(
            whole.cleaned.text == "We shipped the build on Monday. Actually shipped the build on Tuesday.")
    }

    @Test("matches two numbers across the cut the way the pass does inside one piece")
    func numbersAcrossTheCut() {
        #expect(joined(["Coffee at 2.", "Actually 3."], .document) == "Coffee at 3.")
    }

    @Test("drops a replaced phrase when its correction trigger ends the previous piece")
    func triggerAtEndOfPreviousPiece() {
        #expect(
            joined(["Let's move it to Tuesday no wait", "Wednesday afternoon"], .document)
                == "Let's move it to Wednesday afternoon.")
        #expect(
            joined(["Let's move it to Tuesday sorry", "Wednesday afternoon"], .document)
                == "Let's move it to Wednesday afternoon.")
        #expect(
            joined(["Let's move it to Tuesday I mean", "Wednesday afternoon"], .document)
                == "Let's move it to Wednesday afternoon.")
    }

    @Test("keeps a trailing apology when the next piece does not restate the phrase")
    func trailingSorryIsAnApology() {
        #expect(
            joined(["I am sorry", "Thank you for waiting"], .document)
                == "I am sorry. Thank you for waiting")
    }

    @Test("keeps both halves when the piece after the trigger says something else")
    func unmatchedTriggerKeepsEverything() {
        #expect(
            joined(["The build passed.", "Actually I should check the tests."], .document)
                == "The build passed. Actually I should check the tests.")
    }

    /// Only a trigger phrase marks a correction; a phrase said twice over is a list far more often. See `Docs/cleanup.md`.
    @Test("keeps both pieces when the second repeats a phrase with no trigger at all")
    func untriggeredRepeatKeepsEverything() {
        #expect(
            joined(["Let's meet on tuesday.", "On wednesday afternoon."], .document)
                == "Let's meet on tuesday. On wednesday afternoon.")
        #expect(
            joined(["I like tea.", "I like coffee, both are fine."], .document)
                == "I like tea. I like coffee, both are fine.")
    }

    /// The seam drops the previous piece's stop before matching, so a trigger-headed list reaches across a sentence the pass would not.
    @Test("keeps both pieces when the trigger heads a list rather than a correction")
    func triggerHeadedListAcrossTheCut() {
        #expect(
            joined(["I said no to the offer.", "No to the meeting."], .document)
                == "I said no to the offer. No to the meeting.")
        #expect(
            joined(["Say sorry to John.", "Sorry to Marcy too."], .document)
                == "Say sorry to John. Sorry to Marcy too.")
    }

    /// The seam has no sentence to stop the match, so the pair rule is what keeps the first answer's item whole.
    @Test("keeps both pieces when the trigger answers the head the piece before used")
    func triggerAnsweringAnotherHeadAcrossTheCut() {
        #expect(
            joined(["I said yes to the offer.", "No to the meeting."], .document)
                == "I said yes to the offer. No to the meeting.")
        #expect(
            joined(["Say thanks to John.", "Sorry to Marcy too."], .document)
                == "Say thanks to John. Sorry to Marcy too.")
    }

    @Test("never opens a paragraph on a piece whose opening it swallowed")
    func aRestatementIsNeverAParagraph() {
        #expect(
            joined(["We ship on the third.", "No, sorry, on the fourth."], .document)
                == "We ship on the fourth.")
    }

    /// A middle piece that is only a restatement word should not crash the joiner when the next piece opens with a number.
    @Test("does not crash when the middle piece is only a restatement word before a number")
    func restatementWordAsOnlyMiddlePiece() {
        let pieces = [
            piece("Lets meet at two."),
            piece("actually"),
            piece("three."),
        ]
        let whole = PieceJoiner.join(pieces, under: .standard(for: .document))
        #expect(whole.cleaned.text == "Lets meet at three.")
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

    /// A reading the tidier took in any piece is a use of its entry, so joining must not drop the pieces after the first.
    @Test("carries the entry behind every reading each piece's tidier took")
    func entriesTakenSurviveTheJoin() {
        let first = UUID()
        let second = UUID()
        let whole = PieceJoiner.join(
            [
                piece("The crash is in PaymentSheet.", entriesTaken: [first]),
                piece("Nothing taken here."),
                piece("Ask Kestrel.", entriesTaken: [second]),
            ], under: .standard(for: .document))

        #expect(whole.cleaned.entriesTaken == [first, second])
    }

    @Test("moves each correction's words past the pieces before it")
    func correctionsShift() {
        let entry = UUID()
        let correction = DictationCorrection(
            heard: "cubernetes", wrote: "Kubernetes", wordRange: 1..<2, entryID: entry,
            reason: .unknown("dictionary"), heardConfidence: 0.3)
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
            heard: "peeair", wrote: "PR", wordRange: 3..<4, entryID: entry, reason: .unknown("dictionary"),
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

@Suite("A seam ends a sentence the way the place ends one; the final stop is left to the message")
struct PieceJoinerSeamTests {
    /// Cut at its sentence ends, a chat message keeps a stop at every seam, as it would in one breath.
    @Test("stops every seam of a chat message and leaves its end to the message stage")
    func stopsTheSeamsOfAChatMessage() {
        let pieces = ["I left the office", "The traffic is bad", "I will be late"]

        let whole = PieceJoiner.join(pieces.map { piece($0) }, under: .standard(for: .messaging))

        #expect(whole.cleaned.text == "I left the office. The traffic is bad. I will be late")
    }

    @Test(
        "attaches a standalone spoken trailing mark to the previous piece",
        arguments: [
            ("We shipped it", "comma", "We shipped it,"),
            ("We shipped it", "full stop", "We shipped it."),
            ("Did we ship it", "question mark", "Did we ship it?"),
        ])
    func standaloneTrailingMarkAttachesToPrevious(first: String, mark: String, expected: String) {
        let whole = PieceJoiner.join(
            [piece(first), piece(mark)], under: .standard(for: .messaging))

        #expect(whole.cleaned.text == expected)
    }

    @Test("attaches adjacent standalone trailing marks in spoken order")
    func adjacentTrailingMarksAttachInOrder() {
        let whole = PieceJoiner.join(
            [piece("We shipped it"), piece("comma"), piece("full stop")],
            under: .standard(for: .messaging))

        #expect(whole.cleaned.text == "We shipped it.")
    }

    @Test("attaches a standalone opening quote to the following piece")
    func standaloneOpeningQuoteAttachesToFollowing() {
        let whole = PieceJoiner.join(
            [piece("open quote"), piece("hello there")], under: .standard(for: .messaging))

        #expect(whole.cleaned.text == "\"hello there\"")
    }

    @Test("does not carry a mark mention across a sentence boundary")
    func markMentionStopsAtSentenceBoundary() {
        let whole = PieceJoiner.join(
            [piece("we shipped it."), piece("the word"), piece("full stop")],
            under: .standard(for: .messaging))

        #expect(whole.cleaned.text == "We shipped it. The word full stop")
    }

    @Test("keeps a spoken mark name when it is mentioned across a piece boundary")
    func mentionGuardKeepsSpokenMarkName() {
        let whole = PieceJoiner.join(
            [piece("the word"), piece("full stop")], under: .standard(for: .messaging))

        #expect(whole.cleaned.text == "the word full stop")
    }

    @Test(
        "keeps a spoken mark name after any determiner across a piece boundary",
        arguments: ["the", "which", "whose", "both", "all", "his", "her", "its", "some", "any"])
    func keepsSpokenMarkNameAfterDeterminer(determiner: String) {
        let whole = PieceJoiner.join(
            [piece("tell me \(determiner)"), piece("comma")], under: .standard(for: .messaging))

        #expect(whole.cleaned.text.hasSuffix(" comma") && !whole.cleaned.text.contains("\(determiner),"))
    }

    @Test("keeps a question mark at a seam rather than adding a stop after it")
    func keepsAQuestionMarkAtASeam() {
        let whole = PieceJoiner.join(
            [piece("Can you bring the charger?"), piece("I am running late")],
            under: .standard(for: .messaging))

        #expect(whole.cleaned.text == "Can you bring the charger? I am running late")
    }

    @Test(
        "stops the seams of every place whose policy stops sentences",
        arguments: [Destination.plain, .document, .email, .messaging])
    func stopsSeamsWherePlacesStop(destination: Destination) {
        let whole = PieceJoiner.join(
            [piece("I left the office"), piece("I will be late")], under: .standard(for: destination))

        #expect(whole.cleaned.text == "I left the office. I will be late")
    }

    @Test(
        "takes a stop off every seam where the place never has one",
        arguments: [Destination.codeEditor, .spreadsheet])
    func strippedSeamsWherePlacesNeverStop(destination: Destination) {
        let whole = PieceJoiner.join(
            [piece("git status."), piece("git diff.")], under: .standard(for: destination))

        #expect(whole.cleaned.text == "git status git diff.")
    }

    @Test("leaves a seam alone where a list item ends the piece or the code keeps its lines")
    func leavesListsAndCodeLinesAlone() {
        let item = PieceJoiner.seamed(["\n- Milk", "then eggs"], under: .standard(for: .document))
        let code = PieceJoiner.seamed(["let a = 1\nlet b = 2", "done"], under: .standard(for: .sqlEditor))

        #expect(item == ["\n- Milk", "then eggs"])
        #expect(code == ["let a = 1\nlet b = 2", "done"])
    }

    /// A pause is not a sentence end, and the live path's words are supposed to match the one-shot result.
    @Test("adds no stop where the next piece opens on a phrase that continues the sentence")
    func mdSentenceSeamTakesNoStop() {
        let whole = PieceJoiner.join(
            [piece("We moved the review"), piece("To Thursday because the room was taken")],
            under: .standard(for: .document))

        #expect(whole.cleaned.text == "We moved the review to Thursday because the room was taken")
    }

    @Test("lowers a recognizer sentence capital across a run-on seam")
    func lowersCapitalAtRunOnSeam() {
        let whole = PieceJoiner.join(
            [piece("We moved the review to"), piece("The next slot works")],
            under: .standard(for: .document))

        #expect(whole.cleaned.text == "We moved the review to the next slot works")
    }

    @Test(
        "preserves recognizer capitalization for names at run-on seams",
        arguments: [
            ("Thanks to.", "Marcus for the help.", "Thanks to Marcus for the help."),
            ("He works for.", "Microsoft in Seattle.", "He works for Microsoft in Seattle."),
            ("Send it to.", "Sam and Priya.", "Send it to Sam and Priya."),
            ("The email came from.", "Alice.", "The email came from Alice."),
            ("The report is for.", "Acme Corp.", "The report is for Acme Corp."),
            ("I spoke to.", "Maria about it yesterday.", "I spoke to Maria about it yesterday."),
            ("She works at.", "Google.", "She works at Google."),
            ("I will see you in.", "Boston next week.", "I will see you in Boston next week."),
        ])
    func preservesNameCapitalAtRunOnSeam(first: String, next: String, expected: String) {
        let whole = PieceJoiner.join(
            [piece(first), piece(next)], under: .standard(for: .document))

        #expect(whole.cleaned.text == expected)
    }

    @Test("judges a seam against the next piece with words when a piece between was tidied to nothing")
    func judgesSeamPastAnEmptyPiece() {
        let whole = PieceJoiner.join(
            [piece("We moved the review."), piece("", heard: "um"), piece("To the Thursday slot.")],
            under: .standard(for: .document))

        #expect(whole.cleaned.text == "We moved the review to the Thursday slot.")
    }

    @Test("preserves a name whether or not the recognizer inserted a seam stop")
    func preservesNameWithAndWithoutRecognizerStop() {
        let withStop = PieceJoiner.seamed(
            ["Thanks to.", "Marcus for the help."], under: .standard(for: .document))
        let withoutStop = PieceJoiner.seamed(
            ["Thanks to", "Marcus for the help."], under: .standard(for: .document))

        #expect(withStop == ["Thanks to", "Marcus for the help."])
        #expect(withoutStop == ["Thanks to", "Marcus for the help."])
    }

    @Test("keeps a name capitalized when a sentence is cut at every word boundary")
    func preservesNameAcrossEveryWordBoundary() {
        let words = "I spoke to Marcus about it yesterday.".split(separator: " ").map(String.init)

        for boundary in 1..<words.count {
            let before = words[..<boundary].joined(separator: " ")
            let after = words[boundary...].joined(separator: " ")
            let withoutStop = PieceJoiner.join(
                [piece(before), piece(after)], under: .standard(for: .document)
            ).cleaned.text
            let withStop = PieceJoiner.join(
                [piece(before + "."), piece(after)], under: .standard(for: .document)
            ).cleaned.text

            #expect(withoutStop.contains("Marcus"))
            #expect(withStop.contains("Marcus"))
        }
    }

    @Test("keeps protected first word casing across a run-on seam")
    func keepsProtectedCaseAtRunOnSeam() {
        let seamed = PieceJoiner.seamed(
            ["We moved the review to", "I called John"], under: .standard(for: .document))

        #expect(seamed == ["We moved the review to", "I called John"])
    }

    /// An infinitive opens a sentence as readily as it continues one, so it is no evidence either way.
    @Test("still stops a seam where the next piece opens on an infinitive")
    func infinitiveAtASeamStillStops() {
        let seamed = PieceJoiner.seamed(
            ["I finished the draft", "to be honest it took all day"],
            under: .standard(for: .document))

        #expect(seamed.first == "I finished the draft.")
    }

    @Test("keeps a sentence stop between adjacent digit groups")
    func digitGroupsAfterSentenceStopStaySeparate() {
        let whole = PieceJoiner.join(
            [piece("It costs 20."), piece("30 people came.")],
            under: .standard(for: .messaging))

        #expect(whole.cleaned.text == "It costs 20. 30 people came.")
    }

    @Test("joins number groups across a stop only when the heard piece ends on a scale word")
    func scaleWordSupportsStoppedGroupContinuation() {
        let seamed = PieceJoiner.seamed(
            ["It costs 200.", "30 people came."], heard: ["It costs two hundred", "thirty people came"],
            under: .standard(for: .document))

        #expect(seamed.first == "It costs 200")
    }

    @Test("joins digit groups across a cut without a sentence stop")
    func digitGroupsWithoutSentenceStopRunOn() {
        let seamed = PieceJoiner.seamed(
            ["Call me at 555", "123"], under: .standard(for: .document))

        #expect(seamed.first == "Call me at 555")
    }

    /// A fronted phrase opens a sentence, and only a preposition a speaker never fronts counts as evidence.
    @Test("still stops a seam where the next piece opens on a fronted phrase")
    func frontedPhraseAtASeamStillStops() {
        let seamed = PieceJoiner.seamed(
            ["the room was taken", "in the morning we moved it"], under: .standard(for: .document))

        #expect(seamed.first == "the room was taken.")
    }

    @Test(
        "joins a dependent clause opening to its main clause across a seam",
        arguments: ["When", "If", "Because", "Although"])
    func dependentClauseAtASeamRunsOn(subordinator: String) {
        let seamed = PieceJoiner.seamed(
            [
                "\(subordinator) the light was finally automated.",
                "The logbook was given to the town museum.",
            ],
            under: .standard(for: .document))

        #expect(seamed.first == "\(subordinator) the light was finally automated")
    }

    @Test("still stops after a statement that starts with a wh-word")
    func whWordStatementAtASeamStillStops() {
        let seamed = PieceJoiner.seamed(
            ["What it showed was surprising.", "The board approved the report."],
            under: .standard(for: .document))

        #expect(seamed.first == "What it showed was surprising.")
    }

    /// A hard cut falls where the speaker never paused, which is most often inside a phrase.
    @Test(
        "adds no stop where the piece ends on a word no sentence ends on",
        arguments: ["we moved the review to", "the room was taken and", "I spoke to the"])
    func unfinishedPieceTakesNoStop(text: String) {
        let seamed = PieceJoiner.seamed([text, "Thursday works"], under: .standard(for: .document))

        #expect(seamed.first == text)
    }

    @Test(
        "joins the reported phrase completions across a seam",
        arguments: [
            ("The meeting is on", "Tuesday at 10 in the morning."),
            ("I left my keys in", "the blue car"),
            ("Remind me to pick up", "the dry cleaning tomorrow."),
            ("The server went down around", "Midnight last night."),
            ("She asked whether we could finish", "the draft by Wednesday."),
            ("The quarterly numbers look", "better than we expected."),
            ("The workshop covers", "testing and deployment."),
        ])
    func reportedPhraseCompletionTakesNoStop(first: String, next: String) {
        let seamed = PieceJoiner.seamed([first, next], under: .standard(for: .document))

        #expect(seamed.first == first)
    }

    @Test("still stops a sentence-final particle before a new sentence")
    func sentenceFinalParticleStillStops() {
        let seamed = PieceJoiner.seamed(["Turn it on", "again later"], under: .standard(for: .document))

        #expect(seamed.first == "Turn it on.")
    }

    /// The seam of two whole utterances is still a sentence end, which is what #183 asked for.
    @Test("still stops a seam with no evidence either way")
    func seamWithNoEvidenceStillStops() {
        let seamed = PieceJoiner.seamed(["on my way", "be there soon"], under: .standard(for: .messaging))

        #expect(seamed.first == "on my way.")
    }

    @Test("joins a split currency amount across pieces")
    func joinsSplitCurrencyAmount() {
        let whole = PieceJoiner.join(
            [piece("The total came to"), piece("400", heard: "four hundred"), piece("and $20")],
            under: .standard(for: .document))

        #expect(whole.cleaned.text == "The total came to $420")
    }

    @Test(
        "never adds an integer that was not a spoken scale to the next amount",
        arguments: [
            ("we owe him 12", "we owe him twelve", "and $5"), ("seats 12", "seats twelve", "and $5"),
            ("we owe him 3", "we owe him three", "and $5"), ("page 7", "page seven", "and $5"),
            ("table 20", "table twenty", "and $5"), ("room 400", "room four hundred", "and $400"),
            ("gate 1,000", "gate one thousand", "and $5,000"), ("bus 100", "bus one hundred", "and $500"),
        ])
    func keepsUnrelatedIntegerApartFromAmount(cleaned: String, heard: String, amount: String) {
        let seamed = PieceJoiner.seamed(
            [cleaned, amount], heard: [heard, amount], under: .standard(for: .document))

        #expect(seamed.last == amount)
    }

    @Test("joins a spoken scale with the smaller amount after it at every scale")
    func joinsEveryScaleWithSmallerAmount() {
        let cases: [(String, String, String, String)] = [
            ("400", "four hundred", "and $20", "$420"),
            ("2,000", "two thousand", "and $50", "$2050"),
            ("3,000,000", "three million", "and $5", "$3,000,005"),
        ]
        for (number, heard, amount, sum) in cases {
            let seamed = PieceJoiner.seamed(
                ["It cost " + number, amount], heard: ["it cost " + heard, amount],
                under: .standard(for: .document))
            #expect(seamed.first == "It cost " + sum)
        }
    }

    @Test("keeps separate figures apart when the second number has no currency")
    func keepsSeparateFiguresApart() {
        let whole = PieceJoiner.join(
            [piece("Room 400"), piece("And 20 chairs")], under: .standard(for: .document))

        #expect(whole.cleaned.text == "Room 400. And 20 chairs")
    }

    /// A single piece is already the whole message, so the joiner has no seam to end.
    @Test("leaves a one-piece dictation to the message stage")
    func leavesOnePieceAlone() {
        let whole = PieceJoiner.join([piece("On my way")], under: .standard(for: .messaging))

        #expect(whole.cleaned.text == "On my way")
    }

    /// Invented numbers and codes said in groups; the 555 0100 to 0199 range is reserved for fiction.
    static let groupsAcrossPause = [
        "555 0100", "555 0142", "Call 555 0187", "415 555 0123", "Dial 0800 555 0150",
        "Order 7731 4402", "The code is QX 4417", "AB 123", "Card 1234 5678 9012 3456",
        "Ref ZK 2290 18", "PIN 0000 1111", "Room KT 404",
    ]

    /// Sentences that end on a number before one that opens on a number, which the group row joins.
    static let sentencesAcrossNumbers = [
        ("It costs 12.", "13 people came."), ("We sold 40.", "25 came back."),
        ("The score was 3.", "2 goals were late."), ("I counted 7.", "8 were missing."),
        ("Page 10.", "11 is blank."), ("She is 30.", "40 is next year."),
        ("We need 6.", "5 are here."), ("Gate 9.", "10 minutes to board."),
    ]

    @Test(
        "joins the groups of one spoken number or code at every cut, with or without the recogniser's stop",
        arguments: [Destination.document, .messaging, .plain, .email])
    func groupsAcrossPauseJoin(destination: Destination) {
        for text in Self.groupsAcrossPause {
            let words = text.split(separator: " ").map(String.init)
            for cut in 1..<words.count where words[cut - 1].allSatisfy({ $0.isNumber || $0.isUppercase }) {
                for stop in ["", "."] {
                    let pieces = [
                        words[..<cut].joined(separator: " ") + stop, words[cut...].joined(separator: " "),
                    ]
                    let whole = PieceJoiner.join(pieces.map { piece($0) }, under: .standard(for: destination))

                    #expect(whole.cleaned.text == text, "\(pieces) in \(destination)")
                }
            }
        }
    }

    @Test("keeps the stop between two groups when the recogniser heard a question or an exclamation")
    func groupRowAbstainsOnQuestionOrExclamation() {
        for mark in ["?", "!"] {
            let seamed = PieceJoiner.seamed(
                ["It costs 12" + mark, "13 people came."], under: .standard(for: .document))

            #expect(seamed.first == "It costs 12" + mark)
        }
    }

    /// The group row's measured cost: these were ended before it and are joined by it.
    @Test("joins a sentence that ends on a number to one that opens on a number")
    func groupRowCost() {
        let kept = Self.sentencesAcrossNumbers.filter { first, next in
            PieceJoiner.seamed([first, next], under: .standard(for: .document)).first == first
        }

        #expect(kept.isEmpty)
    }
}

@Suite("Seam stops around a snippet expansion")
struct SeamSnippetInputTests {
    private let input = SeamSnippetInput(
        text: "W1 X. W2 X. W3 X", removableStops: [4, 10], source: "W1 X. W2 X. W3 X")

    @Test("an expansion that changed nothing leaves the seam stops where they were")
    func unchangedExpansionKeepsStops() {
        let unchanged = ExpandedTranscript.unchanged(input.removingSeamStops())
        #expect(input.restoringUnconsumedStops(in: unchanged).text == "W1 X. W2 X. W3 X")
    }

    @Test("a stop whose seam is still a gap after the expansion comes back in place")
    func gapKeepsItsStop() {
        let expanded = ExpandedTranscript(text: "W1 X W2 X W3 Y", snippets: [])
        #expect(input.restoringUnconsumedStops(in: expanded).text == "W1 X. W2 X. W3 Y")
    }

    @Test("a snippet's caret moves with the stops restored before it")
    func caretFollowsRestoredStops() {
        let expanded = ExpandedTranscript(text: "W1 X W2 X W3 Y", snippets: [], caret: 6)
        let restored = input.restoringUnconsumedStops(in: expanded)
        #expect(restored.text == "W1 X. W2 X. W3 Y")
        #expect(restored.caret == "W1 X. W".utf16.count)
    }
}
