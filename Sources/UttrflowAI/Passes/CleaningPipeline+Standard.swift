public import UttrflowCore

extension CleaningPipeline {
    /// Every pass in the order they ship, from the cheapest removal to the final full stop.
    public static let standard = CleaningPipeline(passes: [
        FillersPass(), StammersPass(), RepeatedPhrasePass(), SelfCorrectionPass(), SpokenPunctuationPass(),
        LayoutWordsPass(), NumberFormsPass(), SpacingPass(), FirstWordPass(), TerminalStopPass(),
    ])

    /// The passes a language model is handed the result of; casing and the full stop are finished after it.
    public static let beforeModel = standard.without([FirstWordPass.id, TerminalStopPass.id])
}
