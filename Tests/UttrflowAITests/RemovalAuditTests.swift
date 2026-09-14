import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

/// Which of a draft's removals the removing pass had the grant to make, and the guard's verdict on the rest.
@Suite("Removals held to each pass's grant")
struct RemovalAuditTests {
    /// The passes a model is handed the result of, over plain text.
    private let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .plain), situation: .unknown)

    private func draft(_ spoken: String) -> Draft {
        pipeline.run(Draft(text: spoken))
    }

    private func unauthorised(_ spoken: String) -> [UnauthorisedRemoval] {
        RemovalAudit.unauthorised(in: draft(spoken), grants: pipeline.grants)
    }

    @Test("names what each pass may remove")
    func grants() {
        let grants = pipeline.grants
        #expect(grants[.fillers] == .sound)
        #expect(grants[.stammers] == .repetition)
        #expect(grants[.repeatedPhrase] == .repetition)
        #expect(grants[.selfCorrection] == .retraction)
        #expect(grants[.spokenPunctuation] == .conversion)
        #expect(grants[.layoutWords] == .conversion)
        #expect(grants[.numberForms] == .conversion)
    }

    @Test(
        "finds nothing in the removals each pass is there to make",
        arguments: [
            "um we should uh ship it today",
            "so I was I was I was thinking we could ship",
            "just checking in on the the design review",
            "let's meet at four no sorry at five on tuesday",
            "the build is not ready no the build is ready",
            "send it never mind send it later",
            "the report I mean the report is late",
            "we still need milk comma eggs comma and bread",
            "first point new line second point",
            "we need two hundred and fifty chairs",
            "we still need to ship dont we",
        ])
    func findsNothingGranted(spoken: String) {
        #expect(unauthorised(spoken).isEmpty, "\(draft(spoken).text)")
    }

    @Test("finds an acronym the filler pass took for a sound")
    func findsAcronymTakenForASound() {
        #expect(
            unauthorised("we rushed him to ER before midnight") == [
                UnauthorisedRemoval(pass: .fillers, text: "ER")
            ])
        #expect(!RemovalAudit.isSound("ER"))
        #expect(!RemovalAudit.isSound("4"))
        #expect(RemovalAudit.isSound("Um,"))
    }

    @Test("finds a negating trigger whose correction took nothing back")
    func findsUnretractedNegation() {
        #expect(
            unauthorised("tell the landlord no, the landlord has to wait")
                == [UnauthorisedRemoval(pass: .selfCorrection, text: "no,")])
    }

    @Test("finds a repetition with nothing said again after it")
    func findsUnrepeatedRemoval() {
        var draft = Draft(text: "ship the build today")
        draft.remove(at: 2, by: .stammers)
        #expect(
            RemovalAudit.unauthorised(in: draft, grants: pipeline.grants)
                == [UnauthorisedRemoval(pass: .stammers, text: "build")])
    }

    @Test(
        "finds a removal a converting pass wrote nothing for, and reads an unnamed pass as one that converts")
    func findsConversionThatWroteNothing() {
        var draft = Draft(text: "ship the build today")
        draft.remove(at: 3, by: .numberForms)
        draft.remove(at: 0, by: "unnamed")
        #expect(
            RemovalAudit.unauthorised(in: draft, grants: pipeline.grants)
                == [
                    UnauthorisedRemoval(pass: "unnamed", text: "ship"),
                    UnauthorisedRemoval(pass: .numberForms, text: "today"),
                ])
    }

    // MARK: The guard

    private func verdict(_ spoken: String, _ rewritten: String) -> GuardVerdict {
        MeaningPreservationGuard().verdict(
            draft: draft(spoken), rewritten: rewritten, grants: pipeline.grants)
    }

    @Test("refuses a rewrite that leaves out an acronym the filler pass took")
    func refusesLostAcronym() {
        #expect(
            verdict("we rushed him to ER before midnight", "We rushed him to before midnight.")
                == .rejected(reason: "the fillers step took out 'ER' and the rewrite does not put it back"))
    }

    @Test("accepts a rewrite that puts back the acronym, which is the speaker's word and not an invention")
    func acceptsRestoredAcronym() {
        #expect(
            verdict("we rushed him to ER before midnight", "We rushed him to ER before midnight.")
                == .accepted)
    }

    @Test("refuses a rewrite that leaves out a negation a correction took back for nothing")
    func refusesLostNegation() {
        #expect(
            verdict("tell the landlord no, the landlord has to wait", "Tell the landlord has to wait.")
                == .rejected(
                    reason: "the selfCorrection step took out 'no' and the rewrite does not put it back"))
    }

    @Test("accepts a rewrite that puts the negation back")
    func acceptsRestoredNegation() {
        #expect(
            verdict(
                "tell the landlord no, the landlord has to wait",
                "Tell the landlord no, the landlord has to wait.")
                == .accepted)
    }

    @Test("counts the negation put back on top of the ones the draft kept")
    func countsRestoredNegationOverKept() {
        #expect(
            !verdict(
                "do not tell the landlord no, the landlord has to wait",
                "Do not tell the landlord has to wait."
            )
            .isAccepted)
    }

    @Test("accepts the removals the passes are there to make, as before")
    func acceptsGrantedRemovals() {
        #expect(
            verdict("um let's meet at four no sorry at five on tuesday", "Let's meet at five on Tuesday.")
                == .accepted)
    }

    @Test("refuses through the transformer, which hands the guard its own pipeline's grants")
    func refusesThroughTransformer() async {
        let model = FakeCleanupModel { _ in "We rushed him to before midnight." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)
        let request = TransformationRequest(
            transcription: .fixture(text: "we rushed him to ER before midnight", language: .english))
        await #expect(throws: TransformationError.self) { try await sut.transform(request) }
    }
}
