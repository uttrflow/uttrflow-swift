import UttrflowPredict

/// Decides whether the model pause has the energy cause announced to VoiceOver.
enum SuggestionEnergyStatus {
    /// A model that is loading or unavailable is not described as energy-paused.
    static func shouldAnnouncePause(for generator: (any CandidateGenerating)?) -> Bool {
        generator?.isHeldForEnergy ?? false
    }
}
