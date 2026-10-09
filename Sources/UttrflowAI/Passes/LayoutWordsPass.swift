import NaturalLanguage
public import UttrflowCore

/// Turns "new line", "new paragraph", "bullet point" and "number one" into layout, between words only.
public struct LayoutWordsPass: PieceCleaningPass {
    public static let id: PassID = .layoutWords
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    private let layout: LayoutPolicy
    private let insertionState: InsertionPoint.SentenceState

    /// The word that opens a numbered item. It has no row in `SpokenCommands.layout` because the number after it picks the mark.
    static let numbering = "number"

    public init(
        layout: LayoutPolicy = [.paragraphs, .lists], insertionPoint: InsertionPoint = .unknown
    ) {
        self.layout = layout
        self.insertionState = insertionPoint.sentenceState
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        let numbered = Set(live.indices.compactMap { Self.itemValue(at: $0, in: live, of: draft) })
        // Asked of the words as spoken, so an item already laid out cannot hide the run a later item belongs to.
        let corroborated = Set(
            live.indices.filter { isCorroborated(at: $0, in: live, of: draft, among: numbered) }
                .map { live[$0] })
        let labelledItems = labelledItems(in: live, of: draft, among: corroborated)
        var position = 0
        while position < live.count {
            guard
                let found = opening(mark(at: position, in: live, of: draft), at: position),
                position + found.length < live.count,
                isUsed(found, at: position, in: live, of: draft, among: corroborated),
                corroborated.contains(live[position])
            else {
                position += 1
                continue
            }
            if found.isList {
                removeClauseMarkBeforeList(at: position, in: live, from: &draft)
            }
            if let label = labelledItems[live[position]],
                let item = Self.itemNumber(at: position + 1, in: live, of: draft)
            {
                let labelText = WordShape.capitalised(draft.shape(at: label).core)
                // At the head of the text a labelled item has no line to break from, as a numbered item has none.
                let lineBreak = live.first == label ? "" : "\n"
                let written = "\(lineBreak)\(labelText) \(item.value)\(Draft.labelStop)"
                draft.replace(at: label, with: written, by: Self.id)
                for index in live[position..<position + found.length] { draft.remove(at: index, by: Self.id) }
                live.removeSubrange(position..<position + found.length)
                continue
            }
            // A break with nothing to break from writes no mark, so its words go rather than leave an empty word.
            if found.mark.isEmpty {
                draft.remove(at: live[position], by: Self.id)
            } else {
                draft.replace(at: live[position], with: found.mark, by: Self.id)
            }
            for index in live[position + 1..<position + found.length] {
                draft.remove(at: index, by: Self.id)
            }
            live.removeSubrange(position + 1..<position + found.length)
            position += 1
        }
        if layout.contains(.singleLine) { Self.joinOnOneLine(&draft, by: Self.id) }
        return draft
    }

    /// Lays every break and item mark on one line, writing the list separator at each boundary between items.
    static func joinOnOneLine(_ draft: inout Draft, by pass: PassID) {
        var items: [[Int]] = [[]]
        for index in draft.presentIndices {
            let word = draft.words[index]
            guard word.isLayoutMark else {
                items[items.count - 1].append(index)
                continue
            }
            let label = word.isListMark ? "" : word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !items[items.count - 1].isEmpty { items.append([]) }
            if label.isEmpty {
                draft.remove(at: index, by: pass)
            } else {
                draft.replace(at: index, with: label, by: pass)
                items[items.count - 1].append(index)
            }
        }
        let filled = items.filter { !$0.isEmpty }
        // A comma inside an item would blur its edges, so the items are then kept apart with semicolons.
        let holdsComma = filled.contains { item in
            item.dropLast().contains { draft.shape(at: $0).suffix.contains(",") }
        }
        let separator = holdsComma ? ";" : ","
        for item in filled.dropLast() {
            guard let last = item.last, !draft.shape(at: last).endsSentence else { continue }
            draft.replace(at: last, with: WordShape.marked(draft.words[last].text, with: separator), by: pass)
        }
    }

    /// Removes a comma or semicolon stranded before a list marker.
    private func removeClauseMarkBeforeList(at position: Int, in live: [Int], from draft: inout Draft) {
        guard position > 0 else { return }
        let previous = live[position - 1]
        let shape = draft.shape(at: previous)
        guard
            !shape.core.isEmpty,
            let clauseMark = shape.suffix.first(where: { ",;".contains($0) })
        else { return }
        let suffix = shape.suffix.filter { $0 != clauseMark }
        draft.replace(at: previous, with: shape.prefix + shape.core + suffix, by: Self.id)
    }

    /// Labels that repeat before a corroborated, consecutive sequence of numbered items.
    private func labelledItems(in live: [Int], of draft: Draft, among corroborated: Set<Int>) -> [Int: Int] {
        var groups: [String: [(marker: Int, label: Int, value: Int)]] = [:]
        for position in live.indices {
            guard let found = mark(at: position, in: live, of: draft), position + found.length < live.count,
                isUsed(found, at: position, in: live, of: draft, among: corroborated),
                corroborated.contains(live[position]),
                position > 0,
                let item = Self.itemNumber(at: position + 1, in: live, of: draft),
                !followsLayoutBreak(at: position - 1, in: live, of: draft),
                !draft.shape(at: live[position - 1]).endsSentence
            else { continue }
            let label = live[position - 1]
            groups[draft.shape(at: label).key, default: []].append(
                (marker: live[position], label: label, value: item.value))
        }
        return groups.values.reduce(into: [:]) { labels, items in
            guard items.count > 1,
                zip(items, items.dropFirst()).allSatisfy({ pair in pair.1.value == pair.0.value + 1 })
            else { return }
            for item in items { labels[item.marker] = item.label }
        }
    }

    /// A layout phrase immediately before an item is a break, not a repeated label.
    private func followsLayoutBreak(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        SpokenCommands.layout.contains { command in
            guard command.text.allSatisfy(\.isNewline) else { return false }
            let start = position - command.words.count + 1
            return start >= 0 && draft.spells(command.words, at: start, in: live)
        }
    }

    /// At the head, a break depends on the insertion point; an item number keeps its existing behavior.
    private func opening(
        _ found: (length: Int, mark: String, isList: Bool)?, at position: Int
    ) -> (length: Int, mark: String, isList: Bool)? {
        guard let found, position == 0 else { return found }
        guard found.mark.allSatisfy(\.isNewline) else { return found }
        switch insertionState {
        case .startOfText:
            return (found.length, "", found.isList)
        case .startOfSentence, .midSentence:
            return found
        case .unknown:
            return nil
        }
    }

    /// Whether the phrase is dictated layout rather than named; an item opening its sentence needs a mark. See `Docs/cleanup.md`.
    private func isUsed(
        _ found: (length: Int, mark: String, isList: Bool), at position: Int, in live: [Int], of draft: Draft,
        among corroborated: Set<Int>
    ) -> Bool {
        let length = found.length
        if position == 0, found.mark.allSatisfy(\.isNewline), insertionState != .unknown { return true }
        // Asked of the sentence, not the text, so a sentence before it cannot turn "number one is broken" into an item.
        guard position == 0 || draft.shape(at: live[position - 1]).endsSentence else {
            return Self.asksForLayout(at: position, spanning: length, in: live, of: draft)
        }
        // A break straight after a sentence's stop is how people dictate one: "full stop new paragraph".
        if position > 0, found.mark.allSatisfy(\.isNewline) { return true }
        let last = draft.shape(at: live[position + length - 1])
        return (last.endsClause && !last.endsSentence)
            || corroborated.contains(live[position])
    }

    /// Whether the layout phrase at `position`, inside its sentence, asks for layout rather than naming it.
    public static func asksForLayout(
        at position: Int, spanning length: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        var followsLayout = false
        for index in live[..<position].reversed() {
            // An item laid out at the head of the text has no line to break from, yet it is layout all the same.
            if draft.words[index].isLayoutMark
                || draft.words[index].edits.contains(where: { $0.by == Self.id && $0.to.hasPrefix("\n") })
            {
                followsLayout = true
                break
            }
            if draft.shape(at: index).endsSentence { break }
        }
        return !MentionGuard.isMentioned(
            at: position, spanning: length, in: live, of: draft, reach: MentionGuard.phraseReach,
            corroboratedByLayout: followsLayout,
        )
    }

    /// Whether a numbered item inside its sentence has a neighbouring item said beside it, since a lone one is a designator.
    private func isCorroborated(
        at position: Int, in live: [Int], of draft: Draft, among numbered: Set<Int>
    ) -> Bool {
        guard live.indices.contains(position) else { return true }
        guard draft.shape(at: live[position]).key == Self.numbering else {
            guard let found = mark(at: position, in: live, of: draft), found.isList else { return true }
            return isBulletSetOff(found, at: position, in: live, of: draft)
        }
        let insideSentence = position > 0 && !draft.shape(at: live[position - 1]).endsSentence
        guard position + 1 < live.count,
            let item = Self.itemNumber(at: position + 1, in: live, of: draft)
        else { return true }
        let hasAdjacentItem =
            (item.value > 1 && numbered.contains(item.value - 1))
            || (item.value < Int.max && numbered.contains(item.value + 1))
        guard hasAdjacentItem else {
            guard !insideSentence else { return false }
            let numberEnd = position + item.count
            guard live.indices.contains(numberEnd) else { return false }
            let lastNumber = draft.shape(at: live[numberEnd])
            return lastNumber.endsClause && !lastNumber.endsSentence
        }
        return isEligibleNumberedRun(at: item.value, in: live, of: draft)
    }

    /// Whether a bullet opens a line: the text's head, a mark before or after the phrase, or another bullet beside it.
    private func isBulletSetOff(
        _ found: (length: Int, mark: String, isList: Bool), at position: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        if position == 0 { return true }
        let before = draft.shape(at: live[position - 1])
        if before.endsClause && (!before.endsSentence || WordShape.trailsOff(before.suffix)) { return true }
        if draft.shape(at: live[position + found.length - 1]).endsClause { return true }
        return live.indices.contains { other in
            other != position
                && mark(at: other, in: live, of: draft).map { $0.isList && $0.length == found.length }
                    == true
                && draft.shape(at: live[other]).key != Self.numbering
        }
    }

    /// A lead-in and items without a stranded coordinator distinguish a list from a sentence.
    private func isEligibleNumberedRun(
        at value: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        let positionsByValue = Dictionary(
            live.indices.compactMap { position -> (Int, Int)? in
                guard let item = Self.itemValue(at: position, in: live, of: draft) else { return nil }
                return (item, position)
            }, uniquingKeysWith: { first, _ in first },
        )
        var first = value
        while first > 1, positionsByValue[first - 1] != nil { first -= 1 }
        var item = first
        var firstMarker: Int?
        var hasJoiningWord = false
        while let marker = positionsByValue[item] {
            if firstMarker == nil { firstMarker = marker }
            if marker > 0 {
                let previous = draft.shape(at: live[marker - 1]).key
                hasJoiningWord = hasJoiningWord || previous == "and" || previous == "or"
            }
            guard item < Int.max else { return false }
            item += 1
        }
        guard let firstMarker else { return false }
        return !hasJoiningWord && isLeadInBefore(firstMarker, in: live, of: draft)
    }

    /// A mid-sentence list starts after a lead-in, not after a running clause.
    private func isLeadInBefore(_ marker: Int, in live: [Int], of draft: Draft) -> Bool {
        guard marker > 0, !draft.shape(at: live[marker - 1]).endsSentence else { return true }
        let previous = draft.shape(at: live[marker - 1])
        // A colon introduces what follows it, whatever class the word it closes.
        if previous.suffix.hasSuffix(":") { return true }
        guard !["and", "or"].contains(previous.key) else { return false }
        if ["need", "are", "check"].contains(previous.key) { return true }
        let context = live[..<marker].map { draft.words[$0].text }.joined(separator: " ")
        guard let range = context.range(of: previous.core, options: .backwards) else { return false }
        return LexicalClass.tag(at: range.lowerBound, in: context) != .verb
    }

    /// Whether a numbered item opens at `position` and the item after it is said later, so the words are a list.
    static func opensList(at position: Int, in live: [Int], of draft: Draft) -> Bool {
        guard let value = itemValue(at: position, in: live, of: draft), value < Int.max else { return false }
        return live.indices.contains { $0 > position && itemValue(at: $0, in: live, of: draft) == value + 1 }
    }

    /// The number of the item "number" opens at `position`, or nil where no item opens.
    private static func itemValue(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        guard live.indices.contains(position), draft.shape(at: live[position]).key == Self.numbering,
            position + 1 < live.count
        else {
            return nil
        }
        return Self.itemNumber(at: position + 1, in: live, of: draft)?.value
    }

    /// A one-line field takes a spoken list too, written with separators instead of marks.
    private var allowsLists: Bool { layout.contains(.lists) || layout.contains(.singleLine) }

    /// The layout the words at `position` become: one of the fixed phrases, or a numbered item.
    private func mark(
        at position: Int, in live: [Int], of draft: Draft
    ) -> (
        length: Int, mark: String, isList: Bool
    )? {
        if let found = SpokenCommands.layout.first(where: {
            draft.spells($0.words, at: position, in: live) && (allowsLists || !$0.requiresLists)
        }) {
            // At the head of the text an item has no line to break from.
            let text =
                position == 0 && found.requiresLists
                ? String(found.text.drop(while: \.isNewline)) : found.text
            return (found.words.count, text, found.requiresLists)
        }
        guard draft.shape(at: live[position]).key == Self.numbering, position + 1 < live.count,
            allowsLists,
            let item = Self.itemNumber(at: position + 1, in: live, of: draft)
        else { return nil }
        let lineBreak = position == 0 ? "" : "\n"
        return (item.count + 1, "\(lineBreak)\(item.value). ", true)
    }

    /// The item number, spoken or already a numeral, and how many words it took. See `Docs/cleanup.md`.
    private static func itemNumber(
        at position: Int, in live: [Int], of draft: Draft
    ) -> (value: Int, count: Int)? {
        guard live.indices.contains(position) else { return nil }
        let key = draft.shape(at: live[position]).key
        if let digits = NumberWords.digits(key) {
            guard let value = Int(digits), value > 0 else { return nil }
            return (value, 1)
        }
        let keys = live[draft.sentenceRun(from: position, in: live)].map { draft.shape(at: $0).key }
        guard let spoken = NumberWords.cardinal(keys[...]), spoken.value > 0 else { return nil }
        return spoken
    }
}
