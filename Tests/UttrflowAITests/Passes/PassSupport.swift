import UttrflowCore

@testable import UttrflowAI

/// The text a pass leaves behind, for tests that care about words rather than provenance.
func cleaned(_ text: String, by pass: some CleaningPass) -> String {
    pass.apply(Draft(text: text)).text
}
