// The ordinary words each shipped technical term could be heard as, computed from the lists and never stored.

import UttrflowCore

/// One term's report line: the ordinary words its written or spoken forms sound like.
struct LexiconNeighbourLine: Sendable, Equatable {
    /// The term's written form.
    let id: String
    /// Ordinary words sharing a sound with the written form or a spoken form, sorted and without repeats.
    let neighbours: [String]
    /// Whether a written or spoken form is itself an ordinary word, the case a destination must limit.
    let isOrdinary: Bool
}

/// The validator's neighbour report over the technical lexicon. See `Docs/lexicon.md`.
enum LexiconNeighbours {
    /// One line per term, in file order.
    static func report(for terms: [TechnicalTerm] = TechnicalLexicon.terms) -> [LexiconNeighbourLine] {
        terms.map { term in
            let forms = [term.id] + term.spoken
            let near = forms.flatMap(GeneralVocabulary.wordsSounding(like:))
                .filter { word in !forms.contains { $0.lowercased() == word } }
            return LexiconNeighbourLine(
                id: term.id, neighbours: Array(Set(near)).sorted(),
                isOrdinary: forms.contains(where: GeneralVocabulary.isOrdinary))
        }
    }
}
