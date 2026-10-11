public import UttrflowCore

/// Holds the field a paste question names, so agreeing is checked against it and never answers for another field.
@MainActor
public final class PasteGate {
    private var asked: HiddenPasteDestination?

    /// Creates a gate with no question outstanding.
    public init() {}

    /// Decides the paste, checking an agreed one against the asked field, reading the focused field when a hidden clip needs it, and remembers the field when it asks.
    public func decide(
        _ situation: PasteQuestion.Situation, focus: any AccessibilityFocus
    ) async -> PasteQuestion.Decision {
        var situation = situation
        if situation.isAgreed { situation.fieldUnchanged = await agreementHolds(on: focus) }
        var read: HiddenPasteDestination?
        if situation.needsFieldRead {
            read = await HiddenPasteDestination.read(from: focus)
            situation.field = read?.field ?? .unclassified
        }
        let decision = PasteQuestion.decide(situation)
        guard case .ask = decision else { return decision }
        asked = read
        if read == nil { asked = await HiddenPasteDestination.read(from: focus) }
        return decision
    }

    /// Whether the focus is still on the field the answered question named; the question is spent either way.
    func agreementHolds(on focus: any AccessibilityFocus) async -> Bool {
        let question = asked
        asked = nil
        return await question?.isUnchanged(on: focus) ?? false
    }

    /// Drops any outstanding question, as when the panel closes.
    public func forget() { asked = nil }
}
