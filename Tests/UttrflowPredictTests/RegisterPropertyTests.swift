import Testing

@testable import UttrflowPredict

/// Words the person or the screen might use, prose and command alike.
private let words = [
    "on", "my", "way", "running", "late", "sorry", "yes", "kal", "milenge", "bhai", "the", "release", "goes",
    "out", "thursday", "git", "commit", "-m", "ls", "-la", "docker", "compose", "SELECT", "*", "FROM",
    "users",
    "WHERE", "id=3", "🙏", "नमस्ते", "&&", "||", "->", "x.y()", "Deploy", "We", "Nobody",
]

/// One moment built from a seed: a screen, the person's lines, the text before, and what is typed.
struct RegisterCase: Sendable, CustomTestStringConvertible {
    let seed: Int
    let situation: GenerationSituation
    let typed: String

    init(seed: Int) {
        var random = Seeded(seed: seed)
        self.seed = seed
        let screen: String? =
            random.chance(0.25)
            ? nil
            : (0..<Int.random(in: 0...12, using: &random)).map { _ in
                random.chance(0.15)
                    ? random.pick(["", "   ", "\t"]) : RegisterCase.line(&random, long: random.chance(0.3))
            }.joined(separator: random.pick(["\n", "\r\n"]))
        let own = (0..<Int.random(in: 0...15, using: &random)).map { _ in
            RegisterCase.line(&random, long: random.chance(0.2))
        }
        situation = GenerationSituation(
            application: "App", preceding: random.chance(0.5) ? RegisterCase.line(&random, long: true) : nil,
            surroundings: screen, recentLines: own, isMultiline: random.chance(0.5))
        typed = RegisterCase.line(&random, long: false)
    }

    var testDescription: String { "seed \(seed)" }

    /// One line, sometimes long, sometimes opened with a capital and closed with sentence punctuation.
    private static func line(_ random: inout Seeded, long: Bool) -> String {
        let count = long ? Int.random(in: 30...80, using: &random) : Int.random(in: 1...8, using: &random)
        var text = (0..<count).map { _ in random.pick(words) }.joined(separator: " ")
        if random.chance(0.4) { text = text.prefix(1).uppercased() + text.dropFirst() }
        if random.chance(0.4) { text += random.pick([".", "!", "?"]) }
        return text
    }
}

/// A register built directly rather than inferred, so the hints are tried on every combination of facts.
struct RegisterFacts: Sendable, CustomTestStringConvertible {
    let seed: Int
    let register: Register

    init(seed: Int) {
        var random = Seeded(seed: seed)
        self.seed = seed
        register = Register(
            isMultiline: random.chance(0.5),
            typicalLength: random.chance(0.3) ? nil : Int.random(in: 0...600, using: &random),
            isConversational: random.chance(0.5), symbolShare: Double.random(in: 0...1, using: &random),
            usesSentenceCase: random.pick([nil, true, false]))
    }

    var testDescription: String { "seed \(seed)" }
}

private let moments = (0..<400).map(RegisterCase.init)
private let facts = (0..<300).map(RegisterFacts.init)

/// Whether a value sits in the middle of the values: at most half are below it and at most half above.
private func isMedian(_ value: Int, of values: [Int]) -> Bool {
    values.contains(value) && values.filter { $0 < value }.count * 2 <= values.count
        && values.filter { $0 > value }.count * 2 <= values.count
}

@Suite("Reading the register off random moments")
struct RegisterPropertyTests {
    @Test("The token budget always sits inside the range, whatever the register.", arguments: moments)
    func theBudgetStaysInRange(moment: RegisterCase) {
        let register = Register.infer(from: moment.situation, typed: moment.typed)
        #expect(Register.tokenRange.contains(register.maxTokens))
        if let typical = register.typicalLength {
            #expect(register.maxTokens == min(max(typical / 2, 24), 96))
        } else if register.symbolShare > Register.symbolicShare {
            #expect(register.maxTokens == 32)
        } else {
            #expect(register.maxTokens == (register.isConversational ? 48 : 64))
        }
    }

    @Test(
        "The typical length is a median of the person's lines, else of the screen's turns in a conversation.",
        arguments: moments)
    func typicalLengthIsAMedian(moment: RegisterCase) {
        let register = Register.infer(from: moment.situation, typed: moment.typed)
        let own = moment.situation.recentLines.map(\.count)
        let screen = Register.lines(of: moment.situation.surroundings).map(\.count)
        if !own.isEmpty {
            #expect(register.typicalLength.map { isMedian($0, of: own) } == true)
        } else if register.isConversational {
            #expect(register.typicalLength.map { isMedian($0, of: screen) } == true)
        } else {
            #expect(register.typicalLength == nil)
        }
    }

    @Test(
        "A screen is a conversation when it has enough lines and most of them are short.", arguments: moments)
    func conversationsAreShortTurns(moment: RegisterCase) {
        let register = Register.infer(from: moment.situation, typed: moment.typed)
        let lines = (moment.situation.surroundings ?? "").split(whereSeparator: \.isNewline).filter {
            $0.contains { !$0.isWhitespace }
        }
        let short = lines.filter { $0.count < Register.conversationLineLength }.count
        let expected =
            lines.count >= Register.conversationLines && Double(short) / Double(max(lines.count, 1)) >= 0.6
        #expect(register.isConversational == expected)
    }

    @Test(
        "The symbol share is a share, computed over the text before, the line, and the person's lines.",
        arguments: moments)
    func symbolShareIsAShare(moment: RegisterCase) {
        let register = Register.infer(from: moment.situation, typed: moment.typed)
        #expect((0.0...1.0).contains(register.symbolShare))
        let visible = ([moment.situation.preceding ?? "", moment.typed] + moment.situation.recentLines)
            .joined()
            .filter { !$0.isWhitespace }
        let symbols = visible.filter { !$0.isLetter && !$0.isNumber }.count
        let expected = visible.isEmpty ? 0 : Double(symbols) / Double(visible.count)
        #expect(register.symbolShare == expected)
    }

    @Test(
        "Sentence case is read off the person's lines alone, and is unknown until they have written some.",
        arguments: moments)
    func sentenceCaseComesFromTheirLines(moment: RegisterCase) {
        let register = Register.infer(from: moment.situation, typed: moment.typed)
        let own = moment.situation.recentLines
        guard !own.isEmpty else {
            #expect(register.usesSentenceCase == nil)
            return
        }
        let sentences = own.filter { line in
            guard let first = line.first, let last = line.last else { return false }
            return first.isUppercase && ".!?".contains(last)
        }.count
        #expect(register.usesSentenceCase == (Double(sentences) / Double(own.count) >= 0.5))
        #expect((0.0...1.0).contains(Register.sentenceCaseShare(of: own)))
    }

    @Test(
        "The hints never contradict one another, and name only the facts the register holds.",
        arguments: facts)
    func hintsNeverContradict(facts: RegisterFacts) {
        let register = facts.register
        let hints = register.hints
        let formal = hints.contains("this person writes in full sentences with punctuation")
        let casual = hints.contains("this person writes casually, without sentence punctuation")
        let symbolic = hints.contains("the text here is commands, code or queries rather than prose")
        #expect(!(formal && casual))
        #expect(!(symbolic && (formal || casual)))
        #expect(symbolic == (register.symbolShare > Register.symbolicShare))
        #expect(hints.first == (register.isMultiline ? "a multi-line field" : "a single-line field"))
        #expect(hints.contains { $0.hasPrefix("lines here run about") } == (register.typicalLength != nil))
        #expect(
            hints.contains("a conversation is on screen and the line answers its last message")
                == register.isConversational)
        #expect((formal || casual) == (!symbolic && register.usesSentenceCase != nil))
        #expect(Set(hints).count == hints.count)
        #expect(Register.tokenRange.contains(register.maxTokens))
    }
}
