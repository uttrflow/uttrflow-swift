import CryptoKit
import Foundation

enum BIP39RecoveryPhrase {
    private static let supportedWordCounts: Set<Int> = [12, 15, 18, 21, 24]
    private static let wordIndices = loadWordIndices()
    private static let wordFingerprints = Set(wordIndices.keys.map { fingerprint($0.utf8) })

    /// Counts bytes visited by the cheap candidate scan; tests use it instead of wall-clock thresholds.
    @TaskLocal package static var prefilterTally: ScanTally?

    /// Counts bytes passed to the allocating checksum parser; tests prove ordinary prose skips it.
    @TaskLocal package static var candidateTally: ScanTally?

    static func matches(_ text: String) -> Bool {
        guard wordIndices.count == 2_048 else { return false }
        return scanCandidates(in: text)
    }

    private static func scanCandidates(in text: String) -> Bool {
        var bytesRead = 0
        defer { prefilterTally?.record(bytesRead) }

        var run = CandidateRun()
        let bytes = text.utf8
        var index = bytes.startIndex
        while index < bytes.endIndex {
            while index < bytes.endIndex, isTokenBoundary(bytes[index]) {
                bytes.formIndex(after: &index)
                bytesRead += 1
            }
            let start = index
            while index < bytes.endIndex, !isTokenBoundary(bytes[index]) {
                bytes.formIndex(after: &index)
                bytesRead += 1
            }
            guard start < index else { continue }
            let token = bytes[start..<index]
            if finishRunWhenNeeded(token, start: start, end: index, in: text, run: &run) { return true }
        }
        return matchesWords(in: run.substring(in: text))
    }

    private static func finishRunWhenNeeded<C: BidirectionalCollection>(
        _ token: C, start: String.Index, end: String.Index,
        in text: String, run: inout CandidateRun
    ) -> Bool where C.Element == UInt8 {
        if isRecoveryWord(token) {
            run.append(start: start, end: end)
            return false
        }
        if run.count > 0, isNumberedListMarker(token) {
            run.end = end
            return false
        }
        let matched = matchesWords(in: run.substring(in: text))
        run.clear()
        return matched
    }

    private static func matchesWords(in candidate: Substring?) -> Bool {
        guard let candidate else { return false }
        return matchesWords(in: candidate)
    }

    private static func matchesWords(in text: Substring) -> Bool {
        candidateTally?.record(text.utf8.count)
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

    private static func isRecoveryWord<C: BidirectionalCollection>(_ token: C) -> Bool
    where C.Element == UInt8 {
        var start = token.startIndex
        var end = token.endIndex
        while start < end, isASCIIPunctuation(token[start]) { start = token.index(after: start) }
        while start < end, isASCIIPunctuation(token[token.index(before: end)]) {
            end = token.index(before: end)
        }
        let count = token.distance(from: start, to: end)
        guard (3...8).contains(count) else { return false }
        let word = token[start..<end]
        guard word.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else { return false }
        return wordFingerprints.contains(fingerprint(word))
    }

    private static func isNumberedListMarker<C: BidirectionalCollection>(_ token: C) -> Bool
    where C.Element == UInt8 {
        var start = token.startIndex
        var end = token.endIndex
        while start < end, isASCIIPunctuation(token[start]) { start = token.index(after: start) }
        while start < end, isASCIIPunctuation(token[token.index(before: end)]) {
            end = token.index(before: end)
        }
        guard start < end, token[start] != 48 else { return false }
        return token[start..<end].allSatisfy { (48...57).contains($0) }
    }

    private static func isASCIIPunctuation(_ byte: UInt8) -> Bool {
        (33...47).contains(byte) || (58...64).contains(byte) || (91...96).contains(byte)
            || (123...126).contains(byte)
    }

    private static func fingerprint<C: Collection>(_ bytes: C) -> UInt64 where C.Element == UInt8 {
        bytes.reduce(14_695_981_039_346_656_037) { hash, byte in
            let lowercased = (65...90).contains(byte) ? byte + 32 : byte
            return (hash ^ UInt64(lowercased)) &* 1_099_511_628_211
        }
    }

    private static func isTokenBoundary(_ byte: UInt8) -> Bool {
        byte >= 128 || byte == 32 || (9...13).contains(byte)
    }

    private struct CandidateRun {
        var start: String.Index?
        var end: String.Index?
        var count = 0

        mutating func append(start: String.Index, end: String.Index) {
            if self.start == nil { self.start = start }
            self.end = end
            count += 1
        }

        func substring(in text: String) -> Substring? {
            guard let start, let end, count >= 12 else { return nil }
            return text[start..<end]
        }

        mutating func clear() {
            start = nil
            end = nil
            count = 0
        }
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
