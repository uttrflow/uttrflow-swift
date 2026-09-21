import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

/// Dictation writes Latin letters only, and a rewrite of Hindi romanises it rather than translating it.
@Suite("The script guard")
struct ScriptGuardTests {
    private let sut = MeaningPreservationGuard()
    private let examples = PromptBuilder.standard.allWorkedExamples

    @Test(
        "refuses a Devanagari draft rewritten as English",
        arguments: [
            ("मीटिंग चार बजे है, नहीं नहीं, पांच बजे है.", "Meeting is at four o'clock, no no, five o'clock."),
            ("मेरी फ्लाइट 15 अगस्त को सुबह 9 बजे है।", "My flight is on 15 August at 9 in the morning."),
            ("हाँ ठीक है", "Yes, okay."),
            ("धन्यवाद", "Thank you."),
        ])
    func refusesATranslation(draft: String, rewritten: String) {
        #expect(
            sut.scriptVerdict(draft: draft, rewritten: rewritten, examples: examples)
                == .rejected(
                    reason: "the rewrite translated the Hindi instead of romanising it", kind: .translated))
    }

    @Test(
        "accepts a romanisation, spelled any of the usual ways, with digits for number words",
        arguments: [
            ("वो क्या है ना, यानि मुझे थोड़ा टाइम चाहिए.", "Woh kya hai na, yaani mujhe thoda time chahiye."),
            ("हाँ ठीक है", "Haan theek hai."),
            ("मैं meeting के लिए बीस मिनट late हो जाऊंगा", "Main meeting ke liye 20 minute late ho jaunga."),
            ("कल सुबह, सौरी, परशो सुबह, कॉल करना.", "Kal subah, sorry, parson subah, call karna."),
            ("धन्यवाद", "Dhanyawad."),
        ])
    func acceptsARomanisation(draft: String, rewritten: String) {
        #expect(sut.scriptVerdict(draft: draft, rewritten: rewritten, examples: examples) == .accepted)
    }

    @Test(
        "refuses a rewrite written in any script but Latin",
        arguments: [("हाँ ठीक है", "हाँ, ठीक है।"), ("हाँ ठीक है", "ہاں ٹھیک ہے"), ("ship it", "Ship it ✓ готово")])
    func refusesAnotherScript(draft: String, rewritten: String) {
        #expect(
            sut.scriptVerdict(draft: draft, rewritten: rewritten)
                == .rejected(
                    reason: "the rewrite is not written in the Latin alphabet", kind: .notLatinScript))
    }

    @Test("refuses the prompt's own worked example given back for a dictation that did not say it")
    func refusesAnEchoedExample() {
        let verdict = sut.scriptVerdict(
            draft: "मतलब मैं कल आएगा, हाँ, अच्छा तो फिर मिलते हैं.",
            rewritten: "Main aaj ke standup mein deployment ke baare mein baat karunga.", examples: examples)

        guard case .rejected(let reason, _) = verdict else {
            Issue.record("accepted the worked example")
            return
        }
        #expect(reason.hasPrefix("the rewrite repeats the worked example"))
    }

    @Test("refuses an English worked example given back for English that did not say it")
    func refusesAnEchoedEnglishExample() {
        #expect(
            !sut.scriptVerdict(
                draft: "remind me to water the plants", rewritten: "Add milk and eggs to the shopping list.",
                examples: examples
            ).isAccepted)
    }

    @Test(
        "accepts a dictation that says what a worked example says",
        arguments: [
            ("add milk and eggs to the shopping list", "Add milk and eggs to the shopping list."),
            ("as a gift as a present", "As a present."),
            ("the supplier changed their banks", "The supplier changed their banks."),
            ("okay", "Okay."),
        ])
    func acceptsAnExampleActuallySaid(draft: String, rewritten: String) {
        #expect(sut.scriptVerdict(draft: draft, rewritten: rewritten, examples: examples) == .accepted)
    }

    @Test("accepts an English rewrite of English and a rewrite of nothing but numbers")
    func acceptsEnglishAndNumbers() {
        #expect(
            sut.scriptVerdict(
                draft: "we should ship this on friday", rewritten: "We should ship this on Friday.")
                == .accepted)
        #expect(sut.scriptVerdict(draft: "पंद्रह", rewritten: "15.") == .accepted)
    }

    @Test("counts words shared in order, by exact spelling")
    func sharedInOrder() {
        #expect(MeaningPreservationGuard.inOrder(["a", "b", "c", "d"], ["a", "c", "d", "b"]) == 3)
        #expect(MeaningPreservationGuard.inOrder([], ["a"]) == 0)
        #expect(MeaningPreservationGuard.inOrder(["main"], ["mein"]) == 0)
    }
}

/// The generative engine falls back rather than insert a translation, and the rules write Latin letters.
@Suite("Latin-only dictation through the engines")
struct LatinOnlyEngineTests {
    private func hindi(_ text: String) -> TransformationRequest {
        TransformationRequest(transcription: .fixture(text: text, language: .hindi))
    }

    @Test("refuses a model's English translation of a Devanagari dictation")
    func generativeRefusesTranslation() async {
        let model = FakeCleanupModel { _ in "Meeting is at four o'clock, no no, five o'clock." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await #expect(
            throws: TransformationError.outputRejected(
                reason: "the rewrite translated the Hindi instead of romanising it",
                kind: .translated)
        ) {
            try await sut.transform(hindi("मीटिंग चार बजे है, नहीं नहीं, पांच बजे है."))
        }
    }

    @Test("accepts a model's romanisation of a Devanagari dictation")
    func generativeAcceptsRomanisation() async throws {
        let model = FakeCleanupModel { _ in "Aaj bahut baarish ho rahi hai." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        #expect(try await sut.transform(hindi("आज बहुत बारिश हो रही है।")).text == "Aaj bahut baarish ho rahi hai.")
    }

    @Test(
        "keeps the romanised draft when the model translates, the worked example comes back, or the model declines"
    )
    func routerFallsBackToRomanisedRules() async throws {
        for answer in ["Meeting is at four o'clock, no no, five o'clock.", "मीटिंग पाँच बजे है।"] {
            let model = GenerativeTextTransformer(
                kind: .foundationModels, model: FakeCleanupModel { _ in answer })
            let router = TransformerRouter(
                engines: [model, RuleBasedTransformer()], preference: [.foundationModels, .rules])

            let result = try await router.transform(hindi("मीटिंग चार बजे है, नहीं नहीं, पांच बजे है।"))

            #expect(result.producedBy == .rules)
            #expect(result.text == "Meeting chaar baje hai, nahi nahi, paanch baje hai.")
        }
        let declining = FakeCleanupModel()
        declining.fail(with: .transformFailed(kind: .foundationModels, description: "unsupported language"))
        let router = TransformerRouter(
            engines: [
                GenerativeTextTransformer(kind: .foundationModels, model: declining), RuleBasedTransformer(),
            ],
            preference: [.foundationModels, .rules])
        #expect(try await router.transform(hindi("हाँ ठीक है")).text == "Haan thik hai.")
    }

    @Test("writes every Hindi and Hinglish dictation in Latin letters on the rules path")
    func rulesNeverWriteDevanagari() async throws {
        let passages = [
            "कल शाम को मैं घर जल्दी पहुँच गया था इसलिए वो काम नहीं हो पाया। आज सुबह कर दूँगा, चिंता मत करो।",
            "Priya ने कहा कि Bengaluru वाली team आज call पर नहीं आ पाएगी।", "हाँ ठीक है।", "मेरी फ्लाइट १५ अगस्त को है॥",
        ]
        for passage in passages {
            for scope in [CleaningScope.message, .piece] {
                let request = TransformationRequest(
                    transcription: .fixture(text: passage, language: .hindi), scope: scope)
                let text = try await RuleBasedTransformer().transform(request).text
                #expect(LatinScript.isLatin(text), "\(scope): \(text)")
                #expect(!Romaniser.containsDevanagari(text), "\(scope): \(text)")
            }
        }
    }

    @Test("romanises a short Hindi reply on the rules path the way it is typed")
    func rulesRomaniseAReply() async throws {
        #expect(try await RuleBasedTransformer().transform(hindi("हाँ ठीक है")).text == "Haan thik hai.")
        #expect(
            try await RuleBasedTransformer().transform(hindi("मैं अभी आता हूँ।")).text == "Main abhi aata hoon.")
    }
}
