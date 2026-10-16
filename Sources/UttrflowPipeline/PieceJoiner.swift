import UttrflowAI
import UttrflowCore

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
            audioDuration: pieces.reduce(.zero) { $0 + $1.heard.audioDuration },
            leadingSilence: first.heard.leadingSilence,
            trailingSilence: pieces.last?.heard.trailingSilence ?? .zero)
        // The quiet closing a piece plus the quiet opening the next is the pause between them.
        let pauses = pieces.indices.map { index in
            index == 0
                ? Duration.zero : pieces[index - 1].heard.trailingSilence + pieces[index].heard.leadingSilence
        }
        return Piece(
            heard: heard,
            corrected: CorrectedTranscript(
                text: correctedText.joined(separator: " "), corrections: corrections, held: held),
            cleaned: TransformationResult(
                text: laidOut(
                    seamed(
                        pieces.map(\.cleaned.text), heard: heardText, under: formatter, grouping: grouping),
                    under: formatter, steps: steps, pauses: pauses),
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
                intent: situation.intent, mode: situation.adapterMode
            ).passes.filter { unitReaders.contains($0.id) })
        func read(_ words: [String]) -> [String] {
            // A capital the date gives its month counts, so "march | third" is read as the one date.
            WordTokens.words(units.run(Draft(text: words.joined(separator: " "))).text, .display)
        }
        let headRead = read(Array(headWords))
        let apart = headRead + read(Array(tailWords))
        let together = read(Array(headWords + tailWords))
        guard together.map({ WordShape($0).core }) != apart.map({ WordShape($0).core }) else { return false }
        let shapes = apart.map(WordShape.init)
        let cued = NumberFormsPass.hasLabelCue(
            at: headRead.count - 1, keys: shapes.map(\.key), shapes: shapes)
        return cued || !gluesDigitGroups(together, from: apart, at: headRead.count)
    }

    /// Whether reading across the cut only fused two two-digit numbers into a year-like number ("20" "30"), not a century half and a second half that is no round ten.
    private static func gluesDigitGroups(_ together: [String], from apart: [String], at cut: Int) -> Bool {
        guard cut > 0, cut < apart.count, together.count == apart.count - 1 else { return false }
        let (before, after) = (apart[cut - 1], apart[cut])
        guard before.count == 2, after.count == 2, (before + after).allSatisfy({ $0.isASCII && $0.isNumber })
        else { return false }
        if let century = Int(before), (10...21).contains(century), after.last != "0" { return false }
        return together == Array(apart[..<(cut - 1)]) + [before + after] + Array(apart[(cut + 1)...])
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
        .markdownContinuation,
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
        // A pronoun or possessive opens the clause the seam split and is never a name.
        "he", "she", "it", "we", "they", "you", "there", "his", "her", "its", "our", "their", "my", "your",
    ]

    /// The words that open a noun phrase, as the mention guard reads them, without the relatives "which" and "whose".
    private static let determiners = MentionGuard.determiners.subtracting(["which", "whose"])

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
            let replacement = amount.symbol + NumberWords.render(sum, grouping: grouping, isAmount: true)
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
        if numberTakesUnit(last, first) { return true }
        return (noSentenceStop || (last.suffix == "." && previousWasHeardEndingOnScale))
            && first.prefix.isEmpty && isSpokenGroup(last.core)
            && isSpokenGroup(first.core)
    }

    /// Whether a numeral ends a piece and a currency or unit word opens the next, as "10" | "dollars": the quantity is one phrase.
    private static func numberTakesUnit(_ last: WordShape, _ first: WordShape) -> Bool {
        guard first.prefix.isEmpty, last.suffix.isEmpty || last.suffix == ".",
            integer(last.core) != nil, NumberFormsPass.seamUnits.contains(first.key)
        else { return false }
        return true
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
        _ pieces: [String], under formatter: DestinationFormatter, steps: CleaningSteps = .default,
        pauses: [Duration] = []
    ) -> String {
        var draft = Draft(words: [])
        var starts: [Int] = []
        // The pause before each piece, by the word it opens; a piece tidied to nothing hands its pause on.
        var pauseBefore: [Int: Duration] = [:]
        var owed = Duration.zero
        for (index, text) in pieces.enumerated() {
            var piece = Draft(keepingLineBreaks: text)
            owed += pauses.indices.contains(index) ? pauses[index] : .zero
            guard !piece.words.isEmpty else { continue }
            pauseBefore[draft.words.count] = owed
            owed = .zero
            var leadingBreaks = String(text.prefix(while: \.isNewline))
            // A later piece's bullet is written without a break, as the head of its own text; the joined text needs one.
            if leadingBreaks.isEmpty, !draft.words.isEmpty, piece.words[0].isListMark { leadingBreaks = "\n" }
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
            guard let position = livePosition(of: starts[opening], in: live), position >= 2,
                isLineCommand(at: position - 2, in: draft)
            else { continue }
            draft.replace(at: live[position - 2], with: "\n", by: id)
            draft.remove(at: live[position - 1], by: id)
            absorbed.insert(opening)
        }
        layoutCommands(&draft, at: starts, under: formatter)

        var live = draft.presentIndices
        for opening in starts.indices.dropFirst()
        where steps.runs(.selfCorrection) && restate(&draft, at: starts[opening], in: &live) {
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
        let breaking = starts.dropFirst().compactMap { pauseBefore[$0] }.filter { $0 > .zero }
        let openings = sentenceOpenings(in: draft, starts: starts)
        let counted = ordinalsBefore(openings, in: draft, starts: starts)
        for opening in openings.dropFirst() {
            guard paragraphs(formatter), !swallowed.contains(opening),
                !items.contains(where: { $0.opening == opening }),
                opensTopic(
                    draft, at: opening, starts: starts, afterPause: starts.contains(opening),
                    counted: counted)
                    || endsSubject(before: opening, in: draft, pause: pauseBefore[opening], among: breaking)
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
            guard let position = livePosition(of: start, in: live) else { continue }
            // The command may begin in the piece before and end here: `heads` of its words close that piece.
            var found: (command: (words: [String], mark: String, requiresLists: Bool), heads: Int)?
            for heads in 0...(commands.map(\.words.count).max() ?? 0) where found == nil {
                found = commands.first(where: { command in
                    (!command.requiresLists || formatter.layout.contains(.lists))
                        && (command.requiresLists || formatter.layout.contains(.paragraphs)
                            || formatter.layout.contains(.preserveNewlines))
                        && heads <= command.words.count
                        && commandMatches(
                            command.words, heads: heads, at: position, live: live, draft: draft,
                            pieceStart: starts[opening - 1], end: end)
                }).map { ($0, heads) }
            }
            guard let found else { continue }
            let last = position + found.command.words.count - found.heads
            let body = live[last]
            if body < end {
                let shape = draft.shape(at: body)
                draft.replace(
                    at: body, with: shape.replacingCore(with: WordShape.capitalised(shape.core)), by: id)
            }
            let first = position - found.heads
            // A command the cut split leaves the sentence before it unended, so it is ended as a seam ends it.
            if found.heads > 0, first > 0, live[first - 1] >= starts[opening - 1] {
                draft.replace(
                    at: live[first - 1], with: WordShape.finished(draft.words[live[first - 1]].text),
                    by: id)
            }
            draft.replace(at: live[first], with: found.command.mark, by: id)
            for index in live[(first + 1)..<last] {
                draft.remove(at: index, by: id)
            }
        }
    }

    /// Whether `words` are said across a seam: the last `heads` of them end the piece before, the rest open the piece at `position`.
    private static func commandMatches(
        _ words: [String], heads: Int, at position: Int, live: [Int], draft: Draft, pieceStart: Int, end: Int
    ) -> Bool {
        let first = position - heads
        let last = position + words.count - heads
        guard first >= 0, last < live.count, heads == 0 || live[first] >= pieceStart,
            words.count == heads || live[last - 1] < end,
            zip(words, live[first..<last]).allSatisfy({ $0 == draft.shape(at: $1).key })
        else { return false }
        return heads == 0 || !MentionGuard.namesLayout(at: first, spanning: words.count, in: draft)
    }

    /// Whether this place wants a blank line between topics at all.
    private static func paragraphs(_ formatter: DestinationFormatter) -> Bool {
        formatter.layout.contains(.paragraphs) && !formatter.layout.contains(.singleLine)
    }

    // MARK: Restatements across the seam

    /// Drops the tail the speaker replaced when a piece restates it, saying whether it did; `live` follows the drop.
    private static func restate(_ draft: inout Draft, at word: Int, in live: inout [Int]) -> Bool {
        guard let position = livePosition(of: word, in: live), position > 0 else { return false }
        // The stop the piece before was given ends a sentence the speaker never did, so the match reaches through it.
        let last = live[position - 1]
        let stopped = draft.words[last].text
        draft.words[last].text = WordShape.withoutTrailingStop(stopped)
        guard let discarded = discarded(at: position, in: live, of: draft) else {
            draft.words[last].text = stopped
            return false
        }
        for index in live[discarded] { draft.remove(at: index, by: id) }
        live = draft.presentIndices
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
        let openings = sentenceOpenings(in: draft, starts: starts)
        let counted = ordinalsBefore(openings, in: draft, starts: starts)
        var candidates: [BoundaryCandidate] = []
        for opening in openings {
            guard let found = sequence(draft, live, at: opening, starts: starts, counted: counted),
                let position = livePosition(of: opening, in: live),
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
        let live = draft.presentIndices
        for index in (piece + 1)..<starts.count {
            let previous = starts[index] - 1
            guard livePosition(of: previous, in: live) != nil,
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
        guard let position = livePosition(of: opening, in: live) else { return nil }
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
        _ draft: Draft, _ live: [Int], at word: Int, starts: [Int], counted: [Int: Set<Int>]
    ) -> (value: Int, kind: SequenceKind, length: Int)? {
        guard let position = livePosition(of: word, in: live) else { return nil }
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
                    || counted[word]?.contains(value - 1) == true
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
    private static func opensTopic(
        _ draft: Draft, at word: Int, starts: [Int], afterPause: Bool, counted: [Int: Set<Int>]
    ) -> Bool {
        let live = draft.presentIndices
        guard let position = livePosition(of: word, in: live) else { return false }
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
                || counted[word]?.contains(value - 1) == true)
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

    /// The shortest pause that sets a new subject apart.
    private static let subjectPause = Duration.milliseconds(1500)

    /// The multiple of the speaker's usual pause that a subject's pause must reach once there are enough pauses to know it.
    private static let subjectPauseMultiple = 2.0

    /// How many pauses it takes to know the speaker's usual one.
    private static let pausesToKnowUsual = 3

    /// Whether a sentence ends and a pause well past the usual one follows, which sets a new subject apart.
    private static func endsSubject(
        before word: Int, in draft: Draft, pause: Duration?, among pauses: [Duration]
    ) -> Bool {
        guard let pause, pause >= subjectPause else { return false }
        let live = draft.presentIndices
        guard let position = livePosition(of: word, in: live), position > 0,
            draft.shape(at: live[position - 1]).endsSentence
        else { return false }
        guard pauses.count >= pausesToKnowUsual else { return true }
        let usual = pauses.sorted()[pauses.count / 2]
        return pause >= usual * subjectPauseMultiple
    }

    /// Whether a bare ordinal opens a piece and a clause after it: "first we fix the build", where "first place" names a rank.
    private static func opensClauseAfterPause(
        at position: Int, in draft: Draft, _ live: [Int], starts: [Int]
    ) -> Bool {
        guard starts.contains(live[position]), position + 1 < live.count else { return false }
        return QuestionShape.newSubjects.contains(draft.shape(at: live[position + 1]).key)
    }

    /// The ordinal items the openings before each opening establish, read in one pass so no opening rereads the message.
    private static func ordinalsBefore(_ openings: [Int], in draft: Draft, starts: [Int]) -> [Int: Set<Int>] {
        let live = draft.presentIndices
        var seen = Set<Int>()
        var before: [Int: Set<Int>] = [:]
        for opening in openings {
            before[opening] = seen
            guard let position = livePosition(of: opening, in: live) else { continue }
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
        return before
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
