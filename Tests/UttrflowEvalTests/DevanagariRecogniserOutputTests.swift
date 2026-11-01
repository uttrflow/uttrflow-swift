// Shows that a recogniser answer in Devanagari is written in Latin letters by the layers that ship.
import Testing

@testable import UttrflowCore
@testable import UttrflowEval

/// The last-resort layer writes Latin for Devanagari answers; the pipeline path is in `DictationPipelineLatinOutputTests`.
@Suite("Devanagari recogniser output")
struct DevanagariRecogniserOutputTests {
    @Test("writes every Hindi and Hinglish passage heard in Devanagari as Latin letters")
    func enforcedIsLatinForEveryPassage() {
        var checked = 0
        for passage in TranscriptionCorpus.all {
            guard let heard = passage.devanagari else { continue }
            checked += 1
            let written = LatinScript.enforced(heard)
            #expect(!Romaniser.containsDevanagari(written), "\(passage.id) kept Devanagari: \(written)")
            #expect(LatinScript.isLatin(written), "\(passage.id) is not Latin: \(written)")
        }
        #expect(checked == TranscriptionCorpus.all.filter { $0.language != .english }.count)
    }
}
