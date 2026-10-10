// Tests that every homophone class has exactly one owner and that a part-of-speech tagger does not earn a rule.
import NaturalLanguage
import Testing

@testable import UttrflowEval

@Suite("HomophoneOwnership")
struct HomophoneOwnershipTests {
    @Test func everyClassHasOneOwnerAndTheRulesOwnNone() {
        let table = HomophoneOwnership.table
        #expect(table.count == HomophoneCarriers.classes.count + HomophoneLexiconClasses.all.count)
        for (members, owner) in table {
            for member in members { #expect(HomophoneOwnership.owner(of: member) == owner) }
        }
        #expect(Set(table.flatMap(\.members)).count == table.map(\.members.count).reduce(0, +))
    }

    @Test func roleAndSenseClassesBelongToTheModel() {
        for word in [
            "their", "there", "they're", "its", "it's", "your", "you're", "then", "than", "lose", "loose",
        ] {
            #expect(HomophoneOwnership.owner(of: word) == .model)
        }
        #expect(HomophoneOwnership.owner(of: "unlisted") == nil)
    }

    @Test func aPlaceOnlyClassIsThePlaces() {
        let placeOnly = HomophoneOwnership.table.filter { $0.owner == .place }
        for entry in placeOnly {
            let deciders = (HomophoneCarriers.all + HomophoneCarriers.lexicon)
                .filter { entry.members.contains($0.spelling) }.map(\.decider)
            #expect(!deciders.contains(.role) && !deciders.contains(.sense))
        }
    }

    /// The lexical class `NLTagger` gives `word` in `sentence`.
    static func tag(_ sentence: String, word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        var found: String?
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            if sentence[range].lowercased() == word { found = tag?.rawValue }
            return found == nil
        }
        return found
    }

    @Test func partOfSpeechDoesNotSeparateTheRoleClassesAtNinetyNinePercent() {
        let carriers = HomophoneCarriers.all + HomophoneCarriers.lexicon
        let roles = carriers.filter {
            $0.decider == .role && HomophoneOwnership.owner(of: $0.spelling) == .model
        }
        var chosen = 0
        var right = 0
        for carrier in roles {
            let members =
                HomophoneCarriers.group(containing: carrier.spelling)
                ?? HomophoneLexiconClasses.all.first { $0.contains(carrier.spelling) } ?? []
            var tagsOf: [String: Set<String>] = [:]
            for other in roles where other != carrier && members.contains(other.spelling) {
                if let tag = Self.tag(other.filled(with: other.spelling), word: other.spelling) {
                    tagsOf[other.spelling, default: []].insert(tag)
                }
            }
            guard let seen = Self.tag(carrier.filled(with: carrier.spelling), word: carrier.spelling) else {
                continue
            }
            let matching = members.filter { tagsOf[$0]?.contains(seen) == true }
            guard matching.count == 1 else { continue }
            chosen += 1
            if matching[0] == carrier.spelling { right += 1 }
        }
        let precision = chosen == 0 ? 0 : Double(right) / Double(chosen)
        print("POS probe: chose \(chosen) of \(roles.count), right \(right), precision \(precision)")
        #expect(precision < 0.99, "a tagger separates the role classes: revisit Docs/cleanup.md")
    }
}
