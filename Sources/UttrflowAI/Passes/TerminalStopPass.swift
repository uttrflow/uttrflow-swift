public import UttrflowCore

/// Adds or takes back the final full stop the way the formatter's stop policy and layout say.
public struct TerminalStopPass: WholeTextCleaningPass {
    public static let id: PassID = .terminalStop
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    public let policy: TerminalStopPolicy
    public let layout: LayoutPolicy
    public let insertionPoint: InsertionPoint
    public let destination: Destination?

    public init(
        policy: TerminalStopPolicy = .always, layout: LayoutPolicy = .paragraphs,
        insertionPoint: InsertionPoint = .unknown, destination: Destination? = nil
    ) {
        self.policy = policy
        self.layout = layout
        self.insertionPoint = insertionPoint
        self.destination = destination
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        if layout.contains(.singleLine) { LayoutWordsPass.joinOnOneLine(&draft, by: Self.id) }
        if layout.contains(.paragraphs), policy != .never {
            Self.stopParagraphs(&draft, destination: destination)
        }
        Self.separateLeadingReviewTag(&draft, layout: layout)
        Self.separateLeadingQuestionOpener(&draft, layout: layout)
        Self.separateTrailingRequest(&draft, layout: layout)
        Self.separateTrailingTag(&draft, layout: layout)
        Self.separateHindiAsides(&draft, layout: layout)
        guard let last = draft.presentIndices.last, !draft.words[last].isLayoutMark else { return draft }
        let word = draft.words[last].text
        if destination == .email, Self.isEmailGreetingOrSignOff(draft) {
            draft.replace(at: last, with: WordShape.withoutTrailingStop(word), by: Self.id)
            return draft
        }
        let finished: String
        switch policy {
        case .always:
            finished = finishedLast(word, in: draft)
        case .never:
            finished = WordShape.withoutTrailingStop(word)
        case .offForShortMessages(let sentences):
            let stopped = finishedLast(word, in: draft)
            finished =
                Self.sentenceCount(draft.text) <= sentences ? WordShape.withoutTrailingStop(stopped) : stopped
        }
        draft.replace(at: last, with: finished, by: Self.id)
        return draft
    }

    /// Separates an unmarked trailing request from the statement before it.
    private static func separateTrailingRequest(_ draft: inout Draft, layout: LayoutPolicy) {
        guard layout.contains(.paragraphs) else { return }
        let live = draft.presentIndices
        let shapes = live.map { draft.shape(at: $0) }
        guard let start = QuestionShape.trailingRequestStart(in: shapes), start > 0,
            !draft.words[live[start - 1]].isLayoutMark,
            !shapes[start - 1].suffix.contains(where: { ".!?;,:".contains($0) })
        else { return }
        let index = live[start - 1]
        draft.replace(at: index, with: WordShape.marked(draft.words[index].text, with: ","), by: id)
    }

    /// Sets off a review label said first, "nit spelling" → "Nit: spelling", with a colon.
    private static func separateLeadingReviewTag(_ draft: inout Draft, layout: LayoutPolicy) {
        guard layout.contains(.paragraphs) else { return }
        let live = draft.presentIndices.filter { !draft.shape(at: $0).key.isEmpty }
        guard let first = live.first, !draft.words[first].isLayoutMark,
            ReviewTag.leads(live.prefix(3).map { draft.shape(at: $0) })
        else { return }
        draft.replace(at: first, with: WordShape.marked(draft.words[first].text, with: ":"), by: id)
    }

    /// Sets off the address or multiword lead-in before a direct question.
    private static func separateLeadingQuestionOpener(_ draft: inout Draft, layout: LayoutPolicy) {
        guard layout.contains(.paragraphs) else { return }
        let live = draft.presentIndices
        let start = live.indices.dropLast().lastIndex { position in
            let index = live[position]
            guard !draft.words[index].isLayoutMark else { return true }
            return Abbreviations.endsSentence(
                draft.words[index].text, followedBy: draft.words[live[position + 1]].text
            )
        }
        let sentence = Array(live[(start.map { $0 + 1 } ?? 0)...])
        let shapes = sentence.map { draft.shape(at: $0) }
        guard let opener = QuestionShape.leadingQuestionOpenerIndex(in: shapes),
            !shapes[opener].suffix.contains(where: { ".!?;,:".contains($0) })
        else { return }
        let index = sentence[opener]
        draft.replace(at: index, with: WordShape.marked(draft.words[index].text, with: ","), by: id)
    }

    /// Separates a closing tag from the clause it asks about.
    private static func separateTrailingTag(_ draft: inout Draft, layout: LayoutPolicy) {
        guard layout.contains(.paragraphs) else { return }
        let live = draft.presentIndices
        let shapes = live.map { draft.shape(at: $0) }
        guard let start = QuestionShape.trailingTagStart(in: shapes), start > 0,
            !shapes[start - 1].suffix.contains(",")
        else { return }
        let index = live[start - 1]
        draft.replace(at: index, with: WordShape.marked(draft.words[index].text, with: ","), by: id)
    }

    /// Sets off an English aside opening or closing a Hindi sentence, "actually mujhe nahi pata" → "actually, mujhe nahi pata".
    private static func separateHindiAsides(_ draft: inout Draft, layout: LayoutPolicy) {
        guard layout.contains(.paragraphs) else { return }
        for sentence in sentences(in: draft) {
            let keys = sentence.map { draft.shape(at: $0).key }
            guard keys.count >= 3 else { continue }
            if AsideWords.holds(keys[0], at: .opening), AsideWords.areHindiClause(Array(keys.dropFirst())) {
                setOff(sentence[0], in: &draft)
            }
            if AsideWords.holds(keys[keys.count - 1], at: .closing),
                AsideWords.areHindiClause(Array(keys.dropLast()))
            {
                setOff(sentence[sentence.count - 2], in: &draft)
            }
        }
    }

    /// Puts a comma after the word unless it already carries a mark.
    private static func setOff(_ index: Int, in draft: inout Draft) {
        guard !draft.shape(at: index).suffix.contains(where: { ".!?;,:".contains($0) }) else { return }
        draft.replace(at: index, with: WordShape.marked(draft.words[index].text, with: ","), by: id)
    }

    /// The spoken words of each sentence, split at sentence ends and layout marks.
    private static func sentences(in draft: Draft) -> [[Int]] {
        let live = draft.presentIndices
        var sentences: [[Int]] = [[]]
        for (position, index) in live.enumerated() {
            if draft.words[index].isLayoutMark {
                sentences.append([])
                continue
            }
            if !draft.shape(at: index).key.isEmpty { sentences[sentences.count - 1].append(index) }
            let next = live.indices.contains(position + 1) ? draft.words[live[position + 1]].text : nil
            if Abbreviations.endsSentence(draft.words[index].text, followedBy: next) { sentences.append([]) }
        }
        return sentences.filter { !$0.isEmpty }
    }

    /// The last word with a stop unless it ends a list item, or the layout keeps newlines and the text holds one.
    private func finishedLast(_ word: String, in draft: Draft) -> String {
        let spokenAsHindi = draft.presentIndices.last.map(draft.isHindi(at:)) ?? false
        if !spokenAsHindi, MarkLegality.verdict(.stop, after: word) == .illegal { return Self.leftOpen(word) }
        // The text after the caret carries on the sentence, so a stop the recogniser closed it with goes.
        if followingTextContinuesSentence || insertionPoint.structure?.hasOpenBracketOnCaretLine == true {
            return Abbreviations.ownsStop(WordShape(word).core) ? word : WordShape.withoutTrailingStop(word)
        }
        if insertionPoint.isOnListItemLine || draft.endsInListItem { return Self.unstopped(word) }
        // A literal is not a sentence, so the stop the recogniser closed it with goes too.
        if Self.isLiteral(Self.paragraphWords(in: draft).last ?? [], in: draft) {
            return WordShape.withoutTrailingStop(word)
        }
        if Self.endsOnHashtags(draft) { return WordShape.withoutTrailingStop(word) }
        if layout.contains(.preserveNewlines), draft.text.contains(where: \.isNewline) { return word }
        // Only prose asks: "where total is greater than 12000" in a SQL editor is a clause, not a question.
        let asks = layout.contains(.paragraphs) && Self.lastSentenceAsks(draft)
        let preceding = String(draft.text.dropLast(word.count))
        return asks
            ? WordShape.finished(WordShape.withoutTrailingStop(word), with: "?", after: preceding)
            : WordShape.finished(word, after: preceding)
    }

    /// A word that leaves its clause open, such as a trailing "and", keeps no stop; an abbreviation keeps its own dot.
    private static func leftOpen(_ word: String) -> String {
        MarkLegality.state(of: word) == .leadsOn ? WordShape.withoutTrailingStop(word) : word
    }

    /// A list item's last word without the full stop a recogniser closes every dictation with; an abbreviation keeps its own dot.
    private static func unstopped(_ word: String) -> String {
        switch MarkLegality.state(of: word) {
        case .abbreviation, .leadingAbbreviation, .technical: word
        default: WordShape.withoutTrailingStop(word)
        }
    }

    /// Whether text after the replacement already ends or continues the sentence.
    private var followingTextContinuesSentence: Bool {
        guard let followingText = insertionPoint.followingText.map(InsertionPoint.visibleText) else {
            return false
        }
        let leadingWhitespace = followingText.prefix(while: \.isWhitespace)
        guard !leadingWhitespace.contains(where: \.isNewline),
            let next = followingText.dropFirst(leadingWhitespace.count).first
        else { return false }
        return ".!?…,:;".contains(next) || next.isLowercase
    }

    /// Whether the sentence the draft ends on asks a direct question by its word order.
    static func lastSentenceAsks(_ draft: Draft) -> Bool {
        QuestionShape.asks(lastSentence(of: draft).map { draft.shape(at: $0) })
    }

    /// The words of the sentence the draft ends on, after the last sentence end or layout mark.
    private static func lastSentence(of draft: Draft) -> ArraySlice<Int> {
        let live = draft.presentIndices
        let start = live.indices.dropLast().lastIndex { position in
            let index = live[position]
            guard !draft.words[index].isLayoutMark else { return true }
            return Abbreviations.endsSentence(
                draft.words[index].text, followedBy: draft.words[live[position + 1]].text
            )
        }
        return live[(start.map { $0 + 1 } ?? 0)...]
    }

    /// Whether the draft ends on a run of hashtags standing as their own sentence, which closes a post without a stop.
    private static func endsOnHashtags(_ draft: Draft) -> Bool {
        let sentence = lastSentence(of: draft)
        return !sentence.isEmpty && sentence.allSatisfy { WordShape(draft.words[$0].text).isHashtag }
    }

    /// Ends each paragraph of three or more words before a blank line with a full stop; a list item gets none.
    private static func stopParagraphs(_ draft: inout Draft, destination: Destination?) {
        var opening: Draft.Word?
        var paragraph: [Int] = []
        for index in draft.presentIndices {
            let word = draft.words[index]
            guard word.isLayoutMark else {
                paragraph.append(index)
                continue
            }
            let greetsOrSignsOff =
                destination == .email && Self.isEmailGreetingOrSignOff(paragraph, in: draft)
            if word.text.hasPrefix("\n\n"), let last = paragraph.last, greetsOrSignsOff {
                // A greeting or a closing takes no stop, a stop the model wrote included.
                let unstopped = WordShape.withoutTrailingStop(draft.words[last].text)
                if unstopped != draft.words[last].text { draft.replace(at: last, with: unstopped, by: id) }
            } else if word.text.hasPrefix("\n\n"), let last = paragraph.last, paragraph.count >= 3,
                !(opening?.isListMark ?? false), !isLiteral(paragraph, in: draft),
                MarkLegality.verdict(.stop, after: draft.words[last].text) != .illegal
            {
                let preceding = paragraph.dropLast().map { draft.words[$0].text }.joined(separator: " ")
                draft.replace(
                    at: last, with: WordShape.finished(draft.words[last].text, after: preceding), by: id)
            }
            if word.text.hasPrefix("\n\n") || word.isListMark {
                opening = word
                paragraph = []
            }
        }
    }

    /// Whether every word of a paragraph is a literal, such as an address, a path or digits, which is not a sentence.
    private static func isLiteral(_ paragraph: [Int], in draft: Draft) -> Bool {
        !paragraph.isEmpty
            && paragraph.allSatisfy {
                let text = draft.words[$0].text
                return TechnicalToken.classify(text) != nil || isDigits(text)
            }
    }

    /// A numeral written in digits only, such as "4096" or the "0100" of a phone number; "4th" and "10%" are words.
    private static func isDigits(_ text: String) -> Bool {
        text.first?.isNumber == true && text.last?.isNumber == true
            && text.allSatisfy { $0.isNumber || $0 == "," }
    }

    /// Whether a paragraph is an email opener or a final closing with a name.
    private static func isEmailGreetingOrSignOff(_ draft: Draft) -> Bool {
        let paragraphs = paragraphWords(in: draft)
        guard let last = paragraphs.last else { return false }
        return isEmailSignOff(draft) || paragraphs.count == 1 && isEmailGreeting(last, in: draft)
    }

    /// Whether the text ends with a supported email closing and a name.
    private static func isEmailSignOff(_ draft: Draft) -> Bool {
        let live = draft.presentIndices
        for (position, index) in live.enumerated() where !draft.words[index].isLayoutMark {
            if position > 0 {
                let previous = live[position - 1]
                guard draft.words[previous].isLayoutMark || draft.shape(at: previous).endsSentence else {
                    continue
                }
            }
            let suffix = live[position...].filter { !draft.words[$0].isLayoutMark }
            guard let first = suffix.first else { continue }
            let opening = firstWord(draft.words[first].text)
            let closingWords =
                opening == "best"
                    && suffix.dropFirst().first.map { firstWord(draft.words[$0].text) == "regards" } == true
                ? 2
                : 1
            guard ["thanks", "regards", "cheers", "best", "sincerely"].contains(opening),
                suffix.count > closingWords
            else { continue }
            let nameCount = suffix.count - closingWords
            guard (1...2).contains(nameCount) else { continue }
            let name = suffix.dropFirst(closingWords)
            guard name.dropLast().allSatisfy({ !draft.shape(at: $0).endsSentence }) else { continue }
            if draft.words[first].text.hasSuffix(",") || closingWords == 2 || nameCount == 1 { return true }
        }
        return false
    }

    /// The words in a draft split at paragraph marks, ignoring layout marks.
    private static func paragraphWords(in draft: Draft) -> [[Int]] {
        var paragraphs: [[Int]] = [[]]
        for index in draft.presentIndices {
            let word = draft.words[index]
            if word.isLayoutMark {
                if word.text.hasPrefix("\n\n"), !paragraphs[paragraphs.count - 1].isEmpty {
                    paragraphs.append([])
                }
            } else {
                paragraphs[paragraphs.count - 1].append(index)
            }
        }
        return paragraphs.filter { !$0.isEmpty }
    }

    /// Whether these words begin the first paragraph with a conventional email greeting.
    private static func isEmailGreeting(_ indices: [Int], in draft: Draft) -> Bool {
        let paragraphs = paragraphWords(in: draft)
        guard !indices.isEmpty, paragraphs.first == indices else { return false }
        // A longer greeting is one only on its own paragraph, with no clause mark carrying it on into the body.
        let standsAlone =
            paragraphs.count > 1
            && indices.dropLast().allSatisfy {
                !draft.shape(at: $0).suffix.contains(where: { ",.;:!?".contains($0) })
            }
        guard indices.count <= 3 || standsAlone else { return false }
        let openingWords = ["dear", "hello", "hi", "good morning", "good afternoon", "good evening"]
        return openingWords.contains { prefix in
            let words = prefix.split(separator: " ").map(String.init)
            return indices.count >= words.count
                && zip(words, indices).allSatisfy { pair in
                    firstWord(draft.words[pair.1].text) == pair.0
                }
        }
    }

    /// Whether this is the email's first greeting paragraph or final closing paragraph.
    private static func isEmailGreetingOrSignOff(_ paragraph: [Int], in draft: Draft) -> Bool {
        let paragraphs = paragraphWords(in: draft)
        return paragraphs.last == paragraph && isEmailSignOff(draft)
            || paragraphs.first == paragraph && isEmailGreeting(paragraph, in: draft)
    }

    private static func firstWord(_ text: String) -> String {
        String(text.lowercased().prefix(while: \.isLetter))
    }

    /// How many sentences the text holds; the joiner asks the same question of a whole dictation.
    static func sentenceCount(_ text: String) -> Int { SentenceCount.of(text) }
}
