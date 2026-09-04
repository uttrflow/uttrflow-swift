import MLX
import MLXLMCommon

// The parts of token healing that touch the loaded model: reading its vocabulary and masking its logits.

extension TokenHealing.Vocabulary {
    /// More ids than any vocabulary has, so a tokenizer that answers every id still ends the read.
    static let mostTokens = 1_000_000

    /// Reads the whole vocabulary off the tokenizer, stopping at the first id it does not know; the turn ends on the tokenizer's end token, the configuration's, or any piece named as one.
    init(tokenizer: any MLXLMCommon.Tokenizer, endOfTurn: Set<String>, endingIds: Set<Int>) {
        var bytes: [[UInt8]] = []
        var ending = endingIds
        for id in 0..<Self.mostTokens {
            guard let piece = tokenizer.convertIdToToken(id) else { break }
            let written = Self.bytes(of: piece)
            if written.contains(0x0A) || id == tokenizer.eosTokenId || endOfTurn.contains(piece) {
                ending.insert(id)
            }
            bytes.append(written)
        }
        self.init(bytes: bytes, ending: ending)
    }
}

extension TokenHealing: LogitProcessor {
    mutating func prompt(_ prompt: MLXArray) {}

    func process(logits: MLXArray) -> MLXArray {
        guard let mask = mask(width: logits.dim(-1)) else { return logits }
        return logits + MLXArray(mask)
    }

    mutating func didSample(token: MLXArray) {
        guard !isFree else { return }
        let id = token.asArray(Int32.self).first.map(Int.init) ?? -1
        took(vocabulary.bytes.indices.contains(id) ? vocabulary.bytes[id] : [])
    }
}
