import UttrflowCore
import Testing

@testable import UttrflowAI

/// The override gate counts agreement across where signals were read from, never across the signals themselves.
@Suite("SignalProvenance")
struct SignalProvenanceTests {
    /// Whether the cheapest tier of the gate lets this many agreeing provenances through.
    private func passes(_ signals: [Sourced<String>]) -> Bool {
        DoubtPolicy.OverridePolicy.allows(
            margin: SignalProvenance.agreement(of: signals), cost: .cosmetic, consequence: .stores)
    }

    /// One persona word read three ways: biased at decode time, offered as a candidate, and in the n-gram table.
    private let personaThreeWays = [
        Sourced(value: "decode bias", provenance: .personaList),
        Sourced(value: "candidate", provenance: .personaList),
        Sourced(value: "domain n-gram", provenance: .personaList),
    ]

    @Test("two signals of one provenance count once")
    func oneProvenanceCountsOnce() {
        let twice = [
            Sourced(value: "seen", provenance: SignalProvenance.windowText),
            Sourced(value: "seen again", provenance: .windowText),
        ]
        #expect(SignalProvenance.agreement(of: twice) == 1)
    }

    @Test("a persona word biased, offered and in the n-gram table does not pass the two-signal rule alone")
    func personaAloneDoesNotPass() {
        #expect(SignalProvenance.agreement(of: personaThreeWays) == 1)
        #expect(!passes(personaThreeWays))
    }

    @Test(
        "the same persona word passes once an acoustic or caret-text signal agrees",
        arguments: [SignalProvenance.recogniserAcoustics, .caretText])
    func anIndependentSignalPasses(_ independent: SignalProvenance) {
        let signals = personaThreeWays + [Sourced(value: "independent", provenance: independent)]
        #expect(SignalProvenance.agreement(of: signals) == 2)
        #expect(passes(signals))
    }

    // MARK: The gate's own signals

    /// Each reason the gate counts today is read from its own place, so provenance-aware and raw counting agree.
    @Test("stray letters spelt out stay two signals, letters and word count, as raw counting had them")
    func strayLettersKeepTheirCount() {
        let evidence = CorrectionEvidence(utterance: CorrectionFixtures.spoken(""), seeing: .unknown)
        let decision = evidence.decision(preferring: "SQL", over: "s q l")
        #expect(decision?.evidence == OverrideEvidence(signals: 2, margin: 2))
        #expect(
            evidence.signals(preferring: "SQL", over: "s q l").gained.map(\.provenance)
                == [.transcriptLetters, .transcriptWordCount])
    }

    @Test("a word said surely elsewhere is read from the recogniser")
    func saidClearlyIsAcoustic() {
        let evidence = CorrectionEvidence(
            utterance: CorrectionFixtures.spoken("Claude answered again"), seeing: .unknown)
        #expect(
            evidence.signals(preferring: "Claude", over: "clawed").gained.map(\.provenance)
                == [.recogniserAcoustics])
    }

    @Test("a word on screen is read from the caret text when it is there, else from the window")
    func theScreenIsToldApart() {
        let nearCaret = CorrectionEvidence(
            utterance: CorrectionFixtures.spoken(""),
            seeing: AppContext(documentName: "Claude notes", precedingText: "ask Claude"))
        let inWindow = CorrectionEvidence(
            utterance: CorrectionFixtures.spoken(""), seeing: AppContext(documentName: "Claude notes"))
        #expect(
            nearCaret.signals(preferring: "Claude", over: "clawed").gained.map(\.provenance) == [.caretText])
        #expect(
            inWindow.signals(preferring: "Claude", over: "clawed").gained.map(\.provenance) == [.windowText])
    }
}
