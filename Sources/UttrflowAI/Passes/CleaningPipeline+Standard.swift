public import UttrflowCore

extension CleaningPipeline {
    /// Every pass in the shipped order, for plain text at a caret that says nothing.
    public static let standard = standard(for: .standard(for: .plain), situation: .unknown)

    /// The passes a language model is handed the result of; casing and the full stop are finished after it.
    public static let beforeModel = standard.without([FirstWordPass.id, TerminalStopPass.id])

    /// Every pass in the shipped order, the first word and the final stop decided by the formatter and the caret.
    public static func standard(
        for formatter: DestinationFormatter, situation: Situation
    ) -> CleaningPipeline {
        CleaningPipeline(
            passes: [
                FillersPass(), StammersPass(), RepeatedPhrasePass(), SelfCorrectionPass(),
                SpokenPunctuationPass(), LayoutWordsPass(), NumberFormsPass(), SpacingPass(),
            ] + afterModel(for: formatter, situation: situation).passes)
    }

    /// The two passes that finish a model's answer as the formatter says; `heard` is the transcript `.asSpoken` copies.
    public static func afterModel(
        for formatter: DestinationFormatter, situation: Situation, heard: String? = nil
    ) -> CleaningPipeline {
        CleaningPipeline(passes: [
            FirstWordPass(
                policy: formatter.firstWord, state: situation.insertion.sentenceState,
                onScreen: situation.app.textOnScreen, heard: heard),
            TerminalStopPass(policy: formatter.terminalStop),
        ])
    }
}

extension AppContext {
    /// The strings read off the screen a name can be sighted in: title, selection and the text at the caret.
    var textOnScreen: [String] {
        [documentName, selectedText, precedingText, followingText].compactMap { $0 }
    }
}
