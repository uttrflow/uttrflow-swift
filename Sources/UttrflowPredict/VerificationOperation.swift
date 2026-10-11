/// The identity one verification operation carries to publication.
struct VerificationOperation: Sendable {
    let surface: Surface
    let generation: UInt64
    let aliases: AliasExpansionSnapshot

    func report(
        _ verdict: Verdict, on text: String, leading: String
    )
        -> (verdict: Verdict, write: SupersessionWrite?)
    {
        switch verdict {
        case .corrected(let word):
            let corrected = leading + word
            return (.corrected(corrected), .supersede(text, corrected))
        case .rejected: return (.rejected, .reject(text))
        case .attested, .plausible: return (verdict, nil)
        }
    }

    func key(for candidate: String, typed: String) -> VerdictCache.Key {
        VerdictCache.Key(candidate: candidate, context: Self.identity(of: surface, typed: typed))
    }

    static func identity(of surface: Surface, typed: String) -> String {
        [
            surface.bundleIdentifier, surface.role, surface.locator ?? "", surface.scope ?? "", typed,
        ].joined(separator: "\u{0}")
    }
}
