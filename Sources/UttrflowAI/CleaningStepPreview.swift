public import UttrflowCore
import UttrflowDictionary

/// A step's example cleaned with that step on and with it off, by the same rules dictation runs.
public struct CleaningStepPreview: Sendable, Equatable {
    public let step: PassID
    /// The example as the rules leave it with the step switched off.
    public let without: String
    /// The example as the rules leave it with the step switched on.
    public let with: String

    /// The preview for one offered step under the user's other choices, with no model and no context.
    public static func of(_ step: CleaningStep, steps: CleaningSteps = .default) -> CleaningStepPreview {
        CleaningStepPreview(
            step: step.id,
            without: cleaned(step.example, steps: steps.setting(step.id, isOn: false)),
            with: cleaned(step.example, steps: steps.setting(step.id, isOn: true)))
    }

    /// One preview per offered step, in the order the steps run.
    public static func all(steps: CleaningSteps = .default) -> [CleaningStepPreview] {
        CleaningSteps.offered.map { of($0, steps: steps) }
    }

    /// The deterministic transformer's own path over a whole message at a caret that says nothing.
    static func cleaned(_ spoken: String, steps: CleaningSteps) -> String {
        let pipeline = CleaningPipeline.standard(
            for: .standard(for: .unknown), situation: .unknown, steps: steps)
        let draft = LoanwordRestoration().restoring(Draft(romanising: Transcription(text: spoken)))
        return RuleBasedTransformer.audited(pipeline, over: draft).draft.text
    }
}
