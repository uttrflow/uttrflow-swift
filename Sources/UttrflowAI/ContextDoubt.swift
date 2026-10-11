// Which words the recogniser heard surely but whose meaning sits apart from the rest of their sentence.
import NaturalLanguage
import Synchronization
import UttrflowCore

/// Doubts a surely heard word the English embedding does not hold, or holds far from the rest of its sentence. See Docs/cleanup.md.
enum ContextDoubt {
    /// Cosine distance to the nearest other word past which a word sits apart; fitted on the labelled English WhisperKit set.
    static let distanceLine = 1.246
    /// At or above this score the recogniser vouches for a word whatever the sentence says; fitted on the same set.
    static let vouchingScore = 0.9
    /// The distance a word the embedding does not hold is given: the largest a cosine distance can be.
    static let unknownDistance = 2.0

    /// The shipped English embedding, loaded once; it is not documented as safe to share, so it is read under a lock.
    private static let embedding = Mutex(NLEmbedding.wordEmbedding(for: .english))

    /// The positions of the words that sit apart from the rest, among words scored in the band context may doubt.
    static func doubted(_ words: [(text: String, confidence: Double, settled: Bool)]) -> Set<Int> {
        let keys = words.map { WordShape($0.text).core }
        let asked = words.indices.filter { index in
            let word = words[index]
            return !word.settled && DoubtPolicy.isHeardSurely(word.confidence)
                && word.confidence < vouchingScore && keys[index].contains(where: \.isLetter)
                && FunctionWords.isContent(keys[index])
        }
        // Romanised Hindi has content words no English embedding holds, so it would doubt every one of them.
        guard !asked.isEmpty, !WordCorrectionEngine.speaksHindi(keys) else { return [] }
        return embedding.withLock { embedding in
            guard let embedding else { return [] }
            let forms = keys.map { held(by: embedding, $0) }
            return Set(
                asked.filter { index in
                    guard let word = forms[index] else { return true }
                    let others = forms.indices.compactMap { other in
                        other == index || forms[other] == word ? nil : forms[other]
                    }
                    guard !others.isEmpty else { return false }
                    let nearest = others.map { embedding.distance(between: word, and: $0) }.min()
                    return (nearest ?? unknownDistance) > distanceLine
                })
        }
    }

    /// The form of the word the embedding holds, as spoken or in lower case, or `nil` when it holds neither.
    private static func held(by embedding: NLEmbedding, _ key: String) -> String? {
        guard !key.isEmpty else { return nil }
        if embedding.contains(key) { return key }
        let lowered = key.lowercased()
        return embedding.contains(lowered) ? lowered : nil
    }
}
