// Runs each cleaning stage again on its own output across the corpus, catching a stage that moves its words.
import Testing
import UttrflowCore
import UttrflowEval

@testable import UttrflowAI

/// Each stage a dictation passes through after recognition, given its own output back, writes it unchanged.
@Suite("Each cleaning stage gives its own output back unchanged")
struct StageIdempotenceTests {
    /// The stages the pipeline runs one after another on a dictation's words.
    enum Stage: String, CaseIterable, Sendable {
        /// The rules tidier over one piece, as the pipeline asks it at piece scope.
        case piece
        /// The message's own passes over the joined pieces.
        case message
        /// The first-word pass the write runs when the caret moved since the words were cased.
        case finalWrite
        /// The three stages in order, run again on their own result.
        case chain
    }

    /// Cases a stage moves on a second run, as "stage/case id" with the issue that fixes each; only shrinks.
    static let knownFaults: [String: Int] = [
        // Justified: #8274 and #8275 cases are the piece stage reading its own output as recogniser text.
        "chain/code-editor-line-break-preserved": 8274,
        "chain/code-editor-spoken-case-stops-at-comma": 8275,
        "chain/correction-after-new-paragraph": 8274,
        "chain/dev-bug-report-steps": 8274,
        "chain/dev-changelog-entry": 8274,
        "chain/dev-commit-message": 8274,
        "chain/dev-decision-record": 8274,
        "chain/dev-migration-plan": 8274,
        "chain/dev-pr-description-list": 8274,
        "chain/dev-release-checklist": 8274,
        "chain/dictionary-lower-case-after-line-document-4290": 8274,
        "chain/document-list-only-when-spoken": 8274,
        "chain/document-numbered-items-after-a-sentence": 8274,
        "chain/document-numbered-list-after-a-colon-in-a-later-paragraph": 8274,
        "chain/document-spoken-colon-before-a-numbered-list": 8274,
        "chain/document-spoken-colon-before-a-plural-noun": 8274,
        "chain/email-two-paragraphs": 8274,
        "chain/fmt-list-bullet-command": 8274,
        "chain/fmt-list-sub-bullet": 8274,
        "chain/fmt-list-sub-bullet-under-numbered": 8274,
        "chain/fmt-list-sub-point-and-sub-bullet-point": 8274,
        "chain/fmt-paragraph-new-line": 8274,
        "chain/fmt-paragraph-new-paragraph": 8274,
        "chain/fmt-paragraph-two-breaks": 8274,
        "chain/full-stop-new-paragraph": 8274,
        "chain/hinglish-false-start": 8277,
        "chain/hostile-line-doubtful-words": 8274,
        "chain/hostile-line-nearby-text": 8274,
        "chain/hostile-line-spoken": 8274,
        "chain/hostile-line-typed-into-editor": 8274,
        "chain/hostile-line-typed-into-sql": 8274,
        "chain/hostile-line-typed-into-terminal": 8274,
        "chain/markup-css-align": 8275,
        "chain/markup-css-before": 8275,
        "chain/markup-css-colour": 8275,
        "chain/markup-css-declare-and-close": 8275,
        "chain/markup-css-display": 8275,
        "chain/markup-css-group": 8275,
        "chain/markup-css-hex": 8275,
        "chain/markup-css-hyphen-property": 8275,
        "chain/markup-css-two-declarations": 8275,
        "chain/markup-css-z-index": 8275,
        "chain/markup-css-zero": 8275,
        "chain/new-paragraph": 8274,
        "chain/newline-written-as-one-word": 8274,
        "chain/newparagraph-written-as-one-word": 8274,
        "chain/no-after-bullet-point-kept": 8274,
        "chain/no-after-new-line-kept": 8274,
        "chain/no-after-new-paragraph-kept": 8274,
        "chain/numbered-items-a-plan": 8274,
        "chain/numbered-items-an-agenda": 8274,
        "chain/numbered-items-as-digits": 8274,
        "chain/numbered-items-before-lunch": 8274,
        "chain/numbered-items-continuing": 8274,
        "chain/numbered-items-for-a-trip": 8274,
        "chain/numbered-items-priorities": 8274,
        "chain/numbered-items-reminders": 8274,
        "chain/numbered-items-repeated-label": 8274,
        "chain/numbered-items-steps": 8274,
        "chain/numbered-items-three-of-them": 8274,
        "chain/numbered-list-opens-the-dictation": 8274,
        "chain/one-spoken-new-line-stays-one-line": 8274,
        "chain/pause-comma-before-spoken-line-break-dropped": 8274,
        "chain/period-after-new-line": 8274,
        "chain/probe-changelog-bullets": 8274,
        "chain/probe-contract-clauses": 8274,
        "chain/probe-cover-letter": 8274,
        "chain/probe-docker-build-no-cache": 8275,
        "chain/probe-docker-run-flags": 8275,
        "chain/probe-laugh-then-question": 8274,
        "chain/probe-meeting-notes": 8274,
        "chain/probe-quoted-citation": 8274,
        "chain/probe-repro-steps": 8274,
        "chain/probe-retry-bullets": 8274,
        "chain/probe-short-verse": 8274,
        "chain/probe-sql-join": 8274,
        "chain/probe-support-email": 8274,
        "chain/question-mark-new-line": 8274,
        "chain/question-mark-new-line-thanks": 8274,
        "chain/sentence-per-new-line": 8274,
        // Justified: the terminal drops the speaker's comma, the only evidence against joining "u plus x".
        "chain/shell-chmod-marked-subject-not-joined": 8277,
        "chain/source-python-arrow-float": 8275,
        "chain/source-python-arrow-fragment": 8275,
        "chain/source-python-arrow-list": 8275,
        "chain/source-python-arrow-self": 8275,
        "chain/source-python-compare-chain": 8275,
        "chain/source-python-double-equals": 8275,
        "chain/source-python-double-equals-string": 8275,
        "chain/source-python-greater-or-equal": 8275,
        "chain/source-python-greater-than": 8275,
        "chain/source-python-greater-than-zero": 8275,
        "chain/source-python-less-or-equal": 8275,
        "chain/source-python-less-than": 8275,
        "chain/source-python-logical-and-not-python": 8275,
        "chain/source-python-logical-or-not-python": 8275,
        "chain/source-python-not-equals": 8275,
        "chain/source-python-not-equals-default": 8275,
        "chain/source-python-not-equals-end": 8275,
        "chain/source-python-not-equals-zero": 8275,
        "chain/source-python-triple-equals-not-python": 8275,
        "chain/source-swift-arrow-return": 8275,
        "chain/sql-statement-alias": 8274,
        "chain/sql-statement-and": 8274,
        "chain/sql-statement-at-least": 8274,
        "chain/sql-statement-at-most": 8274,
        "chain/sql-statement-between": 8274,
        "chain/sql-statement-between-ratings": 8274,
        "chain/sql-statement-comma-list": 8274,
        "chain/sql-statement-delete": 8274,
        "chain/sql-statement-delete-less-than": 8274,
        "chain/sql-statement-distinct": 8274,
        "chain/sql-statement-dot": 8274,
        "chain/sql-statement-equals": 8274,
        "chain/sql-statement-everything": 8274,
        "chain/sql-statement-greater-or-equal": 8274,
        "chain/sql-statement-greater-than": 8274,
        "chain/sql-statement-group-by": 8274,
        "chain/sql-statement-having": 8274,
        "chain/sql-statement-in-numbers": 8274,
        "chain/sql-statement-in-words": 8274,
        "chain/sql-statement-inner-join": 8274,
        "chain/sql-statement-insert-values": 8275,
        "chain/sql-statement-is-not-null": 8274,
        "chain/sql-statement-is-null": 8274,
        "chain/sql-statement-join": 8274,
        "chain/sql-statement-left-join": 8274,
        "chain/sql-statement-less-or-equal": 8274,
        "chain/sql-statement-less-than": 8274,
        "chain/sql-statement-like": 8274,
        "chain/sql-statement-not": 8274,
        "chain/sql-statement-not-equals": 8274,
        "chain/sql-statement-null-and": 8274,
        "chain/sql-statement-or": 8274,
        "chain/sql-statement-order-asc-limit": 8274,
        "chain/sql-statement-order-by": 8274,
        "chain/sql-statement-order-by-desc": 8274,
        "chain/sql-statement-range": 8274,
        "chain/sql-statement-star": 8274,
        "chain/sql-statement-update": 8274,
        "chain/sql-statement-update-rating": 8274,
        "chain/sql-terminated-semicolon-said": 8274,
        "chain/terminal-spoken-new-line-stays-on-one-line": 8275,
        "chain/terminal-spoken-new-paragraph-stays-on-one-line": 8275,
        "piece/code-editor-line-break-preserved": 8274,
        "piece/code-editor-spoken-case-stops-at-comma": 8275,
        "piece/correction-after-new-paragraph": 8274,
        "piece/dev-bug-report-steps": 8274,
        "piece/dev-changelog-entry": 8274,
        "piece/dev-commit-message": 8274,
        "piece/dev-decision-record": 8274,
        "piece/dev-migration-plan": 8274,
        "piece/dev-pr-description-list": 8274,
        "piece/dev-release-checklist": 8274,
        "piece/dictionary-lower-case-after-line-document-4290": 8274,
        "piece/document-list-only-when-spoken": 8274,
        "piece/document-numbered-items-after-a-sentence": 8274,
        "piece/document-numbered-list-after-a-colon-in-a-later-paragraph": 8274,
        "piece/document-spoken-colon-before-a-numbered-list": 8274,
        "piece/document-spoken-colon-before-a-plural-noun": 8274,
        "piece/email-two-paragraphs": 8274,
        "piece/fmt-list-bullet-command": 8274,
        "piece/fmt-list-sub-bullet": 8274,
        "piece/fmt-list-sub-bullet-under-numbered": 8274,
        "piece/fmt-list-sub-point-and-sub-bullet-point": 8274,
        "piece/fmt-paragraph-new-line": 8274,
        "piece/fmt-paragraph-new-paragraph": 8274,
        "piece/fmt-paragraph-two-breaks": 8274,
        "piece/full-stop-new-paragraph": 8274,
        "piece/hinglish-false-start": 8277,
        "piece/hostile-line-doubtful-words": 8274,
        "piece/hostile-line-nearby-text": 8274,
        "piece/hostile-line-spoken": 8274,
        "piece/hostile-line-typed-into-editor": 8274,
        "piece/hostile-line-typed-into-sql": 8274,
        "piece/hostile-line-typed-into-terminal": 8274,
        "piece/markup-css-align": 8275,
        "piece/markup-css-before": 8275,
        "piece/markup-css-colour": 8275,
        "piece/markup-css-declare-and-close": 8275,
        "piece/markup-css-display": 8275,
        "piece/markup-css-group": 8275,
        "piece/markup-css-hex": 8275,
        "piece/markup-css-hyphen-property": 8275,
        "piece/markup-css-two-declarations": 8275,
        "piece/markup-css-z-index": 8275,
        "piece/markup-css-zero": 8275,
        "piece/new-paragraph": 8274,
        "piece/newline-written-as-one-word": 8274,
        "piece/newparagraph-written-as-one-word": 8274,
        "piece/no-after-bullet-point-kept": 8274,
        "piece/no-after-new-line-kept": 8274,
        "piece/no-after-new-paragraph-kept": 8274,
        "piece/numbered-items-a-plan": 8274,
        "piece/numbered-items-an-agenda": 8274,
        "piece/numbered-items-as-digits": 8274,
        "piece/numbered-items-before-lunch": 8274,
        "piece/numbered-items-continuing": 8274,
        "piece/numbered-items-for-a-trip": 8274,
        "piece/numbered-items-priorities": 8274,
        "piece/numbered-items-reminders": 8274,
        "piece/numbered-items-repeated-label": 8274,
        "piece/numbered-items-steps": 8274,
        "piece/numbered-items-three-of-them": 8274,
        "piece/numbered-list-opens-the-dictation": 8274,
        "piece/one-spoken-new-line-stays-one-line": 8274,
        "piece/pause-comma-before-spoken-line-break-dropped": 8274,
        "piece/period-after-new-line": 8274,
        "piece/probe-changelog-bullets": 8274,
        "piece/probe-clinical-note": 8277,
        "piece/probe-contract-clauses": 8274,
        "piece/probe-cover-letter": 8274,
        "piece/probe-docker-build-no-cache": 8275,
        "piece/probe-docker-run-flags": 8275,
        "piece/probe-laugh-then-question": 8274,
        "piece/probe-meeting-notes": 8274,
        "piece/probe-quoted-citation": 8274,
        "piece/probe-repro-steps": 8274,
        "piece/probe-retry-bullets": 8274,
        "piece/probe-short-verse": 8274,
        "piece/probe-sql-join": 8274,
        "piece/probe-support-email": 8274,
        "piece/question-mark-new-line": 8274,
        "piece/question-mark-new-line-thanks": 8274,
        "piece/sentence-per-new-line": 8274,
        // Justified: the terminal drops the speaker's comma, the only evidence against joining "u plus x".
        "piece/shell-chmod-marked-subject-not-joined": 8277,
        "piece/source-python-arrow-float": 8275,
        "piece/source-python-arrow-fragment": 8275,
        "piece/source-python-arrow-list": 8275,
        "piece/source-python-arrow-self": 8275,
        "piece/source-python-compare-chain": 8275,
        "piece/source-python-double-equals": 8275,
        "piece/source-python-double-equals-string": 8275,
        "piece/source-python-greater-or-equal": 8275,
        "piece/source-python-greater-than": 8275,
        "piece/source-python-greater-than-zero": 8275,
        "piece/source-python-less-or-equal": 8275,
        "piece/source-python-less-than": 8275,
        "piece/source-python-logical-and-not-python": 8275,
        "piece/source-python-logical-or-not-python": 8275,
        "piece/source-python-not-equals": 8275,
        "piece/source-python-not-equals-default": 8275,
        "piece/source-python-not-equals-end": 8275,
        "piece/source-python-not-equals-zero": 8275,
        "piece/source-python-triple-equals-not-python": 8275,
        "piece/source-swift-arrow-return": 8275,
        "piece/sql-statement-alias": 8274,
        "piece/sql-statement-and": 8274,
        "piece/sql-statement-at-least": 8274,
        "piece/sql-statement-at-most": 8274,
        "piece/sql-statement-between": 8274,
        "piece/sql-statement-between-ratings": 8274,
        "piece/sql-statement-comma-list": 8274,
        "piece/sql-statement-delete": 8274,
        "piece/sql-statement-delete-less-than": 8274,
        "piece/sql-statement-distinct": 8274,
        "piece/sql-statement-dot": 8274,
        "piece/sql-statement-equals": 8274,
        "piece/sql-statement-everything": 8274,
        "piece/sql-statement-greater-or-equal": 8274,
        "piece/sql-statement-greater-than": 8274,
        "piece/sql-statement-group-by": 8274,
        "piece/sql-statement-having": 8274,
        "piece/sql-statement-in-numbers": 8274,
        "piece/sql-statement-in-words": 8274,
        "piece/sql-statement-inner-join": 8274,
        "piece/sql-statement-insert-values": 8275,
        "piece/sql-statement-is-not-null": 8274,
        "piece/sql-statement-is-null": 8274,
        "piece/sql-statement-join": 8274,
        "piece/sql-statement-left-join": 8274,
        "piece/sql-statement-less-or-equal": 8274,
        "piece/sql-statement-less-than": 8274,
        "piece/sql-statement-like": 8274,
        "piece/sql-statement-not": 8274,
        "piece/sql-statement-not-equals": 8274,
        "piece/sql-statement-null-and": 8274,
        "piece/sql-statement-or": 8274,
        "piece/sql-statement-order-asc-limit": 8274,
        "piece/sql-statement-order-by": 8274,
        "piece/sql-statement-order-by-desc": 8274,
        "piece/sql-statement-range": 8274,
        "piece/sql-statement-star": 8274,
        "piece/sql-statement-update": 8274,
        "piece/sql-statement-update-rating": 8274,
        "piece/sql-terminated-semicolon-said": 8274,
        "piece/terminal-spoken-new-line-stays-on-one-line": 8275,
        "piece/terminal-spoken-new-paragraph-stays-on-one-line": 8275,
    ]

    static func piece(_ text: String, for testCase: EvaluationCase) async throws -> String {
        let request = testCase.transformationRequest()
        return try await RuleBasedTransformer().transform(
            TransformationRequest(
                transcription: Transcription(text: text), context: request.context,
                situation: request.situation, scope: .piece, vocabulary: request.vocabulary)
        ).text
    }

    static func message(_ text: String, for testCase: EvaluationCase) -> String {
        let situation = testCase.situation
        return CleaningPipeline.message(
            for: .standard(for: situation), situation: situation, heard: testCase.spoken,
            vocabulary: testCase.dictionary
        ).run(Draft(keepingLineBreaks: text)).text
    }

    static func finalWrite(_ text: String, for testCase: EvaluationCase) -> String {
        let context = testCase.context
        let formatter = DestinationFormatter.standard(for: testCase.situation)
        return FirstWordPass(
            policy: formatter.firstWord, state: context.insertionPoint.sentenceState,
            onScreen: [
                context.documentName, context.selectedText, context.precedingText, context.followingText,
            ]
            .compactMap { $0 },
            heard: testCase.spoken,
            capitaliseCalendarWords: formatter.firstWord == .fromInsertionPoint
                && formatter.destination != .codeEditor,
            vocabulary: testCase.dictionary, keepsCommandCase: formatter.keepsCommandCase
        ).apply(Draft(keepingLineBreaks: text)).text
    }

    static func chain(_ text: String, for testCase: EvaluationCase) async throws -> String {
        finalWrite(message(try await piece(text, for: testCase), for: testCase), for: testCase)
    }

    /// The text a stage writes, and what it writes when handed that text again.
    static func runs(
        _ stage: Stage, for testCase: EvaluationCase
    ) async throws -> (once: String, twice: String) {
        let pieceOutput = try await piece(testCase.spoken, for: testCase)
        let messageOutput = message(pieceOutput, for: testCase)
        switch stage {
        case .piece: return (pieceOutput, try await piece(pieceOutput, for: testCase))
        case .message: return (messageOutput, message(messageOutput, for: testCase))
        case .finalWrite:
            let written = finalWrite(messageOutput, for: testCase)
            return (written, finalWrite(written, for: testCase))
        case .chain:
            let written = finalWrite(messageOutput, for: testCase)
            return (written, try await chain(written, for: testCase))
        }
    }

    @Test(
        "A second run of each stage leaves every corpus case as the first run wrote it",
        arguments: Stage.allCases)
    func stageIsIdempotent(stage: Stage) async throws {
        var moved: [String: (once: String, twice: String)] = [:]
        for testCase in EvaluationCorpus.all {
            let (once, twice) = try await Self.runs(stage, for: testCase)
            if once != twice { moved["\(stage.rawValue)/\(testCase.id)"] = (once, twice) }
        }
        let known = Set(Self.knownFaults.keys.filter { $0.hasPrefix("\(stage.rawValue)/") })
        for (key, run) in moved.sorted(by: { $0.key < $1.key }) where !known.contains(key) {
            let became = String(reflecting: run.twice)
            Issue.record("\(key) moved on a second run: \(String(reflecting: run.once)) became \(became)")
        }
        for key in known.sorted() where moved[key] == nil {
            Issue.record(
                "\(key) is idempotent now; remove it from knownFaults (#\(Self.knownFaults[key] ?? 0))")
        }
    }
}
