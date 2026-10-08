import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowAI

/// One generated phrase, the numeral the pass must write for it, and the bucket it is counted in.
struct RoundTripCase {
    let bucket: String
    let spoken: String
    let expected: String
}

/// Generates spoken numbers in every value class and variant, with a fixed seed and case count.
enum RoundTripCorpus {
    static let seed = 3766
    static let casesPerBucket = 150

    static func all() -> [RoundTripCase] {
        var random = Seeded(seed: seed)
        var cases: [RoundTripCase] = []
        let styles = [
            SpokenStyle(), SpokenStyle(and: true), SpokenStyle(leadingA: true), SpokenStyle(hyphen: true),
        ]
        for style in styles {
            cases += (0..<casesPerBucket).map { _ in
                let value = scaled(&random)
                let spoken = NumberVerbaliser.cardinal(value, style: style)
                return RoundTripCase(
                    bucket: "cardinal/" + style.name, spoken: "we counted \(spoken) items",
                    expected: "we counted \(NumberVerbaliser.numeral(value)) items")
            }
            cases += (0..<casesPerBucket).map { _ in
                let value = Int.random(in: 10...199, using: &random)
                return RoundTripCase(
                    bucket: "ordinal/" + style.name,
                    spoken: "the \(NumberVerbaliser.ordinal(value, style: style)) floor",
                    expected: "the \(value)\(NumberVerbaliser.ordinalSuffix(value)) floor")
            }
        }
        for currency in ["dollars", "rupees", "euros"] {
            cases += (0..<casesPerBucket).map { _ in
                let value = scaled(&random)
                return RoundTripCase(
                    bucket: "currency/" + currency,
                    spoken: "it costs \(NumberVerbaliser.cardinal(value)) \(currency)",
                    expected: "it costs \(NumberVerbaliser.numeral(value)) \(currency)")
            }
        }
        for word in ["percent", "per cent"] {
            cases += (0..<casesPerBucket).map { _ in
                let value = Int.random(in: 10...100, using: &random)
                return RoundTripCase(
                    bucket: "percent/" + word, spoken: "about \(NumberVerbaliser.cardinal(value)) \(word)",
                    expected: "about \(value)%")
            }
        }
        cases += (0..<casesPerBucket).map { _ in
            let whole = Int.random(in: 10...999, using: &random)
            let fraction = (0..<Int.random(in: 1...3, using: &random)).map { _ in
                Int.random(in: 0...9, using: &random)
            }
            let spokenFraction = fraction.map { NumberVerbaliser.units[$0] }.joined(separator: " ")
            return RoundTripCase(
                bucket: "decimal/point",
                spoken: "it read \(NumberVerbaliser.cardinal(whole)) point \(spokenFraction)",
                expected: "it read \(whole).\(fraction.map(String.init).joined())")
        }
        for zero in ["oh", "zero", "and"] {
            cases += (0..<casesPerBucket).map { _ in
                let value = Int.random(in: 1900...2099, using: &random)
                return RoundTripCase(
                    bucket: "year/" + zero, spoken: "in \(NumberVerbaliser.year(value, zero: zero))",
                    expected: "in \(value)")
            }
        }
        for zero in ["oh", "zero"] {
            cases += (0..<casesPerBucket).map { _ in
                let hour = Int.random(in: 1...12, using: &random)
                let minute = Int.random(in: 1...59, using: &random)
                let spoken = NumberVerbaliser.cardinal(hour) + " " + NumberVerbaliser.pair(minute, zero: zero)
                let padded = minute < 10 ? "0\(minute)" : String(minute)
                return RoundTripCase(
                    bucket: "time/" + zero, spoken: "at \(spoken) pm", expected: "at \(hour):\(padded) pm")
            }
            cases += (0..<casesPerBucket).map { _ in
                let digits = (0..<Int.random(in: 3...10, using: &random)).map { _ in
                    Int.random(in: 0...9, using: &random)
                }
                let spoken = digits.map { $0 == 0 ? zero : NumberVerbaliser.units[$0] }.joined(separator: " ")
                return RoundTripCase(
                    bucket: "digits/" + zero, spoken: "the code is \(spoken)",
                    expected: "the code is \(digits.map(String.init).joined())")
            }
        }
        return cases
    }

    /// Phrases whose number words are not a number; the pass must return them unchanged.
    static let idioms = [
        "it's a twenty four seven service", "it's fifty fifty", "one of them came", "give me a second",
        "I lost a pound", "she was on cloud nine", "two of a kind", "we finished in no time",
    ]

    /// A value spread across every magnitude from ten to a trillion.
    static func scaled(_ random: inout Seeded) -> Int {
        let magnitude = Int.random(in: 1...12, using: &random)
        var upper = 1
        for _ in 0..<magnitude { upper *= 10 }
        return Int.random(in: 10...max(10, upper), using: &random)
    }
}

@Suite("Number grammar round trip")
struct NumberRoundTripTests {
    /// Buckets that fail today and the most cases each may fail; a count may fall and never rise.
    static let knownFailures: [String: (count: Int, issue: Int)] = [
        "cardinal/a": (5, 4033), "cardinal/hyphen": (121, 4085),
        "ordinal/a": (88, 3628), "ordinal/and": (32, 4452), "ordinal/hyphen": (93, 4085),
        "ordinal/plain": (30, 3628),
        "year/and": (8, 4058), "year/oh": (5, 4058), "year/zero": (6, 4058),
    ]

    @Test(
        "a number written out in words reads back as its numeral", arguments: [NumberPolicy.fromTen, .always])
    func roundTrip(policy: NumberPolicy) {
        let pass = NumberFormsPass(policy: policy)
        var failures: [String: [RoundTripCase]] = [:]
        var totals: [String: Int] = [:]
        for item in RoundTripCorpus.all() {
            totals[item.bucket, default: 0] += 1
            if cleaned(item.spoken, by: pass) != item.expected {
                failures[item.bucket, default: []].append(item)
            }
        }
        for bucket in totals.keys.sorted() {
            let failed = failures[bucket] ?? []
            let allowed = Self.knownFailures[bucket]?.count ?? 0
            print(
                "round trip \(policy) \(bucket): \(totals[bucket, default: 0] - failed.count)/\(totals[bucket, default: 0])"
            )
            let shortest = failed.min { $0.spoken.count < $1.spoken.count }
            #expect(
                failed.count <= allowed,
                "\(bucket): \(failed.count) failures, \(allowed) known; shortest \(shortest.map { "\"\($0.spoken)\" -> \"\(cleaned($0.spoken, by: pass))\", want \"\($0.expected)\"" } ?? "")"
            )
        }
    }

    @Test("number words that are not a number come back unchanged", arguments: RoundTripCorpus.idioms)
    func idiom(phrase: String) {
        #expect(cleaned(phrase, by: NumberFormsPass(policy: .fromTen)) == phrase)
    }

    @Test("the verbaliser says values the way the pass's own examples do")
    func verbaliser() {
        #expect(NumberVerbaliser.cardinal(105, style: SpokenStyle(and: true)) == "one hundred and five")
        #expect(
            NumberVerbaliser.cardinal(121, style: SpokenStyle(leadingA: true, hyphen: true))
                == "a hundred twenty-one")
        #expect(NumberVerbaliser.cardinal(2_000_005, style: SpokenStyle(and: true)) == "two million and five")
        #expect(NumberVerbaliser.ordinal(42) == "forty second")
        #expect(NumberVerbaliser.ordinal(30) == "thirtieth")
        #expect(NumberVerbaliser.year(1905, zero: "oh") == "nineteen oh five")
        #expect(NumberVerbaliser.year(2005, zero: "and") == "two thousand and five")
        #expect(NumberVerbaliser.numeral(15000) == "15,000")
        #expect(NumberVerbaliser.numeral(9000) == "9000")
    }
}
