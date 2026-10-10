// Builds a back-off n-gram model on the device from counted sentences, smoothed by absolute discounting.

import Foundation

extension NGramModel {
    /// The model of `sentences` counted up to `order`, each n-gram's discount backing off to the shorter history and the unigrams' to `<unk>`, so every history sums to 1.
    static func counted(_ sentences: [[String]], order: Int = maxOrder) -> NGramModel {
        let order = min(max(order, 1), maxOrder)
        var ids: [String: UInt32] = [unknownToken: 1]
        var counts: [[[UInt32]: Int]] = Array(repeating: [:], count: order + 1)
        for sentence in sentences {
            let wordIDs = sentence.filter { !$0.isEmpty }.map { word -> UInt32 in
                if let known = ids[word] { return known }
                guard ids.count < maxVocabulary else { return 1 }
                let next = UInt32(ids.count + 1)
                ids[word] = next
                return next
            }
            for length in 1...order where wordIDs.count >= length {
                for start in 0...(wordIDs.count - length) {
                    counts[length][Array(wordIDs[start..<(start + length)]), default: 0] += 1
                }
            }
        }
        var entries: [UInt64: NGramEntry] = [:]
        let unigramTotal = counts[1].values.reduce(0, +)
        guard unigramTotal > 0 else {
            return NGramModel(order: 1, ids: ids, entries: [key([1]): NGramEntry(log10Probability: 0)])
        }
        let unigramDiscount = discount(counts[1])
        var seenMass = 0.0
        for (gram, count) in counts[1] where gram != [1] {
            let probability = (Double(count) - unigramDiscount) / Double(unigramTotal)
            seenMass += probability
            entries[key(gram)] = NGramEntry(log10Probability: Float(log10(probability)))
        }
        entries[key([1])] = NGramEntry(
            log10Probability: Float(log10(max(1 - seenMass, .leastNormalMagnitude))))

        for length in 2...max(order, 2) where length <= order {
            let shorter = NGramModel(order: length - 1, ids: ids, entries: entries)
            let gramDiscount = discount(counts[length])
            var totals: [[UInt32]: (count: Int, types: Int, lowerMass: Double)] = [:]
            for (gram, count) in counts[length] {
                let history = Array(gram.dropLast())
                let lowerLog = shorter.backedOff(gram[gram.count - 1], Array(history.dropFirst()))
                let lower = pow(10, Double(lowerLog))
                totals[history, default: (0, 0, 0)].count += count
                totals[history, default: (0, 0, 0)].types += 1
                totals[history, default: (0, 0, 0)].lowerMass += lower
            }
            for (gram, count) in counts[length] {
                guard let total = totals[Array(gram.dropLast())] else { continue }
                let probability = (Double(count) - gramDiscount) / Double(total.count)
                entries[key(gram)] = NGramEntry(log10Probability: Float(log10(probability)))
            }
            for (history, total) in totals {
                guard let entry = entries[key(history)] else { continue }
                let leftover = gramDiscount * Double(total.types) / Double(total.count)
                let weight = leftover / max(1 - total.lowerMass, .leastNormalMagnitude)
                entries[key(history)] = NGramEntry(
                    log10Probability: entry.log10Probability, log10Backoff: Float(log10(weight)))
            }
        }
        return NGramModel(order: order, ids: ids, entries: entries)
    }

    /// The absolute discount for one order, `n1 / (n1 + 2 n2)` from how many n-grams were seen once and twice, or 0.5 without both.
    static func discount(_ counts: [[UInt32]: Int]) -> Double {
        let once = counts.values.count { $0 == 1 }
        let twice = counts.values.count { $0 == 2 }
        guard once > 0, twice > 0 else { return 0.5 }
        return Double(once) / Double(once + 2 * twice)
    }
}
