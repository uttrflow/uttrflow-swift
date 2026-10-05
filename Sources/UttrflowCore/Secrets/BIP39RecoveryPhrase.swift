import CryptoKit
import Foundation

enum BIP39RecoveryPhrase {
    private static let supportedWordCounts: Set<Int> = [12, 15, 18, 21, 24]
    private static let wordIndices = loadWordIndices()

    static func matches(_ text: String) -> Bool {
        guard wordIndices.count == 2_048 else { return false }

        var window: [UInt16] = []
        for rawWord in text.split(whereSeparator: \.isWhitespace) {
            let word = String(rawWord).trimmingCharacters(in: .punctuationCharacters)
            // A standalone positive integer is a position marker; other numeric text breaks the phrase.
            if !window.isEmpty, isNumberedListMarker(String(rawWord)) { continue }

            let normalizedWord = word.lowercased()
            guard !word.isEmpty,
                word.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
                let index = wordIndices[normalizedWord]
            else {
                window.removeAll(keepingCapacity: true)
                continue
            }

            window.append(index)
            if window.count > 24 { window.removeFirst() }
            if supportedWordCounts.contains(where: { count in
                window.count >= count && hasValidChecksum(Array(window.suffix(count)))
            }) {
                return true
            }
        }

        return false
    }

    private static func isNumberedListMarker(_ token: String) -> Bool {
        let number = token.trimmingCharacters(in: .punctuationCharacters)
        guard !number.isEmpty, number.first != "0" else { return false }
        return number.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func loadWordIndices() -> [String: UInt16] {
        guard let url = Bundle.module.url(forResource: "bip39-english", withExtension: "txt"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }

        let words = contents.split(whereSeparator: \.isNewline).filter {
            !$0.isEmpty && !$0.hasPrefix("#")
        }
        guard words.count == 2_048 else { return [:] }

        var indices: [String: UInt16] = [:]
        for (index, word) in words.enumerated() {
            indices[String(word)] = UInt16(index)
        }
        return indices.count == 2_048 ? indices : [:]
    }

    private static func hasValidChecksum(_ wordIndices: [UInt16]) -> Bool {
        let checksumLength = wordIndices.count / 3
        let entropyLength = wordIndices.count * 11 - checksumLength
        var entropy = [UInt8](repeating: 0, count: entropyLength / 8)
        var suppliedChecksum = 0

        for (wordPosition, wordIndex) in wordIndices.enumerated() {
            for bitPosition in 0..<11 {
                let bit = (Int(wordIndex) >> (10 - bitPosition)) & 1
                let position = wordPosition * 11 + bitPosition
                if position < entropyLength {
                    if bit == 1 {
                        entropy[position / 8] |= UInt8(1 << (7 - position % 8))
                    }
                } else {
                    suppliedChecksum = (suppliedChecksum << 1) | bit
                }
            }
        }

        let digest = Array(SHA256.hash(data: Data(entropy)))
        var expectedChecksum = 0
        for position in 0..<checksumLength {
            let bit = (digest[position / 8] >> (7 - position % 8)) & 1
            expectedChecksum = (expectedChecksum << 1) | Int(bit)
        }
        return suppliedChecksum == expectedChecksum
    }
}
