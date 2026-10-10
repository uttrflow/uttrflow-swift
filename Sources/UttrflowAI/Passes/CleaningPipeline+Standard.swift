public import UttrflowCore

extension CleaningPipeline {
    /// Every pass in the shipped order, for plain text at a caret that says nothing.
    public static let standard = standard(for: .standard(for: .plain), situation: .unknown)

    /// The piece's passes and the spelled letters joined, so a model is handed "API" rather than "a p i".
    public static func beforeModel(
        for formatter: DestinationFormatter, situation: Situation, steps: CleaningSteps = .default,
        pauses: PauseLength = .usual
    ) -> CleaningPipeline {
        CleaningPipeline(
            passes: piece(
                numbers: formatter.numbers, digits: situation.digits(for: formatter),
                layout: formatter.layout,
                insertionPoint: situation.insertion, destination: formatter.destination,
                intent: situation.intent, steps: steps, pauses: pauses
            ).passes + initialisms(steps: steps))
    }

    /// Every pass the user has left on over a whole message, in the shipped order: the piece's, then the message's.
    public static func standard(
        for formatter: DestinationFormatter, situation: Situation, steps: CleaningSteps = .default,
        vocabulary: [String] = [], pauses: PauseLength = .usual
    ) -> CleaningPipeline {
        CleaningPipeline(
            passes: piece(
                numbers: formatter.numbers, digits: situation.digits(for: formatter),
                insertionPoint: situation.insertion,
                destination: formatter.destination, intent: situation.intent, steps: steps,
                pauses: pauses, screen: situation
            ).passes
                + message(for: formatter, situation: situation, steps: steps, vocabulary: vocabulary).passes)
    }

    /// The passes that are right on any piece of a message, which is why no casing or stop policy can reach them.
    /// `screen` is where the identifiers a doubted run may be bound to are read; the model path leaves it unknown.
    public static func piece(
        numbers: NumberPolicy, digits: DigitGrouping, layout: LayoutPolicy = [.paragraphs, .lists],
        insertionPoint: InsertionPoint = .unknown, destination: Destination = .plain,
        intent: WritingIntent = .unknown, steps: CleaningSteps = .default, pauses: PauseLength = .usual,
        screen: Situation = .unknown
    ) -> CleaningPipeline {
        let identifiers = ScreenVocabulary(screen)
        var cleanings: [any PieceCleaningPass] = [
            FillersPass(), RepeatedPhrasePass(), StammersPass(), SelfCorrectionPass(),
            // Spoken punctuation must mark a stop before LayoutWordsPass checks for a break after it.
            SpokenPunctuationPass(
                destination: destination, fieldRole: intent.fieldRole, region: intent.region),
            SpokenEmojiPass(destination: destination),
            LayoutWordsPass(layout: layout, insertionPoint: insertionPoint),
            NumberFormsPass(policy: numbers, digits: digits),
            ContractionsPass(), SpacingPass(),
            // Last, so a pause inside a number or a removed filler is read on the words left standing.
            PauseStopPass(destination: destination, pauses: pauses),
        ]
        // Only a screen showing an identifier adds the pass, so every other pipeline keeps its list of passes.
        if !identifiers.identifiers.isEmpty,
            let afterCorrection = cleanings.firstIndex(where: { $0.id == .selfCorrection })
        {
            cleanings.insert(ScreenIdentifierPass(vocabulary: identifiers), at: afterCorrection + 1)
        }
        let inCode = destination == .codeEditor && intent.region.isCode
        let notation = NotationEvidence.applicability(destination: destination, region: intent.region)
        if let layoutPosition = cleanings.firstIndex(where: { $0.id == .layoutWords }) {
            if NotationEvidence.mayActivate(notation, in: destination) {
                cleanings.insert(
                    CodeEditorCommandsPass(destination: destination, evidence: notation), at: layoutPosition)
            }
            // A code editor's comments take no casing: its rows are identifiers, which a comment is not.
            if destination != .codeEditor || inCode {
                cleanings.insert(SpokenCasingPass(destination: destination), at: layoutPosition)
            }
        }
        return CleaningPipeline(piece: cleanings.filter { steps.runs($0.id) })
    }

    /// The passes that finish a model's answer to a whole message: the caret's echo taken back, then the message's.
    public static func afterModel(
        for formatter: DestinationFormatter, situation: Situation, heard: String? = nil,
        spoken: String? = nil, steps: CleaningSteps = .default, vocabulary: [String] = []
    ) -> CleaningPipeline {
        CleaningPipeline(
            passes: afterModelPiece(
                digits: situation.digits(for: formatter), situation: situation, heard: heard, spoken: spoken
            ).passes
                + message(
                    for: formatter, situation: situation, heard: heard, steps: steps, vocabulary: vocabulary
                ).passes)
    }

    /// What finishes a model's answer to one piece before the final message-wide passes run.
    static func afterModelPiece(
        digits: DigitGrouping, situation: Situation, heard: String? = nil, spoken: String? = nil
    ) -> CleaningPipeline {
        CleaningPipeline(piece: [
            SpokenPunctuationPass(
                destination: situation.destination, fieldRole: situation.intent.fieldRole,
                region: situation.intent.region),
            CaretEchoPass(
                state: situation.insertion.sentenceState, precedingText: situation.insertion.precedingText,
                spokenText: heard),
            CaretCloserPass(precedingText: situation.insertion.precedingText, spokenText: spoken),
            DigitGroupingPass(digits: digits, spokenText: spoken),
        ])
    }

    /// The passes asked once of a whole message, spelled letters to the final stop; `heard` is what `.asSpoken` copies.
    public static func message(
        for formatter: DestinationFormatter, situation: Situation, heard: String? = nil,
        steps: CleaningSteps = .default, vocabulary: [String] = []
    ) -> CleaningPipeline {
        let casing = AcronymCasingPass(
            destination: formatter.destination, vocabulary: vocabulary, onScreen: situation.app.textOnScreen)
        // Only a chat takes "at Sam" as a mention; everywhere else it is a word.
        let mentions: [any WholeTextCleaningPass] =
            formatter.destination == .messaging
            ? [AtMentionPass(precedingText: situation.insertion.precedingText)] : []
        return CleaningPipeline(
            wholeText: initialisms(steps: steps) + [casing] + mentions + [
                SentenceBoundaryPass(),
                FirstWordPass(
                    policy: formatter.firstWord, state: situation.insertion.sentenceState,
                    onScreen: situation.app.textOnScreen, heard: heard,
                    capitaliseCalendarWords: formatter.firstWord == .fromInsertionPoint
                        && formatter.destination != .codeEditor,
                    vocabulary: vocabulary, casing: casing, keepsCommandCase: formatter.keepsCommandCase),
                CommentMarkerPass(
                    opensComment: formatter.destination == .codeEditor
                        && CaretStructure.opensComment(
                            precedingText: situation.insertion.precedingText,
                            documentName: situation.app.documentName)
                ),
                TerminalStopPass(
                    policy: terminalStop(formatter, in: situation), layout: formatter.layout,
                    insertionPoint: situation.insertion, destination: formatter.destination),
            ])
    }

    /// The one registration of the spelled-letter join, a whole-text pass filtered like every other step.
    private static func initialisms(steps: CleaningSteps) -> [any WholeTextCleaningPass] {
        [SpelledInitialismPass()].filter { steps.runs($0.id) }
    }

    /// The formatter's stop policy, except a code editor takes `.always` when the caret sits in a comment.
    private static func terminalStop(
        _ formatter: DestinationFormatter, in situation: Situation
    ) -> TerminalStopPolicy {
        guard formatter.destination == .codeEditor else { return formatter.terminalStop }
        return situation.intent.region == .comment ? .always : formatter.terminalStop
    }
}

extension AppContext {
    /// The strings read off the screen a name can be sighted in: title, selection and the text at the caret.
    var textOnScreen: [String] {
        [documentName, selectedText, precedingText, followingText].compactMap { $0 }
    }
}
