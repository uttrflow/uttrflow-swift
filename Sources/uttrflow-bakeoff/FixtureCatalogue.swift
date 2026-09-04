import UttrflowEval
import UttrflowLocalModel
import UttrflowPredict

/// One place lines are typed, and the register every line there inherits, multiplied by its lines and their cuts.
struct Scenario {
    let category: String
    let name: String
    let situation: GenerationSituation
    /// Where each line is cut unless the line says otherwise.
    let cuts: [LineCut]
    /// How much a cut determines unless the line says otherwise.
    let determinacy: Determinacy
    let band: ClosedRange<Int>
    let forbidden: [String]
    /// Lines typed here that are never cut themselves, only counted when they share a cut's typed text.
    let known: [String]
    let lines: [Line]

    init(
        category: String, name: String, situation: GenerationSituation, cuts: [LineCut],
        determinacy: Determinacy,
        band: ClosedRange<Int>, forbidden: [String] = [], known: [String] = [], lines: [Line]
    ) {
        self.category = category
        self.name = name
        self.situation = situation
        self.cuts = cuts
        self.determinacy = determinacy
        self.band = band
        self.forbidden = forbidden
        self.known = known
        self.lines = lines
    }

    /// Every cut of every line here as a fixture named `category/scenario/line/cutN`, slugs made distinct.
    var fixtures: [Fixture] {
        let register = CutRegister(
            band: band, forbidden: forbidden, siblings: lines.map(\.text) + known,
            minimumTyped: MLXCandidateScorer.minimumTypedLength)
        var slugs: [String: Int] = [:]
        return lines.flatMap { line -> [Fixture] in
            var cut = line.cutLine(cuts: cuts, determinacy: determinacy)
            let seen = slugs[cut.slug, default: 0] + 1
            slugs[cut.slug] = seen
            if seen > 1 {
                cut = CutLine(
                    cut.text, slug: "\(cut.slug)-\(seen)", cuts: cut.cuts, determinacy: cut.determinacy)
            }
            return cut.cases(in: register).map {
                Fixture(
                    "\(category)/\(name)/\($0.name)", situation, typed: $0.typed, expectation: $0.expectation)
            }
        }
    }
}

/// One full line as typed here, differing from the scenario only where it says so.
struct Line: ExpressibleByStringLiteral {
    let text: String
    let slug: String?
    let cuts: [LineCut]?
    let determinacy: Determinacy?

    init(_ text: String, slug: String? = nil, cuts: [LineCut]? = nil, determinacy: Determinacy? = nil) {
        self.text = text
        self.slug = slug
        self.cuts = cuts
        self.determinacy = determinacy
    }

    init(stringLiteral text: String) {
        self.init(text)
    }

    /// The line with the scenario's cuts and determinacy filled in wherever it left them unsaid.
    func cutLine(cuts defaults: [LineCut], determinacy fallback: Determinacy) -> CutLine {
        CutLine(text, slug: slug, cuts: cuts ?? defaults, determinacy: determinacy ?? fallback)
    }
}

extension Determinacy {
    /// The rest of a shell word, where a path's segments count as words too.
    static let command = Determinacy.segment(until: [" ", "/"])
    /// The rest of a SQL token, stopped by the punctuation a query wraps names in.
    static let query = Determinacy.segment(until: [" ", ",", ";", "(", ")"])
    /// The rest of a URL's host or path segment.
    static let address = Determinacy.segment(until: ["/", "?", "&", "=", " "])
    /// The rest of a word in prose, stopped by the punctuation a sentence ends or pauses on.
    static let prose = Determinacy.segment(until: [" ", ".", ",", "!", "?", ";", ":"])
    /// The rest of an identifier in code, stopped by the brackets and operators around it.
    static let code = Determinacy.segment(until: [" ", "(", ")", "{", "}", "[", "]", ".", ",", ":", ";", "="])
}

extension [LineCut] {
    /// The cuts a command is measured at: after the program, one and a few letters into its verb, and after it.
    static let command: [LineCut] = [.afterWord(1), .intoWord(2, by: 1), .midWord(2), .afterWord(2)]
    /// The cuts prose is measured at: after the first word, inside and after the second, inside the third.
    static let prose: [LineCut] = [.afterWord(1), .midWord(2), .afterWord(2), .midWord(3)]
    /// The cuts a query is measured at, past its opening keyword and object.
    static let query: [LineCut] = [.afterWord(2), .midWord(3), .afterWord(3), .midWord(4)]
    /// The cuts a clause on its own line is measured at.
    static let clause: [LineCut] = [.midWord(1), .afterWord(1), .midWord(2)]
    /// The cuts a URL is measured at: into the host, at its end, into the path.
    static let address: [LineCut] = [.characters(3), .characters(5), .characters(9), .characters(14)]
    /// The cuts a one- or two-word entry is measured at.
    static let entry: [LineCut] = [.characters(2), .midWord(1), .afterWord(1), .midWord(2)]
}

/// Every generated fixture, one list per register, beside the hand-written ones in `Fixture.handwritten`.
enum FixtureCatalogue {
    static let all: [Fixture] = scenarios.flatMap(\.fixtures)

    static let scenarios: [Scenario] = terminal + sql + url + chat + mail + notes + code + robust
}
