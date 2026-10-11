import Testing

@testable import UttrflowPredict

@Suite("Verification operation state")
struct VerificationSessionTests {
    private let terminal = Surface(
        bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "/repo")
    private let prose = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
    private let key = VerdictCache.Key(candidate: "git status", context: "fixture")

    private func begin(_ session: inout VerificationSession, revision: UInt64) -> VerificationOperation {
        session.begin(
            in: terminal, aliases: AliasExpansionSnapshot(words: [:], revision: revision),
            generation: session.generation)
    }

    @Test("The same revision preserves the remembered verdict and a newer one invalidates it.")
    func revisionIdentity() {
        var session = VerificationSession()
        let first = begin(&session, revision: 1)
        session.remember(.attested, for: key)
        let same = begin(&session, revision: 1)
        #expect(session.verdict(for: key) == .attested)
        #expect(session.isCurrent(first) && session.isCurrent(same))
        let newer = begin(&session, revision: 2)
        #expect(session.count == 0)
        #expect(!session.isCurrent(first) && session.isCurrent(newer))
    }

    @Test("An older revision cannot clear a newer cache or restore its operation identity.")
    func olderRevisionCannotMutate() {
        var session = VerificationSession()
        let newer = begin(&session, revision: 2)
        session.remember(.plausible, for: key)
        let older = begin(&session, revision: 1)
        #expect(session.verdict(for: key) == .plausible)
        #expect(session.isCurrent(newer) && !session.isCurrent(older))
        _ = begin(&session, revision: 2)
        #expect(session.count == 1)
    }

    @Test("Forget invalidates a captured operation without letting its late begin alter new state.")
    func staleGenerationCannotMutate() {
        var session = VerificationSession()
        let old = begin(&session, revision: 9)
        session.remember(.attested, for: key)
        session.forgetEverything()
        #expect(session.count == 0 && !session.isCurrent(old))
        let current = begin(&session, revision: 1)
        session.remember(.plausible, for: key)
        let late = session.begin(in: terminal, aliases: old.aliases, generation: old.generation)
        #expect(session.verdict(for: key) == .plausible)
        #expect(session.isCurrent(current) && !session.isCurrent(late))
        _ = begin(&session, revision: 1)
        #expect(session.count == 1)
    }

    @Test(
        "A prose operation preserves eligible revision state and the first empty identity preserves prose cache."
    )
    func prosePreservesState() {
        var session = VerificationSession()
        session.remember(.plausible, for: key)
        let terminalOperation = begin(&session, revision: 0)
        #expect(session.count == 1)
        let proseOperation = session.begin(
            in: prose, aliases: AliasExpansionSnapshot(words: [:], revision: 99),
            generation: session.generation)
        #expect(session.isCurrent(terminalOperation) && session.isCurrent(proseOperation))
        _ = begin(&session, revision: 0)
        #expect(session.verdict(for: key) == .plausible)
        session.forgetEverything()
        #expect(!session.isCurrent(proseOperation))
    }

    @Test("Reports preserve whole-line text and the exact corpus-write candidate.")
    func reportIdentity() {
        var session = VerificationSession()
        let operation = begin(&session, revision: 0)
        let corrected = operation.report(.corrected("status"), on: "git sttaus", leading: "git ")
        #expect(corrected.verdict == .corrected("git status"))
        if case .supersede(let original, let replacement)? = corrected.write {
            #expect(original == "git sttaus" && replacement == "git status")
        } else {
            Issue.record("A correction produces its exact supersession write.")
        }
        #expect(corrected.write?.candidate == "git sttaus")
        let rejected = operation.report(.rejected, on: "git unknown", leading: "git ")
        #expect(rejected.verdict == .rejected && rejected.write?.candidate == "git unknown")
        if case .reject(let original)? = rejected.write {
            #expect(original == "git unknown")
        } else {
            Issue.record("A refusal produces its exact rejection write.")
        }
        for verdict in [Verdict.attested, .plausible] {
            let report = operation.report(verdict, on: "fixture", leading: "prefix ")
            #expect(report.verdict == verdict && report.write == nil)
        }
    }

    @Test("Context identity keeps every field component and the typed text in their original order.")
    func contextIdentity() {
        let surface = Surface(
            bundleIdentifier: "com.example.editor", role: "AXTextArea", locator: "fixture", scope: "/repo")
        #expect(
            VerificationOperation.identity(of: surface, typed: "git ")
                == "com.example.editor\0AXTextArea\0fixture\0/repo\0git ")
        let operation = VerificationOperation(
            surface: surface, generation: 0, aliases: AliasExpansionSnapshot(words: [:], revision: 0))
        #expect(
            operation.key(for: "git status", typed: "git ")
                == VerdictCache.Key(
                    candidate: "git status", context: "com.example.editor\0AXTextArea\0fixture\0/repo\0git "))
        #expect(Verifier.context(of: prose, typed: "") == "com.example.notes\0AXTextArea\0\0\0")
    }
}
