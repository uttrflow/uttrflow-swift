public import Foundation
import UttrflowCore

/// What the store must answer before a turn can be finished.
public struct SuggestionQuery: Sendable, Equatable {
    /// The field the answer belongs to.
    public let surface: Surface
    /// What has been typed into it so far.
    public let typed: String
    /// Which turn asked, so an answer arriving after the user moved on is dropped.
    public let generation: Int

    /// One question for the store, stamped with the turn that asked it.
    public init(surface: Surface, typed: String, generation: Int) {
        self.surface = surface
        self.typed = typed
        self.generation = generation
    }
}

/// What the gates must judge before a turn can be drawn.
public struct VerificationRequest: Sendable, Equatable {
    /// The field the candidates were offered for.
    public let surface: Surface
    /// What has been typed into it, which is the context a verdict is reached in.
    public let typed: String
    /// The ranked head of the candidates, which is everything that could be drawn and nothing else.
    public let candidates: [Candidate]
    /// Which turn asked, so a verdict arriving after the user typed on is dropped.
    public let generation: Int

    /// One question for the gates, stamped with the turn that asked it.
    public init(surface: Surface, typed: String, candidates: [Candidate], generation: Int) {
        self.surface = surface
        self.typed = typed
        self.candidates = candidates
        self.generation = generation
    }
}

/// What to draw and what the tap must swallow, decided together so the two cannot disagree.
public struct SuggestionUpdate: Sendable, Equatable {
    /// What the surface draws.
    public let suggestion: Suggestion
    /// What the tap swallows while that is drawn.
    public let armed: ArmedKeys
    /// Why nothing is on offer, present exactly when `suggestion.accepting` is nil.
    public let silence: Quieting.Reason?

    /// What to draw, what to arm, and why nothing is on offer when nothing is.
    public init(suggestion: Suggestion, armed: ArmedKeys, silence: Quieting.Reason?) {
        self.suggestion = suggestion
        self.armed = armed
        self.silence = silence
    }

    /// Nothing drawn and no key taken, for this reason, which is what most turns come to.
    public static func quiet(because reason: Quieting.Reason) -> SuggestionUpdate {
        SuggestionUpdate(suggestion: .silent, armed: [], silence: reason)
    }
}

/// What one turn of the loop needs next.
public enum SuggestionStep: Sendable, Equatable {
    /// Nothing needs asking, so draw this and arm that.
    case settled(SuggestionUpdate)
    /// Ask the store this, then hand the answer back to ``SuggestionSession/resolve(_:for:now:elapsedMilliseconds:)``.
    case query(SuggestionQuery)
}

/// What the store's answer comes to: something to draw, or something the gates must judge first.
public enum SuggestionResolution: Sendable, Equatable {
    /// Nothing is on offer, so this is drawn without the gates being troubled at all.
    case settled(SuggestionUpdate)
    /// Something is on offer, so ask the gates about these before anything is drawn.
    case verify(VerificationRequest)
}

/// One turn: what to do next, and what the user typed past on the way here.
public struct SuggestionTurn: Sendable, Equatable {
    /// What the loop needs next.
    public let step: SuggestionStep
    /// The suggestion just typed past, which the corpus counts against it.
    public let rejected: String?

    /// What to do next, and what the user typed past on the way here.
    public init(step: SuggestionStep, rejected: String? = nil) {
        self.step = step
        self.rejected = rejected
    }
}

/// What a keystroke the tap took comes to.
public enum SuggestionAction: Sendable, Equatable {
    /// Take this text: insert what it adds to what is typed, and count it as accepted.
    case accept(String)
    /// Draw this instead, which a move or a dismissal produces.
    case redraw(SuggestionUpdate)
    /// The keystroke means nothing here, so it goes back to the application as pressed.
    case giveBack(KeyStroke)
}

/// Sequences the whole tab-to-complete loop without touching a store, a clock or a screen.
public struct SuggestionSession: Sendable, Equatable {
    /// Beyond this many characters a field is a document, and its whole value is not a prefix worth matching.
    public static let maximumTypedLength = 256

    /// How long a turn may take, wide enough now to let the model answer; a superseded turn is dropped by its generation.
    public static let turnBudgetInMilliseconds = 8_000

    /// How long an accepted line remains eligible for being recognised as undone.
    public static let undoWindow: TimeInterval = 10

    /// How many of the ranked candidates the gates judge, which is every one that could be drawn.
    public static let verifiedDepth = PredictionEngine.maximumChoices

    /// The field the loop is following, or nothing when none is focused.
    public private(set) var surface: Surface?

    /// What is on screen right now.
    public private(set) var suggestion: Suggestion = .silent

    /// Where the highlight sits in what is offered.
    public private(set) var selection: SuggestionSelection = .untouched

    /// Whether the feature is on at all, which ⌥⎋ turns off.
    public private(set) var isEnabled = true

    /// Whether this field has been silenced for the rest of its life, which ⎋⎋ does.
    public private(set) var isSilencedHere = false

    /// How many suggestions have been typed past in this field.
    public private(set) var rejectionsHere = 0

    /// The line as of the last read, which is what an accepted suggestion continues.
    public private(set) var typed = ""

    /// Keys for lines taken and then undone in this field, never offered again until the line ends or the field changes.
    public private(set) var undoneHere: Set<String> = []

    /// Whether ⎋ has left only the dot in this field.
    private var isMinimised = false
    /// The key this application accepts with, told to the session each turn.
    private var acceptKey = AcceptKey.tab
    /// Whether only a completion this session is sure of may be drawn, never a list to choose from.
    private var isQuiet = false
    /// The moment an answer still in flight is being judged against.
    private var pending: PredictionContext?
    /// Which turn is current, so an answer to any earlier one is dropped.
    private var generation = 0
    /// Whether what is on screen was invented by the model rather than remembered, which decides what typing past it means.
    private var shownIsGenerated = false
    /// Keystrokes the coordinator has reported, so an offer worked out before the latest one is never taken.
    public private(set) var keystrokes = 0
    /// How many keystrokes the offer now on screen had seen when its turn's field read began.
    private var drawnAtKeystroke = 0
    /// The same count for the turn still being answered, which becomes the drawn one's only once it draws.
    private var pendingKeystroke = 0
    /// The last line taken here and the line it was taken over, watched for an undo until the line moves on.
    private var taken: TakenLine?

    /// A session following nothing, with the feature on and nothing drawn.
    public init() {}

    /// Notes one key typed in the field, which makes whatever is on offer stale until a turn reads the line again.
    public mutating func keystrokeArrived() {
        invalidate()
    }

    /// Notes a Return that ended the line, so the empty line after it is a new one and not an undo of what was taken.
    public mutating func lineEnded() {
        taken = nil
        undoneHere = []
    }

    /// Notes a click, scroll, switch or anything else that may have moved the caret, so neither the offer drawn nor an answer in flight is drawn again.
    public mutating func invalidate() {
        keystrokes += 1
    }

    /// Follows a key that typed the next characters of the ghost on screen, keeping the offer drawn and current; nothing when it typed anything else.
    public mutating func typedThrough(_ characters: String) -> SuggestionUpdate? {
        guard isCurrent, !characters.isEmpty, !selection.hasMoved, let line = suggestion.accepting,
            let edit = Acceptance.edit(accepting: line, after: typed), !edit.isReplacement,
            edit.inserted.count > characters.count, edit.inserted.hasPrefix(characters)
        else { return nil }
        // The key is counted and the offer is carried past it, so an answer read before it is still dropped.
        keystrokes += 1
        drawnAtKeystroke = keystrokes
        generation += 1
        typed += characters
        if case .choice(let leader, let others) = suggestion {
            let still = Array(Self.drawable([leader] + others, past: typed).dropFirst())
            suggestion = still.isEmpty ? .certain(leader) : .choice(leader: leader, others: still)
        }
        return armed(showing: suggestion, silence: nil)
    }

    /// Whether what was last settled was worked out from a read that saw every key and move since, which is all that may stay on screen.
    public var isCurrent: Bool { drawnAtKeystroke == keystrokes }

    /// Whether the turn being answered read the field after the latest key or move, so its answer still describes the line.
    private var answersTheLatestRead: Bool { pendingKeystroke == keystrokes }

    /// Takes one moment in one field and answers with what to do about it; `sawKeystrokes` is the count as its read began.
    public mutating func turn(
        in surface: Surface?, at moment: PredictionContext, acceptKey: AcceptKey = .tab,
        isQuiet: Bool = false, sawKeystrokes: Int? = nil, now: Date = Date()
    ) -> SuggestionTurn {
        self.acceptKey = acceptKey
        self.isQuiet = isQuiet
        // Held for this turn's offer, so the one still on screen keeps its own count until something replaces it.
        pendingKeystroke = sawKeystrokes ?? keystrokes
        let rejected = adopt(surface, typing: moment.typed, now: now)
        typed = moment.typed
        // Every turn is a new moment, so an answer to any earlier one is stale whether or not this one asks anything.
        generation += 1

        guard let surface else {
            return SuggestionTurn(step: .settled(.quiet(because: .nothingFocused)), rejected: rejected)
        }
        let context = contextualised(moment, in: surface)
        pending = context

        if let refused = Quieting.reason(context) { return settled(because: refused, rejected: rejected) }
        guard !context.isMinimised else {
            return settled(.minimised, because: .minimised, rejected: rejected)
        }
        guard !context.typed.isEmpty else { return settled(because: .emptyLine, rejected: rejected) }
        guard !ListMarker.isAlone(context.typed) else {
            return settled(because: .listMarkerOnly, rejected: rejected)
        }
        guard context.typed.count <= Self.maximumTypedLength else {
            return settled(because: .lineTooLong, rejected: rejected)
        }
        // A line in another script is one a suggestion may neither continue in that script nor glue Latin onto.
        guard LatinScript.writesOnlyLatin(context.typed) else {
            return settled(because: .nonLatinLine, rejected: rejected)
        }

        let query = SuggestionQuery(surface: surface, typed: context.typed, generation: generation)
        return SuggestionTurn(step: .query(query), rejected: rejected)
    }

    /// A turn that draws nothing, or only the dot, and says why.
    private mutating func settled(
        _ shown: Suggestion = .silent, because reason: Quieting.Reason, rejected: String?
    ) -> SuggestionTurn {
        SuggestionTurn(step: .settled(settle(shown, silence: reason)), rejected: rejected)
    }

    /// Turns the store's answer into what to draw or what to verify, nothing once the user has moved on.
    public mutating func resolve(
        _ candidates: [Candidate], for query: SuggestionQuery, now: Date, elapsedMilliseconds: Int
    ) -> SuggestionResolution? {
        guard query.generation == generation, query.surface == surface, answersTheLatestRead,
            let pending
        else { return nil }
        // A slow read has already cost the user the moment it answers about.
        guard elapsedMilliseconds <= Self.turnBudgetInMilliseconds else {
            return .settled(settle(.silent, silence: .overBudget))
        }
        // A candidate the user has already finished typing adds nothing, and one in another script is never written.
        let offerable = candidates.filter {
            $0.text != pending.typed && LatinScript.writesOnlyLatin($0.text)
                && SuggestionTextSafety.allows($0.text) && isOfferable($0.text)
        }
        let decided = PredictionEngine.ranked(from: offerable, in: pending, now: now)
        // A turn with nothing on offer has nothing to be wrong about, so the gates are never troubled.
        guard decided.suggestion.accepting != nil, let ranking = decided.ranking else {
            return .settled(settle(decided.suggestion, silence: decided.silence))
        }
        let head = ranking.candidates.prefix(Self.verifiedDepth).map(\.candidate)
        return .verify(
            VerificationRequest(
                surface: query.surface, typed: pending.typed, candidates: head,
                generation: generation))
    }

    /// Turns what the gates left of the head into what is drawn, nothing once the user has moved on.
    public mutating func resolve(
        _ verified: [Candidate], for request: VerificationRequest, now: Date, elapsedMilliseconds: Int
    ) -> SuggestionUpdate? {
        guard request.generation == generation, request.surface == surface, answersTheLatestRead,
            let pending
        else { return nil }
        // A verdict reached after the moment it judges has already cost the user that moment.
        guard elapsedMilliseconds <= Self.turnBudgetInMilliseconds else {
            return settle(.silent, silence: .overBudget)
        }
        let decided = PredictionEngine.decision(
            from: verified.filter {
                LatinScript.writesOnlyLatin($0.text) && SuggestionTextSafety.allows($0.text)
                    && isOfferable($0.text)
            }, in: pending,
            now: now)
        return settle(decided.suggestion, silence: decided.silence)
    }

    /// Draws the model's invented continuations in its own order, each only as sure as the pass that wrote it; a line it could not score is never drawn.
    public mutating func resolveGenerated(
        _ completions: [String], for query: SuggestionQuery, elapsedMilliseconds: Int,
        whenEmpty silence: Quieting.Reason = .nothingOffered,
        scores: [String: Double], listed: Set<String> = []
    ) -> SuggestionUpdate? {
        guard query.generation == generation, query.surface == surface, answersTheLatestRead,
            let pending
        else { return nil }
        guard elapsedMilliseconds <= Self.turnBudgetInMilliseconds else {
            return settle(.silent, silence: .overBudget)
        }
        let offerable = completions.filter { SuggestionTextSafety.allows($0) && isOfferable($0) }
        let decision = Self.generatedDecision(offerable, typed: pending.typed, scores: scores, listed: listed)
        let suggestion: Suggestion
        switch decision {
        case .noCandidate:
            return settle(.silent, silence: silence)
        case .unsure:
            return settle(.silent, silence: .modelUnsure)
        case .certain(let leader):
            suggestion = .certain(leader)
        case .choice(let leader, let others):
            suggestion = .choice(leader: leader, others: others)
        }
        let update = settle(suggestion, silence: nil)
        shownIsGenerated = true
        return update
    }

    /// Applies the app's drawable-line and confidence floors without the turn state.
    public static func generatedDecision(
        _ completions: [String], typed: String, scores: [String: Double], listed: Set<String> = []
    ) -> GeneratedSuggestionDecision {
        let drawable = Self.drawable(completions, past: typed)
        let usable = drawable.map { Self.keepingTypedCase($0, typed: typed) }
        guard let leader = usable.first else { return .noCandidate }
        let leaderListed = listed.contains(drawable[0])
        let leaderScore = leaderListed ? Verification.choiceFloor : scores[drawable[0]]
        // A list's leader has to clear the choice bar, and so does every alternative kept beside it.
        guard Verification.clears(leaderScore, floor: Verification.choiceFloor) else { return .unsure }
        let others = zip(drawable.dropFirst(), usable.dropFirst()).compactMap { scored, drawn in
            let lineScore = listed.contains(scored) ? Verification.choiceFloor : scores[scored]
            return Verification.clears(lineScore, floor: Verification.choiceFloor) ? drawn : nil
        }
        let kept = Array(others.prefix(Self.verifiedDepth - 1))
        // A lone leader has to clear the stricter bar; a machine-listed value is certain by existence and skips the score gate.
        let leaderClearsCertain =
            leaderListed || Verification.clears(leaderScore, floor: Verification.certainFloor)
        guard !kept.isEmpty || leaderClearsCertain else { return .unsure }
        return kept.isEmpty ? .certain(leader) : .choice(leader: leader, others: kept)
    }

    /// Adds the alternatives that arrived after the one line was drawn, so Down has a list to open without redrawing the line; nil scores mean the machine listed them.
    public mutating func expandGenerated(
        _ others: [String], for query: SuggestionQuery, scores: [String: Double]?
    ) -> SuggestionUpdate? {
        // Quiet mode never draws a list, so the alternatives have nothing to add and the line stays as it is.
        guard query.generation == generation, query.surface == surface, isCurrent, let pending,
            shownIsGenerated, !isQuiet,
            case .certain(let leader) = suggestion
        else { return nil }
        // The leader goes through the same sieve first, so an alternative repeating it in any case is dropped with the other repeats.
        let alternatives = others.filter(isOfferable)
        let drawable = Self.drawable([leader] + alternatives, past: pending.typed)
        // A model's alternative must clear the choice bar; a value the machine listed exists, so it needs no score.
        let kept = drawable.dropFirst().compactMap { scored -> String? in
            let floor = Verification.choiceFloor
            let stands = scores.map { Verification.clears($0[scored], floor: floor) } ?? true
            return stands ? Self.keepingTypedCase(scored, typed: pending.typed) : nil
        }
        guard !kept.isEmpty else { return nil }
        let update = settle(
            .choice(leader: leader, others: Array(kept.prefix(Self.verifiedDepth - 1))), silence: nil)
        shownIsGenerated = true
        return update
    }

    /// Whether a line may be offered here, which one the person took and undid in this field may not.
    private func isOfferable(_ line: String) -> Bool {
        !undoneHere.contains(TextMatching.caseFoldedKey(line))
    }

    /// The model's lines that can be drawn over what is typed: each extending it in the Latin alphabet, none repeated in any case, in the model's order.
    private static func drawable(_ lines: [String], past typed: String) -> [String] {
        var seen: Set<String> = []
        let matchingKey = TextMatching.caseFoldedKey(typed)
        return lines.filter {
            let key = TextMatching.caseFoldedKey($0)
            return key != matchingKey && key.hasPrefix(matchingKey)
                && LatinScript.writesOnlyLatin($0)
                && SuggestionTextSafety.allows($0)
                && seen.insert(key).inserted
        }
    }

    /// The line with its opening characters spelled as the user typed them, so a ghost only adds and never re-cases what is on the line.
    private static func keepingTypedCase(_ line: String, typed: String) -> String {
        guard line.count > typed.count,
            zip(line, typed).allSatisfy({
                TextMatching.caseFoldedKey(String($0)) == TextMatching.caseFoldedKey(String($1))
            })
        else { return line }
        return typed + line.dropFirst(typed.count)
    }

    /// Takes one keystroke the tap swallowed and answers with what it means.
    public mutating func route(_ stroke: KeyStroke, at now: Date = Date()) -> SuggestionAction {
        switch KeyRouting.decision(
            for: stroke, showing: suggestion, selection: selection, acceptKey: acceptKey)
        {
        case .accept(let text):
            // A key typed since the read this offer was worked out for has moved the line, so Tab takes nothing.
            guard drawnAtKeystroke == keystrokes else { return .giveBack(stroke) }
            // The offer is gone the moment it is taken, and so is any answer still in flight for it.
            generation += 1
            clearDrawing()
            taken = TakenLine(line: text, over: typed, moment: now)
            typed = text
            return .accept(text)
        case .moveSelection(let moved):
            selection = moved
            return .redraw(armed(showing: suggestion, silence: nil))
        case .dismiss(let dismissal):
            return .redraw(dismiss(dismissal))
        case .passThrough:
            return .giveBack(stroke)
        }
    }

    /// Applies one rung of the escape ladder and says what is left on screen; it asks for quiet, so the store is not told the line was wrong.
    private mutating func dismiss(_ dismissal: Dismissal) -> SuggestionUpdate {
        generation += 1
        switch dismissal {
        case .minimise:
            isMinimised = true
            return settle(.minimised, silence: .minimised)
        case .silenceField:
            isSilencedHere = true
            isMinimised = false
            return settle(.silent, silence: .turnedOffHere)
        case .turnOff:
            isEnabled = false
            isMinimised = false
            return settle(.silent, silence: .turnedOffHere)
        }
    }

    /// Follows identified fields, forgetting what belonged to the field being left.
    private mutating func adopt(_ surface: Surface?, typing: String, now: Date) -> String? {
        guard let surface else { return nil }
        guard surface == self.surface else {
            self.surface = surface
            isSilencedHere = false
            isMinimised = false
            rejectionsHere = 0
            taken = nil
            undoneHere = []
            clearDrawing()
            return nil
        }
        watchTaken(typing: typing, now: now)
        // An emptied line is a fresh start, so neither the suggestions typed past before it nor the ⎋ still binds the field.
        if typing.isEmpty {
            rejectionsHere = 0
            isMinimised = false
        }
        let folded = TextMatching.caseFoldedKey(typing)
        let offeredKey = suggestion.accepting.map(TextMatching.caseFoldedKey)
        let earlier = TextMatching.caseFoldedKey(typed)
        guard let offered = suggestion.accepting, let offeredKey,
            !offeredKey.hasScalarPrefix(folded)
        else { return nil }
        // Finishing the suggestion by hand and typing on is taking it, not typing past it.
        guard !folded.hasScalarPrefix(offeredKey) else { return nil }
        // Whitespace alone typed past a suggestion is a pause or a slip of the space bar, not a refusal.
        guard
            !(folded.hasScalarPrefix(earlier)
                && folded.dropFirst(earlier.count).allSatisfy(\.isWhitespace))
        else { return nil }
        // Only an offer that completed the line can be typed past; leaving a fuzzy or corrected one, or shortening the line, says nothing.
        guard offeredKey.hasScalarPrefix(earlier) else { return nil }
        rejectionsHere += 1
        // A guess the model invented counts toward quieting the field, but the store is never told to blame it.
        return shownIsGenerated ? nil : offered
    }

    /// Ends the watch on the last line taken once the line moves, marking it undone when the line went back inside it or to what it was taken over.
    private mutating func watchTaken(typing: String, now: Date) {
        guard let taken else { return }
        guard now.timeIntervalSince(taken.moment) <= Self.undoWindow else {
            self.taken = nil
            return
        }
        let line = TextMatching.caseFoldedKey(typing)
        let whole = TextMatching.caseFoldedKey(taken.line)
        // The read that shows the taken line in place is still inside the watch.
        guard line != whole else { return }
        self.taken = nil
        // A field emptied after a take was sent by a button or shortcut the tap never sees, which is not an undo.
        guard !line.isEmpty else { return }
        // A fuzzy line rewrote what was typed, so its undo lands on the typo rather than inside the line.
        if whole.hasScalarPrefix(line) || TextMatching.caseFoldedKey(taken.over).hasScalarPrefix(line) {
            undoneHere.insert(TextMatching.caseFoldedKey(taken.line))
        }
    }

    /// The moment with the three facts only this session knows filled in.
    private func contextualised(_ moment: PredictionContext, in surface: Surface) -> PredictionContext {
        var context = PredictionContext(
            typed: moment.typed, caretAtLineEnd: moment.caretAtLineEnd, hasSelection: moment.hasSelection,
            isComposing: moment.isComposing, isSecure: moment.isSecure, isProse: moment.isProse,
            millisecondsSinceKeystroke: moment.millisecondsSinceKeystroke,
            isEnabledHere: isEnabled && !isSilencedHere, isMinimised: isMinimised,
            rejectionsThisSession: rejectionsHere, canDraw: moment.canDraw, markedText: moment.markedText,
            isCommandLine: moment.isCommandLine, showsOwnList: moment.showsOwnList)
        context.applicationSupportsPickers = AppPicker.supportsPickers(in: surface.bundleIdentifier)
        return context
    }

    /// Records what is now on screen and reports it with the keys it claims and, when nothing is offered, why.
    private mutating func settle(_ shown: Suggestion, silence: Quieting.Reason?) -> SuggestionUpdate {
        // What is drawn now carries the count its own turn's read saw, and nothing drawn earlier does.
        drawnAtKeystroke = pendingKeystroke
        // The model's list outlives a corpus redraw of its line; a list the gates chose is replaced by their latest answer.
        if case .certain(let leader) = shown, case .choice(let current, let others) = suggestion,
            current == leader, shownIsGenerated, !isQuiet
        {
            let still = Array(Self.drawable([leader] + others, past: typed).dropFirst())
            if !still.isEmpty {
                // A narrowed list moves what sits under the highlight, so the highlight goes back to the leader.
                if still != others { selection = .untouched }
                suggestion = .choice(leader: leader, others: still)
                return armed(showing: suggestion, silence: nil)
            }
        }
        shownIsGenerated = false
        let next = isQuiet ? shown.certainOnly : shown
        // A list quiet mode dropped is its own reason, since nothing upstream withheld it.
        let reason = next == shown ? silence : Quieting.Reason.quietModeChoice
        if next != suggestion { selection = .untouched }
        suggestion = next
        return armed(showing: next, silence: reason)
    }

    /// Pairs a suggestion with the keys it claims and the reason for its silence, which is the only place the three are put together.
    private func armed(showing next: Suggestion, silence: Quieting.Reason?) -> SuggestionUpdate {
        SuggestionUpdate(
            suggestion: next,
            armed: KeyRouting.arming(showing: next, selection: selection, acceptKey: acceptKey),
            silence: next.accepting == nil ? silence : nil)
    }

    /// Takes the surface away without disturbing what the field has been told about itself.
    private mutating func clearDrawing() {
        suggestion = .silent
        selection = .untouched
        shownIsGenerated = false
    }
}

/// A line the person took and the line it was taken over, which is what an undo goes back to.
private struct TakenLine: Sendable, Equatable {
    /// The whole line the acceptance wrote.
    let line: String
    /// The line as typed when the key was pressed.
    let over: String
    /// When the key accepted the line.
    let moment: Date
}
