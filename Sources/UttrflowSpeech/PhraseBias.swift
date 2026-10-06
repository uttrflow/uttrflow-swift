// The user's words as a decode-time nudge: a word the decoder has begun is helped to finish.
import CoreML
import WhisperKit

/// Helps the decoder finish a dictionary word it has already begun. See `Docs/speech-phrase-bias.md`.
struct PhraseBias: Equatable {
    /// Log-odds added to a token that continues a begun word; zero turns the bias off.
    let strength: Float
    /// Each word's tokens as spelled mid-sentence, kept only when there is a second token to help.
    let phrases: [[Int]]

    /// The strongest nudge allowed, so no setting can outvote what the audio says.
    static let maximumStrength: Float = 4

    /// A next token the decoder already gives this probability is heard, and is never outvoted.
    static let protectedProbability: Float = 0.9

    /// The bias towards `words`, as packed in the prompt, spelled by `tokenizer`.
    init(words: [String], using tokenizer: some PromptTokenizer, strength: Float) {
        self.strength = min(max(strength, 0), Self.maximumStrength)
        phrases = words.map { tokenizer.encode(text: " " + $0).filter { $0 < tokenizer.firstSpecialToken } }
            .filter { $0.count > 1 }
    }

    /// Whether any word can be helped at all.
    var isActive: Bool { strength > 0 && !phrases.isEmpty }

    /// The tokens that would continue a word whose first tokens end `sampled`; never a word's first token.
    func continuations(after sampled: [Int]) -> Set<Int> {
        var next: Set<Int> = []
        for phrase in phrases {
            for begun in 1..<phrase.count where begun <= sampled.count {
                if sampled.suffix(begun).elementsEqual(phrase.prefix(begun)) {
                    next.insert(phrase[begun])
                }
            }
        }
        return next
    }

    /// `scores` with `continuing` raised by ``strength``, or unchanged when the decoder is already sure of another token.
    func biased(_ scores: [Float], continuing: Set<Int>) -> [Float] {
        let valid = continuing.filter { scores.indices.contains($0) }
        guard strength > 0, !valid.isEmpty, let top = scores.indices.max(by: { scores[$0] < scores[$1] })
        else {
            return scores
        }
        let peak = scores[top]
        guard peak.isFinite else { return scores }
        let mass = scores.reduce(Float(0)) { $1.isFinite ? $0 + exp($1 - peak) : $0 }
        // The top token's probability is 1 / mass; a confidently heard word is left alone.
        if !valid.contains(top), 1 / mass >= Self.protectedProbability {
            return scores
        }
        var out = scores
        for token in valid where out[token].isFinite {
            out[token] += strength
        }
        return out
    }

    /// The scores before ``biased(_:continuing:)`` turned them into `observed`; exactly one reading is consistent.
    func unbiased(_ observed: [Float], continuing: Set<Int>) -> [Float] {
        var lowered = observed
        for token in continuing where lowered.indices.contains(token) && lowered[token].isFinite {
            lowered[token] -= strength
        }
        // Lowering only the continuations cannot turn a skipped step into an applied one, so this decides it.
        return biased(lowered, continuing: continuing) == lowered ? observed : lowered
    }
}

/// ``PhraseBias`` at each decode step, deriving its state from the tokens alone so concurrent windows share it safely.
final class PhraseBiasFilter: LogitsFiltering {
    let bias: PhraseBias
    /// Where sampling begins, past the forced prompt.
    let sampleBegin: Int
    /// Tokens from here up are timestamps and instructions, skipped when matching a word.
    let firstSpecialToken: Int

    init(bias: PhraseBias, sampleBegin: Int, firstSpecialToken: Int) {
        self.bias = bias
        self.sampleBegin = sampleBegin
        self.firstSpecialToken = firstSpecialToken
    }

    /// The tokens this step would help, given the history it is handed.
    func continuations(after tokens: [Int]) -> Set<Int> {
        guard tokens.count > sampleBegin else { return [] }
        return bias.continuations(after: tokens[sampleBegin...].filter { $0 < firstSpecialToken })
    }

    /// `observed` as the model scored it, before any raise from this filter.
    func unbiased(_ observed: [Float], withTokens tokens: [Int]) -> [Float] {
        let next = continuations(after: tokens)
        return next.isEmpty ? observed : bias.unbiased(observed, continuing: next)
    }

    func filterLogits(_ logits: MLMultiArray, withTokens tokens: [Int]) -> MLMultiArray {
        let next = continuations(after: tokens)
        guard !next.isEmpty else { return logits }
        let count = logits.count
        switch logits.dataType {
        case .float16:
            let pointer = logits.dataPointer.bindMemory(to: Float16.self, capacity: count)
            let scores = (0..<count).map { Float(pointer[$0]) }
            let raised = bias.biased(scores, continuing: next)
            for token in next where scores.indices.contains(token) {
                pointer[token] = Float16(raised[token])
            }
        case .float32:
            let pointer = logits.dataPointer.bindMemory(to: Float.self, capacity: count)
            let scores = (0..<count).map { pointer[$0] }
            let raised = bias.biased(scores, continuing: next)
            for token in next where scores.indices.contains(token) {
                pointer[token] = raised[token]
            }
        default:
            break
        }
        return logits
    }
}
