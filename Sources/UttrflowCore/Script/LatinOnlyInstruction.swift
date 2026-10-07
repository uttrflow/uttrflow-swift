// The Latin-only rule as a model is told it.

/// The one wording of the Latin-only rule every prompt carries, so a change to the rule is made once. See `Docs/latin-output.md`.
public enum LatinOnlyInstruction {
    /// The sentences a prompt quotes verbatim; `LatinScript` is the check that holds whatever a model writes.
    public static let text =
        "Write only English in the Latin alphabet, or romanised Hinglish where the person writes Hindi in Latin "
        + "letters. Never write Devanagari or any other script, and never translate."
}
