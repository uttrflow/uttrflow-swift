import UttrflowAI
import UttrflowCore

/// One piece of the recording, through every stage that runs before the words are joined.
struct Piece: Sendable {
    let heard: Transcription
    let corrected: CorrectedTranscript
    let cleaned: TransformationResult
}

/// Joins the pieces of one dictation, laying out what only the seam between two of them can show. See `Docs/cleanup-design.md` §7.
enum PieceJoiner {
    static let id: PassID = "pieceJoiner"

    /// The finished transcript before seam stops are restored, with the affected seam positions retained.
    static func snippetInput(
        _ pieces: [Piece], under formatter: DestinationFormatter, grouping: DigitGrouping? = nil,
        using text: String
    ) -> SeamSnippetInput {
        guard pieces.count > 1 else { return SeamSnippetInput(text: text, removableStops: [], source: text) }
        let texts = pieces.map(\.cleaned.text)
        let seamed = seamed(texts, heard: pieces.map(\.heard.text), under: formatter, grouping: grouping)
        var removableStops: [Int] = []
        var original = ""
        for index in pieces.indices {
            if index > 0 { original += " " }
            original += seamed[index]
            if index < pieces.count - 1,
                String(seamed[index]) != String(texts[index]),
                let last = original.last, ".!?".contains(last)
            {
                removableStops.append(original.count - 1)
            }
        }
        // The message's finishing cases the openings and adds a closing stop, which leaves every seam stop in place.
        let head = String(text.prefix(original.count))
        let exact =
            head.lowercased() == original.lowercased() && head.count == original.count
            && text.dropFirst(original.count).allSatisfy { ".!?".contains($0) }
        return SeamSnippetInput(text: text, removableStops: exact ? removableStops : [], source: text)
    }

    /// Every piece as one, with the corrections' word ranges moved to where their piece begins.
    static func join(
        _ pieces: [Piece], under formatter: DestinationFormatter, grouping: DigitGrouping? = nil,
        steps: CleaningSteps = .default
    ) -> Piece {
        guard pieces.count > 1, let first = pieces.first else {
            return pieces.first
                ?? Piece(
                    heard: Transcription(text: ""), corrected: .unchanged(""),
                    cleaned: TransformationResult(text: "", producedBy: .rules))
        }
        var corrections: [DictationCorrection] = []
        var held: [Range<Int>] = []
        var wordsBefore = 0
        var heardText: [String] = []
        var correctedText: [String] = []
        var producedBy = first.cleaned.producedBy
        for piece in pieces {
            corrections += piece.corrected.corrections.map { $0.shifted(by: wordsBefore) }
            held += piece.corrected.held.map { ($0.lowerBound + wordsBefore)..<($0.upperBound + wordsBefore) }
            wordsBefore += piece.heard.text.spokenWordCount
            heardText.append(piece.heard.text)
            correctedText.append(piece.corrected.text)
            // Any piece the model left to the rules makes the whole a rules result.
            if piece.cleaned.producedBy != producedBy { producedBy = .rules }
        }
        let heard = Transcription(
            text: heardText.joined(separator: " "),
            detectedLanguage: first.heard.detectedLanguage,
            segments: pieces.flatMap(\.heard.segments),
            audioDuration: pieces.reduce(.zero) { $0 + $1.heard.audioDuration })
        return Piece(
            heard: heard,
            corrected: CorrectedTranscript(
                text: correctedText.joined(separator: " "), corrections: corrections, held: held),
            cleaned: TransformationResult(
                text: laidOut(
                    seamed(
                        pieces.map(\.cleaned.text), heard: heardText, under: formatter, grouping: grouping),
                    under: formatter, steps: steps),
                producedBy: producedBy, entriesTaken: pieces.flatMap(\.cleaned.entriesTaken)))
    }

    /// Every piece but the last ended as a sentence the way the place ends one; the message's own stop is the cleaner's.
    static func seamed(
        _ pieces: [String], heard: [String] = [], under formatter: DestinationFormatter,
        grouping: DigitGrouping? = nil
    ) -> [String] {
        // An amount joined across a seam takes the person's grouping where given, else the place's.
        let joined = recleaningMarksAcrossSeams(
            joiningSpokenMarksAcrossSeams(
                joiningAmountsAcrossSeams(pieces, heard: heard, grouping: grouping ?? formatter.digits)))
        // A piece tidied to nothing has no seam, so each seam is judged against the next piece with words.
        let worded = joined.indices.filter { !joined[$0].allSatisfy(\.isWhitespace) }
        let heard = heard.count == joined.count ? worded.map { heard[$0] } : []
        var seamed = joined
        for (position, text) in seamedWorded(worded.map { joined[$0] }, heard: heard, under: formatter)
            .enumerated()
        {
            seamed[worded[position]] = text
        }
        return seamed
    }

    /// Seams pieces that all have words; each seam is judged once, and that verdict both ends the piece before it and opens the one after.
    private static func seamedWorded(
        _ pieces: [String], heard: [String], under formatter: DestinationFormatter
    ) -> [String] {
        let runsOn = pieces.indices.dropLast().map { index in
            sentenceRunsOn(pieces[index], into: pieces[index + 1])
                || groupRunsAcross(
                    pieces[index], into: pieces[index + 1],
                    previousWasHeardEndingOnScale: heardScaleEnding(heard, at: index))
        }
        return pieces.enumerated().map { index, text in
            var seamed = text
            // Each piece on its own line, so the opening word itself never reads as a name capitalised mid-line.
            if index > 0, runsOn[index - 1] {
                seamed = lowercasedOpening(seamed, in: pieces[index - 1] + "\n" + seamed)
            }
            guard index < pieces.count - 1 else { return seamed }
            return endedAtSeam(seamed, before: pieces[index + 1], runsOn: runsOn[index], under: formatter)
        }
    }

    /// Whether the passes that read a spoken unit or notation command read one across the cut, so only one piece writes it.
    static func unitRunsAcross(
        _ head: String, into tail: String, under formatter: DestinationFormatter, going situation: Situation
    ) -> Bool {
        let headWords = WordTokens.words(head, .display).suffix(longestSpokenUnit)
        let tailWords = WordTokens.words(tail, .display).prefix(longestSpokenUnit)
        guard !headWords.isEmpty, !tailWords.isEmpty else { return false }
        let units = CleaningPipeline(
            passes: CleaningPipeline.piece(
                numbers: formatter.numbers, digits: situation.digits(for: formatter),
                insertionPoint: situation.insertion, destination: formatter.destination,
                intent: situation.intent
            ).passes.filter { unitReaders.contains($0.id) })
        func read(_ words: [String]) -> [String] {
            WordTokens.words(units.run(Draft(text: words.joined(separator: " "))).text, .display)
                .map { WordShape($0).key }
        }
        return read(Array(headWords + tailWords)) != read(Array(headWords)) + read(Array(tailWords))
    }

    /// Whether a tidied piece leaves a double quotation open that the next one closes, so the cut falls inside the quoted words.
    static func quotationRunsAcross(_ head: String, into tail: String) -> Bool {
        !head.filter { $0 == "\"" }.count.isMultiple(of: 2) && tail.contains("\"")
    }

    /// The most words either side of a cut that one spoken number, time or address is read from.
    static let longestSpokenUnit = 8

    /// The destination's piece passes that read several words as one unit, the ones a cut can split.
    private static let unitReaders: Set<PassID> = [
        .spokenPunctuation, .numberForms, .codeEditorCommands, .spokenCasing,
    ]

    /// Attaches standalone spoken marks to adjacent words across piece boundaries.
    private static func joiningSpokenMarksAcrossSeams(_ pieces: [String]) -> [String] {
        guard pieces.count > 1 else { return pieces }
        var joined = pieces
        for index in joined.indices {
            let words = WordTokens.words(joined[index], .display)
            guard !words.isEmpty else { continue }
            if let leading = spokenMark(at: words, fromStart: true), leading.opening,
                words.count == leading.words.count,
                let following = joined[(index + 1)...].indices.first(where: {
                    !WordTokens.tokens(joined[$0], .display).isEmpty
                })
            {
                let nextWords = WordTokens.words(joined[following], .display)
                if let first = nextWords.first {
                    let rest = nextWords.dropFirst().joined(separator: " ")
                    joined[following] = leading.symbol + first + (rest.isEmpty ? "" : " " + rest)
                    joined[index] = ""
                }
            }
            guard let trailing = spokenMark(at: words, fromStart: false), !trailing.opening,
                words.count == trailing.words.count,
                !isMentionedSpokenMark(preceding: joined[..<index])
            else { continue }
            guard
                let previous = joined[..<index].indices.reversed().first(where: {
                    !WordTokens.tokens(joined[$0], .display).isEmpty
                })
            else { continue }
            joined[previous] = WordShape.marked(joined[previous], with: trailing.symbol)
            joined[index] = ""
        }
        return joined
    }

    /// Reads a mark name the pause cut from the word it follows by cleaning both pieces as one, so the cleaner's own judgement decides.
    private static func recleaningMarksAcrossSeams(_ pieces: [String]) -> [String] {
        var joined = pieces
        let worded = joined.indices.filter { !joined[$0].allSatisfy(\.isWhitespace) }
        for (previous, next) in zip(worded, worded.dropFirst()) {
            guard let (head, tail) = recleaned(joined[previous], before: joined[next]) else { continue }
            joined[previous] = head
            joined[next] = tail
        }
        return joined
    }

    /// The two pieces with a mark name at the seam written as its mark, when the spoken-punctuation pass changes only that name.
    private static func recleaned(_ head: String, before tail: String) -> (String, String)? {
        let headTokens = WordTokens.tokens(head, .display)
        let tailTokens = WordTokens.tokens(tail, .display)
        let headWords = headTokens.map(\.text)
        let tailWords = tailTokens.map(\.text)
        for mark in SpokenCommands.marks
        where !mark.placement.attachesAfter && ![.joining, .standalone].contains(mark.placement) {
            for fromHead in 0..<mark.words.count {
                let fromTail = mark.words.count - fromHead
                // A piece that is only the name is `joiningSpokenMarksAcrossSeams`'s to read.
                guard headWords.count > fromHead, tailWords.count >= fromTail,
                    fromHead > 0 || tailWords.count > fromTail,
                    (headWords.suffix(fromHead) + tailWords.prefix(fromTail)).map({
                        WordShape($0).key
                    })
                        == mark.words
                else { continue }
                let window = headWords + tailWords
                let cleaned = WordTokens.words(
                    SpokenPunctuationPass().apply(Draft(text: window.joined(separator: " "))).text, .display)
                let marked = headWords.count - fromHead - 1
                guard cleaned.count == window.count - mark.words.count,
                    cleaned[..<marked] == window[..<marked],
                    cleaned[(marked + 1)...] == window[(marked + 1 + mark.words.count)...],
                    cleaned[marked] != window[marked]
                else { return nil }
                let rest =
                    fromTail < tailWords.count ? String(tail[tailTokens[fromTail].range.lowerBound...]) : ""
                return (String(head[..<headTokens[marked].range.lowerBound]) + cleaned[marked], rest)
            }
        }
        return nil
    }

    /// Whether the next piece opens with a mark name the words before it introduce, so the name is the sentence's object.
    private static func namesMentionedMark(after text: String, in next: String) -> Bool {
        let words = WordTokens.words(next, .display)
        guard spokenMark(at: words, fromStart: true) != nil else { return false }
        return isMentionedSpokenMark(preceding: [text])
    }

    /// Keeps a spoken mark as words when a nearby determiner introduces its name.
    private static func isMentionedSpokenMark(preceding pieces: ArraySlice<String>) -> Bool {
        let prior = pieces.flatMap {
            WordTokens.words($0, .display).map { WordShape($0).key }
        }
        guard let previous = prior.last else { return false }
        if QuestionShape.determiners.contains(previous) { return true }
        if let lastSentenceEnd = prior.lastIndex(where: { [".", "?", "!"].contains($0) }) {
            return lastSentenceEnd == prior.index(before: prior.endIndex)
        }
        return previous == "word" && ["the", "a", "this", "that"].contains(prior.dropLast().last ?? "")
    }

    /// Finds a spoken mark from the shared registry at the start or end of a piece.
    private static func spokenMark(
        at words: [String], fromStart: Bool
    ) -> (words: [String], symbol: String, opening: Bool)? {
        for mark in SpokenCommands.marks
        where ![.joining, .standalone].contains(mark.placement) && words.count >= mark.words.count {
            let candidate = fromStart ? words.prefix(mark.words.count) : words.suffix(mark.words.count)
            if candidate.map({ WordShape($0).key }) == mark.words {
                return (mark.words, mark.text, mark.placement.attachesAfter)
            }
        }
        return nil
    }

    /// Lowers a sentence starter while leaving unrecognized proper nouns intact.
    private static func lowercasedOpening(_ text: String, in context: String) -> String {
        guard let start = text.firstIndex(where: { !$0.isWhitespace }),
            let first = text[start...].first
        else { return text }
        let end = text[start...].firstIndex(where: \.isWhitespace) ?? text.endIndex
        guard
            first.isUppercase,
            let lowercased = FirstWordPass.lowercasedAtRunOnSeam(String(text[start..<end]), in: context),
            lowercaseAtRunOnSeam.contains(WordShape(String(text[start..<end])).key)
        else { return text }
        return text.replacingCharacters(in: start..<end, with: lowercased)
    }

    private static let lowercaseAtRunOnSeam: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "from", "if", "in", "into", "of",
        "on", "or", "so", "that", "the", "then", "these", "this", "those", "to", "when",
        "which", "while", "who", "with",
        // A form of "be" or "have" after a run-on seam is the verb of the clause the seam split.
        "is", "are", "was", "were", "has", "have", "had",
    ]

    private static let determiners: Set<String> = [
        "a", "an", "the", "put", "add", "insert", "with", "no", "this", "that", "these", "those", "each",
        "every", "my", "your", "his", "her", "its", "their", "our", "another", "any", "some", "same",
    ]

    /// Completes a spoken scale amount with the smaller currency amount the next piece adds with "and".
    private static func joiningAmountsAcrossSeams(
        _ pieces: [String], heard: [String], grouping: DigitGrouping
    ) -> [String] {
        guard pieces.count > 1, heard.count == pieces.count else { return pieces }
        var joined = pieces
        for index in 0..<(joined.count - 1) {
            let following = WordTokens.words(joined[index + 1], .display)
            guard let last = WordTokens.words(joined[index], .display).last,
                following.count == 2, WordShape(following[0]).key == "and",
                let leadingValue = integer(last),
                let amount = currencyAmount(following[1]),
                let scale = closingScale(of: heard[index]),
                leadingValue.isMultiple(of: scale), amount.value < scale
            else { continue }
            let (sum, overflow) = leadingValue.addingReportingOverflow(amount.value)
            guard !overflow else { continue }
            let replacement = amount.symbol + NumberWords.render(sum, grouping: grouping)
            let prefix = String(joined[index].dropLast(last.count))
            joined[index] = prefix + replacement
            joined[index + 1] = ""
        }
        return joined
    }

    /// The scale word, such as hundred or thousand, that a piece was heard to end on.
    private static func closingScale(of heard: String) -> Int? {
        guard let last = WordTokens.words(heard, .display).last else { return nil }
        return NumberWords.scales[WordShape(last).key]
    }

    /// Reads a grouped or ungrouped nonnegative integer.
    private static func integer(_ text: String) -> Int? {
        let digits = text.replacingOccurrences(of: ",", with: "")
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }

    /// Reads the currency symbol and integer value from a cleaned amount.
    private static func currencyAmount(_ text: String) -> (symbol: String, value: Int)? {
        guard let symbol = text.first, "$€£₹".contains(symbol),
            let value = integer(String(text.dropFirst()))
        else { return nil }
        return (String(symbol), value)
    }

    /// One piece ended at a seam, unless the words on either side of the cut say the sentence ran through it. See `Docs/cleanup-design.md` §7.
    private static func endedAtSeam(
        _ text: String, before next: String, runsOn: Bool, under formatter: DestinationFormatter
    ) -> String {
        if endsWithSpokenLineCommand(text, before: next) { return WordShape.withoutTrailingStop(text) }
        if formatter.terminalStop == .never { return WordShape.withoutTrailingStop(text) }
        if WordTokens.words(next, .display).isEmpty { return text }
        let piece = Draft(keepingLineBreaks: text)
        guard let last = text.last, !last.isNewline, !piece.endsInListItem,
            !(formatter.layout.contains(.preserveNewlines) && text.contains(where: \.isNewline))
        else { return text }
        return runsOn ? WordShape.withoutTrailingStop(text) : WordShape.finished(text)
    }

    /// Whether a piece ends with the spoken command that opens a new line, read with the piece after it.
    private static func endsWithSpokenLineCommand(_ text: String, before next: String) -> Bool {
        let count = Draft(keepingLineBreaks: text).presentIndices.count
        return count >= 2 && isLineCommand(at: count - 2, in: Draft(keepingLineBreaks: text + " " + next))
    }

    /// Whether the live words at `position` ask for a new line, rather than naming one as in "a new line of shoes".
    private static func isLineCommand(at position: Int, in draft: Draft) -> Bool {
        let live = draft.presentIndices
        guard position >= 0, position + 1 < live.count else { return false }
        return draft.shape(at: live[position]).key == "new"
            && draft.shape(at: live[position + 1]).key == "line"
            && !MentionGuard.namesLayout(at: position, spanning: 2, in: draft)
    }

    // MARK: The stop at a seam

    /// Whether the words across a seam show the sentence carried on, which is the one reason not to end it there.
    static func sentenceRunsOn(_ text: String, into next: String) -> Bool {
        SentenceBoundaryEvidence.sentenceRunsOn(text, into: next)
            || trailingTriggerDiscardsWords(in: text, before: next)
            || namesMentionedMark(after: text, in: next)
    }

    /// The longest digit group or letter run a speaker says in one breath, as in a phone number's "555" or a code's "AB".
    static let longestSpokenGroup = 6

    /// Whether the seam falls inside a spoken group, with scale-word evidence required after a stop.
    private static func groupRunsAcross(
        _ text: String, into next: String, previousWasHeardEndingOnScale: Bool = false
    ) -> Bool {
        guard let last = WordTokens.words(text, .display).last.map(WordShape.init),
            let first = WordTokens.words(next, .display).first.map(WordShape.init)
        else { return false }
        let noSentenceStop = last.suffix.isEmpty
        return (noSentenceStop || (last.suffix == "." && previousWasHeardEndingOnScale))
            && first.prefix.isEmpty && isSpokenGroup(last.core)
            && isSpokenGroup(first.core)
    }

    /// Whether the recognizer heard the preceding piece end on a number scale word.
    private static func heardScaleEnding(_ heard: [String], at index: Int) -> Bool {
        heard.indices.contains(index) && closingScale(of: heard[index]) != nil
    }

    /// A rendered digit group, or a run of capital letters said one at a time, no longer than `longestSpokenGroup`.
    private static func isSpokenGroup(_ core: String) -> Bool {
        guard core.count <= longestSpokenGroup else { return false }
        if core.allSatisfy(\.isASCII) && core.allSatisfy(\.isNumber) { return !core.isEmpty }
        // A digit word, as in "two two four four", is a one-digit group.
        if let digit = NumberWords.value(of: core.lowercased()), (0...9).contains(digit) { return true }
        return core.count > 1 && core.allSatisfy { $0.isASCII && $0.isUppercase }
    }

    /// The cleaned pieces as one text: a spoken list, a paragraph at a topic, a restatement across the seam, else a space.
    static func laidOut(
        _ pieces: [String], under formatter: DestinationFormatter, steps: CleaningSteps = .default
    ) -> String {
        var draft = Draft(words: [])
        var starts: [Int] = []
        for text in pieces {
            var piece = Draft(keepingLineBreaks: text)
            guard !piece.words.isEmpty else { continue }
            let leadingBreaks = String(text.prefix(while: \.isNewline))
            if !leadingBreaks.isEmpty {
                if piece.words[0].isListMark {
                    piece.words[0].text = leadingBreaks + piece.words[0].text
                    if piece.words.count > 1 {
                        piece.words[1].text = WordShape.capitalised(piece.words[1].text)
                    }
                } else {
                    piece.words.insert(
                        Draft.Word(
                            text: leadingBreaks, heard: "", evidence: .unknown, state: .inserted(by: id)),
                        at: 0)
                }
            }
            starts.append(draft.words.count)
            draft.words += piece.words
        }
        guard !starts.isEmpty else { return draft.text }

        var marks: [Int: String] = [:]
        var absorbed: Set<Int> = []
        for opening in starts.indices.dropFirst() {
            let live = draft.presentIndices
            guard let position = live.firstIndex(of: starts[opening]), position >= 2,
                isLineCommand(at: position - 2, in: draft)
            else { continue }
            draft.replace(at: live[position - 2], with: "\n", by: id)
            draft.remove(at: live[position - 1], by: id)
            absorbed.insert(opening)
        }
        layoutCommands(&draft, at: starts, under: formatter)

        for opening in starts.indices.dropFirst()
        where steps.runs(.selfCorrection) && restate(&draft, at: starts[opening]) {
            absorbed.insert(opening)
        }
        let items = formatter.layout.contains(.lists) ? listItems(in: draft, starts: starts) : []
        for listItem in items {
            if let mark = itemise(&draft, listItem, starts: starts) {
                marks[listItem.opening] = mark
            }
        }
        if let last = items.last, last.bodyEnd < draft.words.count {
            marks[last.bodyEnd] = "\n\n"
        }
        let swallowed = Set(absorbed.map { starts[$0] })
        for opening in sentenceOpenings(in: draft, starts: starts).dropFirst() {
            guard paragraphs(formatter), !swallowed.contains(opening),
                !items.contains(where: { $0.opening == opening }),
                opensTopic(draft, at: opening, starts: starts, afterPause: starts.contains(opening))
            else { continue }
            marks[opening] = "\n\n"
        }
        for (index, mark) in marks.sorted(by: { $0.key > $1.key }) {
            draft.insert(mark, at: index, by: id)
        }
        return draft.text
    }

    /// Turns an explicit layout phrase at a noninitial piece boundary into its mark.
    private static func layoutCommands(
        _ draft: inout Draft, at starts: [Int], under formatter: DestinationFormatter
    ) {
        let commands: [(words: [String], mark: String, requiresLists: Bool)] = [
            (["new", "line"], "\n", false), (["new", "paragraph"], "\n\n", false),
            (["blank", "line"], "\n\n", false), (["bullet", "point"], "\n- ", true),
            (["next", "point"], "\n- ", true),
        ]
        for opening in starts.indices.dropFirst() {
            let start = starts[opening]
            let end = opening + 1 < starts.count ? starts[opening + 1] : draft.words.count
            let live = draft.presentIndices
            guard let position = live.firstIndex(of: start) else { continue }
            guard
                let found = commands.first(where: { command in
                    (!command.requiresLists || formatter.layout.contains(.lists))
                        && (command.requiresLists
                            || formatter.layout.contains(.paragraphs)
                            || formatter.layout.contains(.preserveNewlines))
                        && position + command.words.count < live.count
                        && live[position + command.words.count - 1] < end
                        && zip(command.words, live[position..<position + command.words.count]).allSatisfy {
                            $0 == draft.shape(at: $1).key
                        }
                })
            else { continue }
            let body = live[position + found.words.count]
            if body < end {
                let shape = draft.shape(at: body)
                draft.replace(
                    at: body, with: shape.replacingCore(with: WordShape.capitalised(shape.core)), by: id)
            }
            draft.replace(at: start, with: found.mark, by: id)
            for index in live[(position + 1)..<(position + found.words.count)] {
                draft.remove(at: index, by: id)
            }
        }
    }

    /// Whether this place wants a blank line between topics at all.
    private static func paragraphs(_ formatter: DestinationFormatter) -> Bool {
        formatter.layout.contains(.paragraphs) && !formatter.layout.contains(.singleLine)
    }

    // MARK: Restatements across the seam

    /// Drops the tail the speaker replaced when a piece restates it, saying whether it did.
    private static func restate(_ draft: inout Draft, at word: Int) -> Bool {
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: word), position > 0 else { return false }

        // The stop the piece before was given ends a sentence the speaker never did, so the match reaches through it.
        let last = live[position - 1]
        let stopped = draft.words[last].text
        draft.words[last].text = WordShape.withoutTrailingStop(stopped)
        guard let discarded = discarded(at: position, in: live, of: draft) else {
            draft.words[last].text = stopped
            return false
        }
        for index in live[discarded] { draft.remove(at: index, by: id) }
        return true
    }

    /// The half the piece opening at `position` takes back, trigger included, or nil when the halves do not match.
    private static func discarded(at position: Int, in live: [Int], of draft: Draft) -> Range<Int>? {
        let trigger = Restatement.triggerRun(at: position, in: live, of: draft)
        if trigger > 0, position + trigger < live.count,
            let start = Restatement.discardedStart(
                before: position, after: position + trigger, in: live, of: draft,
                asksForLayout: LayoutWordsPass.asksForLayout)
        {
            return start..<(position + trigger)
        }
        guard let tail = trailingTriggerStart(before: position, in: live, of: draft),
            position < live.count,
            let start = Restatement.discardedStart(
                before: tail, after: position, in: live, of: draft,
                asksForLayout: LayoutWordsPass.asksForLayout)
        else { return nil }
        return start..<position
    }

    /// Finds a correction trigger that ends exactly at the seam and takes back the words before it.
    private static func trailingTriggerStart(before position: Int, in live: [Int], of draft: Draft) -> Int? {
        for start in stride(from: position - 1, through: max(0, position - 3), by: -1) {
            let length = Restatement.triggerRun(at: start, in: live, of: draft)
            if length > 0, start + length == position { return start }
        }
        return nil
    }

    /// Whether a trigger at the end of this piece matches the opening words of the next one as a correction.
    private static func trailingTriggerDiscardsWords(in text: String, before next: String) -> Bool {
        let draft = Draft(text: text + " " + next)
        let live = draft.presentIndices
        let boundary = Draft(text: text).presentIndices.count
        guard boundary > 0, boundary < live.count,
            let trigger = trailingTriggerStart(before: boundary, in: live, of: draft),
            Restatement.discardedStart(
                before: trigger, after: boundary, in: live, of: draft,
                asksForLayout: LayoutWordsPass.asksForLayout) != nil
        else { return false }
        return true
    }

    // MARK: Lists from spoken sequence words

    private struct ListItem {
        let opening: Int
        let sequenceLength: Int
        let bodyEnd: Int
    }

    private struct BoundaryCandidate {
        let position: Int
        let opening: Int
        let length: Int
        let value: Int
        let kind: SequenceKind
    }

    /// The spans that are the items of one spoken list, read over the joined message so that where pieces were cut never decides it.
    private static func listItems(in draft: Draft, starts: [Int]) -> [ListItem] {
        let live = draft.presentIndices
        var candidates: [BoundaryCandidate] = []
        for opening in sentenceOpenings(in: draft, starts: starts) {
            guard let found = sequence(draft, live, at: opening, starts: starts),
                let position = live.firstIndex(of: opening),
                // A pause inside "number one" makes "one" an opening, but it is the marker already read.
                candidates.last.map({ position >= $0.position + $0.length }) ?? true
            else { continue }
            candidates.append(
                BoundaryCandidate(
                    position: position, opening: opening, length: found.length,
                    value: found.value, kind: found.kind))
        }
        guard let head = candidates.firstIndex(where: { $0.value == 1 }), candidates.count - head >= 2
        else { return [] }
        let kind = candidates[head].kind
        let run = Array(candidates[head...])
        for (offset, candidate) in run.enumerated() {
            let nextPosition = offset + 1 < run.count ? run[offset + 1].position : live.count
            guard candidate.kind == kind, candidate.value == offset + 1,
                hasClauseBody(
                    draft, live, from: candidate.position + candidate.length, to: nextPosition)
            else { return [] }
        }
        return run.enumerated().map { offset, candidate in
            let end =
                offset + 1 < run.count
                ? run[offset + 1].opening
                : trailingSentenceStart(in: draft, starts: starts, after: candidate.opening)
                    ?? draft.words.count
            return ListItem(
                opening: candidate.opening, sequenceLength: candidate.length, bodyEnd: end)
        }
    }

    /// The words that open a sentence: the message's first, each piece's first, and each after a sentence end.
    private static func sentenceOpenings(in draft: Draft, starts: [Int]) -> [Int] {
        let live = draft.presentIndices
        let pieceStarts = Set(starts)
        return live.indices.filter { position in
            position == live.startIndex || pieceStarts.contains(live[position])
                || Abbreviations.endsSentence(
                    draft.words[live[position - 1]].text, followedBy: draft.words[live[position]].text)
        }.map { live[$0] }
    }

    /// A later sentence after a complete item starts the closing paragraph; lowercase continuations stay in the item.
    private static func trailingSentenceStart(in draft: Draft, starts: [Int], after opening: Int) -> Int? {
        guard let piece = starts.lastIndex(where: { $0 <= opening }) else { return nil }
        for index in (piece + 1)..<starts.count {
            let previous = starts[index] - 1
            let live = draft.presentIndices
            guard live.contains(previous),
                draft.shape(at: previous).endsSentence,
                let first = live.first(where: { $0 >= starts[index] }),
                let character = draft.shape(at: first).core.first, character.isUppercase
            else { continue }
            return starts[index]
        }
        return nil
    }

    /// Whether words after a sequence marker form a clause before the next marker.
    private static func hasClauseBody(_ draft: Draft, _ live: [Int], from start: Int, to end: Int) -> Bool {
        let body = live[start..<end]
        guard body.count >= 2, let first = body.first else { return false }
        return !Self.determiners.contains(draft.shape(at: first).key)
    }

    /// Takes the sequence word off an item, capitalises what is left of it and drops its full stop, answering its mark.
    private static func itemise(_ draft: inout Draft, _ listItem: ListItem, starts: [Int]) -> String? {
        let live = draft.presentIndices
        let opening = listItem.opening
        guard let position = live.firstIndex(of: opening) else { return nil }
        let length = listItem.sequenceLength
        for index in live[position..<position + length] { draft.remove(at: index, by: id) }
        let end = listItem.bodyEnd
        let body = draft.presentIndices.filter { $0 >= opening && $0 < end }
        guard let head = body.first, let tail = body.last else { return nil }
        draft.replace(at: head, with: WordShape.capitalised(draft.words[head].text), by: id)
        draft.replace(at: tail, with: WordShape.withoutTrailingStop(draft.words[tail].text), by: id)
        // A stop at a seam the item's next words continue in lower case is the pause's, not the speaker's.
        for (word, next) in zip(body, body.dropFirst())
        where word != tail && starts.contains(next)
            && draft.shape(at: word).endsSentence && draft.shape(at: next).core.first?.isLowercase == true
        {
            draft.replace(at: word, with: WordShape.withoutTrailingStop(draft.words[word].text), by: id)
        }
        return draft.presentIndices.first == head ? Draft.bullet : "\n" + Draft.bullet
    }

    /// The sequence word a piece opens with — "first", "two", "number three", "point four" — and how many words it took.
    private static func sequence(
        _ draft: Draft, _ live: [Int], at word: Int, starts: [Int]
    ) -> (value: Int, kind: SequenceKind, length: Int)? {
        guard let position = live.firstIndex(of: word) else { return nil }
        var length = 0
        if position + 1 < live.count, Self.prefixes.contains(draft.shape(at: live[position]).key) {
            length = 1
        }
        guard position + length < live.count else { return nil }
        let prefix = length == 0 ? nil : draft.shape(at: live[position]).key
        let head = draft.shape(at: live[position + length])
        if let value = Self.ordinals[head.key] {
            guard
                prefix != nil || head.endsClause
                    || opensClauseAfterPause(at: position, in: draft, live, starts: starts)
                    || hasPriorOrdinalSequence(
                        value, before: word, in: draft, starts: starts
                    )
            else { return nil }
            return (value, .ordinal, length + 1)
        }
        // A bare cardinal counts the words after it as readily as it announces an item — "one bug is still open" — so it needs the announcing word or the mark the speaker set it off with.
        guard length > 0 || head.endsClause else { return nil }
        // A point-number needs a clause mark to distinguish a list item from a decimal.
        guard prefix != "point" || head.endsClause else { return nil }
        if let value = Self.cardinals[head.key] { return (value, .cardinal, length + 1) }
        return nil
    }

    // MARK: Paragraphs between topics

    /// Whether a sentence opens a new topic: a later ordinal item anywhere, or, after a pause, a phrase a speaker moves on with.
    private static func opensTopic(_ draft: Draft, at word: Int, starts: [Int], afterPause: Bool) -> Bool {
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: word) else { return false }
        let ordinalPosition: Int
        if Self.ordinals[draft.shape(at: live[position]).key] != nil {
            ordinalPosition = position
        } else if position + 1 < live.count,
            Self.prefixes.contains(draft.shape(at: live[position]).key),
            Self.ordinals[draft.shape(at: live[position + 1]).key] != nil
        {
            ordinalPosition = position + 1
        } else {
            ordinalPosition = -1
        }
        // An ordinal opens a topic only when its mark or an earlier item shows a sequence.
        if ordinalPosition >= 0, ordinalPosition + 1 < live.count,
            Self.ordinals[draft.shape(at: live[ordinalPosition]).key] != 1,
            let value = Self.ordinals[draft.shape(at: live[ordinalPosition]).key],
            (ordinalPosition != position || draft.shape(at: live[ordinalPosition]).endsClause
                || hasPriorOrdinalSequence(value, before: word, in: draft, starts: starts))
        {
            return true
        }
        return afterPause
            && Self.topics.contains { phrase in
                position + phrase.count <= live.count
                    && zip(phrase, live[position..<position + phrase.count]).allSatisfy {
                        $0 == draft.shape(at: $1).key
                    }
            }
    }

    /// Whether a bare ordinal opens a piece and a clause after it: "first we fix the build", where "first place" names a rank.
    private static func opensClauseAfterPause(
        at position: Int, in draft: Draft, _ live: [Int], starts: [Int]
    ) -> Bool {
        guard starts.contains(live[position]), position + 1 < live.count else { return false }
        return QuestionShape.newSubjects.contains(draft.shape(at: live[position + 1]).key)
    }

    /// Whether earlier sentence openings establish the ordinal sequence before this word.
    private static func hasPriorOrdinalSequence(
        _ value: Int, before word: Int, in draft: Draft, starts: [Int]
    ) -> Bool {
        let live = draft.presentIndices
        var seen = Set<Int>()
        for opening in sentenceOpenings(in: draft, starts: starts) where opening < word {
            guard let position = live.firstIndex(of: opening) else { continue }
            let prefix = Self.prefixes.contains(draft.shape(at: opening).key)
            let ordinal = prefix && position + 1 < live.count ? live[position + 1] : opening
            guard let prior = Self.ordinals[draft.shape(at: ordinal).key] else { continue }
            if prior == 1 {
                guard
                    prefix || draft.shape(at: ordinal).endsClause
                        || opensClauseAfterPause(at: position, in: draft, live, starts: starts)
                else { continue }
                seen = [1]
            } else if seen.contains(prior - 1) {
                seen.insert(prior)
            }
        }
        return seen.contains(value - 1)
    }

    // MARK: The words this reads

    /// Whether a sequence is counted in ordinals or in cardinals; one dictation's list never mixes them.
    private enum SequenceKind: Equatable { case ordinal, cardinal }

    /// Words that may stand before the number of an item, as in "number one" and "point two".
    private static let prefixes = MeaningPreservationGuard.listPrefixes

    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
        "eighth": 8, "ninth": 9, "tenth": 10,
        "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5, "6th": 6, "7th": 7,
        "8th": 8, "9th": 9, "10th": 10,
    ]

    private static let cardinals: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8,
        "9": 9, "10": 10,
    ]

    /// The phrases a speaker opens a new topic with after a pause.
    private static let topics: [[String]] = [
        ["okay", "so"], ["ok", "so"], ["another", "thing"], ["one", "more", "thing"],
        ["moving", "on"], ["also"], ["next"], ["finally"], ["anyway"], ["additionally"],
        ["furthermore"], ["lastly"],
    ]
}

extension DictationCorrection {
    /// The same correction, indexing words `offset` further into a longer sentence.
    fileprivate func shifted(by offset: Int) -> Self {
        Self(
            heard: heard, wrote: wrote,
            wordRange: (wordRange.lowerBound + offset)..<(wordRange.upperBound + offset),
            entryID: entryID, reason: reason, heardConfidence: heardConfidence, evidence: evidence)
    }
}

extension String {
    /// How many words were spoken, counted the way the corrections' ranges count them.
    var spokenWordCount: Int { split(whereSeparator: \.isWhitespace).count }
}
