public import UttrflowCore

/// A word a pass took out that its grant does not cover, so the rewrite is still answerable for it.
public struct UnauthorisedRemoval: Sendable, Equatable {
    /// The pass that removed it.
    public let pass: PassID
    /// The word as it read when it was removed.
    public let text: String
}

/// Reads a draft's removals against what each pass may remove. See `Docs/cleanup.md`.
public enum RemovalAudit {
    /// How many words ahead the kept saying of a repetition may stand, the longest run `RepeatedPhrasePass` removes.
    static let repetitionReach = RepeatedPhrasePass.lengths.upperBound

    /// Every removal no grant covers, in the order the words were said; a pass the table does not name only converts.
    public static func unauthorised(
        in draft: Draft, grants: [PassID: RemovalGrant]
    ) -> [UnauthorisedRemoval] {
        var found: Set<Int> = []
        for index in draft.words.indices {
            guard case .removed(let pass) = draft.words[index].state else { continue }
            switch grants[pass] ?? .conversion {
            case .sound:
                if !isSound(draft.words[index].text) { found.insert(index) }
            case .repetition:
                if !isRepeated(at: index, in: draft) { found.insert(index) }
            case .conversion:
                if !isConverted(at: index, by: pass, in: draft) { found.insert(index) }
            case .retraction:
                found.formUnion(unretractedNegations(at: index, by: pass, in: draft))
            }
        }
        return found.sorted().compactMap { index in
            guard case .removed(let pass) = draft.words[index].state else { return nil }
            return UnauthorisedRemoval(pass: pass, text: draft.words[index].text)
        }
    }

    /// Whether a word can be a sound: it holds no digit and no second capital, which a numeral or an acronym does.
    static func isSound(_ text: String) -> Bool {
        !text.contains(where: \.isNumber) && text.count(where: \.isUppercase) < 2
    }

    /// Whether the same word stands among the words kept either side of it, where the saying that stayed is.
    private static func isRepeated(at index: Int, in draft: Draft) -> Bool {
        let key = draft.shape(at: index).key
        let kept = draft.words.indices.filter { draft.words[$0].isPresent }
        let before = kept.filter { $0 < index }.suffix(repetitionReach)
        let after = kept.filter { $0 > index }.prefix(repetitionReach)
        return (before + after).contains { draft.shape(at: $0).key == key }
    }

    /// Whether the pass wrote something into the run of words it touched around this one.
    private static func isConverted(at index: Int, by pass: PassID, in draft: Draft) -> Bool {
        let run = touchedRun(around: index, by: pass, in: draft)
        return run.contains { place in
            draft.words[place].edits.contains { $0.by == pass && $0.kind != .removed }
        }
    }

    /// The words either side of `index` the pass touched, stepping over words another pass removed.
    private static func touchedRun(around index: Int, by pass: PassID, in draft: Draft) -> [Int] {
        func belongs(_ place: Int) -> Bool {
            let word = draft.words[place]
            return !word.isPresent || word.edits.contains { $0.by == pass }
        }
        var start = index
        while start > draft.words.startIndex, belongs(start - 1) { start -= 1 }
        var end = index
        while end + 1 < draft.words.endIndex, belongs(end + 1) { end += 1 }
        return (start...end).filter { draft.words[$0].edits.contains { $0.by == pass } }
    }

    /// The one-word negating triggers of a retraction that took nothing back, its taken-back words said again unchanged.
    private static func unretractedNegations(at index: Int, by pass: PassID, in draft: Draft) -> [Int] {
        let run = touchedRun(around: index, by: pass, in: draft).filter { !draft.words[$0].isPresent }
        // The whole run is judged once, from its first word.
        guard run.first == index else { return [] }
        let keys = run.map { draft.shape(at: $0).key }
        guard let split = (1..<keys.count).first(where: { triggers(in: keys[$0...]) != nil }),
            let said = triggers(in: keys[split...])
        else { return [] }
        let takenBack = keys[..<split]
        let restart = draft.words.indices[((run.last ?? index) + 1)...]
            .filter { draft.words[$0].isPresent }.prefix(takenBack.count).map { draft.shape(at: $0).key }
        guard restart.elementsEqual(takenBack) else { return [] }
        var place = split
        var negations: [Int] = []
        for trigger in said {
            if trigger.count == 1, MeaningPreservationGuard.negatingWords.contains(trigger[0]) {
                negations.append(run[place])
            }
            place += trigger.count
        }
        return negations
    }

    /// The trigger phrases the words are spelled from end to end, longest first as `Restatement` reads them, or nil.
    private static func triggers(in keys: ArraySlice<String>) -> [[String]]? {
        var rest = keys
        var said: [[String]] = []
        while !rest.isEmpty {
            guard let trigger = Restatement.triggers.first(where: { rest.starts(with: $0) }) else {
                return nil
            }
            said.append(trigger)
            rest = rest.dropFirst(trigger.count)
        }
        return said
    }
}
