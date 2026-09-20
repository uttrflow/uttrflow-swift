public import UttrflowCore

extension CleaningPipeline {
    /// Every pass in the shipped order, for plain text at a caret that says nothing.
    public static let standard = standard(for: .standard(for: .plain), situation: .unknown)

    /// The passes a language model is handed the result of, which are the piece's; the message's are finished after it.
    public static func beforeModel(
        for formatter: DestinationFormatter, situation: Situation, steps: CleaningSteps = .default
    ) -> CleaningPipeline {
        piece(numbers: formatter.numbers, digits: formatter.digits, steps: steps)
    }

    /// Every pass the user has left on over a whole message, in the shipped order: the piece's, then the message's.
    public static func standard(
        for formatter: DestinationFormatter, situation: Situation, steps: CleaningSteps = .default
    ) -> CleaningPipeline {
        CleaningPipeline(
            passes: piece(numbers: formatter.numbers, digits: formatter.digits, steps: steps).passes
                + message(for: formatter, situation: situation).passes)
    }

    /// The passes that are right on any piece of a message, which is why no casing or stop policy can reach them.
    public static func piece(
        numbers: NumberPolicy, digits: DigitGrouping, steps: CleaningSteps = .default
    ) -> CleaningPipeline {
        let cleanings: [any CleaningPass] = [
            FillersPass(), StammersPass(), RepeatedPhrasePass(), SelfCorrectionPass(),
            SpokenPunctuationPass(), LayoutWordsPass(),
            NumberFormsPass(policy: numbers, digits: digits),
            ContractionsPass(), SpacingPass(),
        ]
        return CleaningPipeline(passes: cleanings.filter { steps.runs($0.id) })
    }

    /// The passes that finish a model's answer to a whole message: the caret's echo taken back, then the message's.
    public static func afterModel(
        for formatter: DestinationFormatter, situation: Situation, heard: String? = nil
    ) -> CleaningPipeline {
        CleaningPipeline(
            passes: afterModelPiece(situation: situation, heard: heard).passes
                + message(for: formatter, situation: situation, heard: heard).passes)
    }

    /// What finishes a model's answer to one piece: only the caret's echo, since each piece's prompt quotes the caret.
    public static func afterModelPiece(situation: Situation, heard: String? = nil) -> CleaningPipeline {
        CleaningPipeline(passes: [
            CaretEchoPass(
                state: situation.insertion.sentenceState, precedingText: situation.insertion.precedingText,
                spokenText: heard)
        ])
    }

    /// The two passes asked once of a whole message, the first word and the final stop; `heard` is what `.asSpoken` copies.
    public static func message(
        for formatter: DestinationFormatter, situation: Situation, heard: String? = nil
    ) -> CleaningPipeline {
        CleaningPipeline(passes: [
            FirstWordPass(
                policy: formatter.firstWord, state: situation.insertion.sentenceState,
                onScreen: situation.app.textOnScreen, heard: heard),
            TerminalStopPass(policy: formatter.terminalStop, layout: formatter.layout),
        ])
    }
}

extension AppContext {
    /// The strings read off the screen a name can be sighted in: title, selection and the text at the caret.
    var textOnScreen: [String] {
        [documentName, selectedText, precedingText, followingText].compactMap { $0 }
    }
}
