// Tests the code-mixed Hinglish passages a synthetic voice reads into the transcription corpus.
import Testing

@testable import UttrflowEval

/// Checks the matrix is whole, Latin-only and winnable, so a low score is the recogniser's.
@Suite("Code-mixing passages")
struct CodeMixingPassagesTests {
    private let passages = TranscriptionCorpus.codeMixing
    private let normaliser = TextNormaliser.standard

    @Test("covers every frame and kind of inserted word exactly once")
    func everyCellOnce() {
        for frame in CodeMixingPassages.Frame.allCases {
            for insert in CodeMixingPassages.Insert.allCases {
                let cell = passages.filter {
                    $0.stresses.contains("frame-\(frame.rawValue)")
                        && $0.stresses.contains("insert-\(insert.rawValue)")
                }
                #expect(cell.count == 1, "\(frame.rawValue) x \(insert.rawValue) has \(cell.count) passages")
            }
        }
        #expect(passages.count == 12)
    }

    @Test("spreads the switch evenly over start, middle and end")
    func positionsBalanced() {
        for position in CodeMixingPassages.Position.allCases {
            #expect(passages.filter { $0.stresses.contains("switch-\(position.rawValue)") }.count == 4)
        }
    }

    @Test("is Latin-only Hinglish marked as code-switching, with no Devanagari form")
    func latinOnly() {
        for passage in passages {
            #expect(passage.language == .hinglish)
            #expect(passage.devanagari == nil, "\(passage.id) has a Devanagari form")
            #expect(Script.of(passage.romanised) == .latin, "\(passage.id) is not Latin")
            #expect(passage.stresses.contains(CorpusStress.codeSwitching))
            #expect(passage.stresses.contains(passage.stressor.rawValue))
        }
    }

    @Test("stays out of the passages read aloud by a person, with ids of its own")
    func separateFromReadCorpus() {
        let ids = Set(passages.map(\.id))
        #expect(ids.count == passages.count)
        #expect(ids.isDisjoint(with: TranscriptionCorpus.all.map(\.id)))
    }

    @Test("is long enough to measure and keeps every required term")
    func lengthAndTerms() {
        for passage in passages {
            let words = normaliser.words(passage.romanised)
            #expect(words.count >= 25, "\(passage.id) is too short to measure")
            for term in passage.mustKeep {
                #expect(
                    Scorer.containsPhrase(normaliser.words(term), in: words), "\(passage.id) lacks '\(term)'")
            }
        }
    }

    @Test("scores a perfect transcript at zero")
    func perfectScoresZero() {
        for passage in passages {
            let score = TranscriptionScorer.score(passage.romanised, against: passage)
            #expect(score.wordErrorRate?.rate == 0, "\(passage.id) cannot be transcribed perfectly")
            #expect(score.lost.isEmpty)
        }
    }

    @Test("is checked by the contamination audit")
    func audited() {
        let audited = Set(ContaminationAudit.corpusPassages.map(\.caseID))
        #expect(passages.allSatisfy { audited.contains($0.id) })
    }
}
