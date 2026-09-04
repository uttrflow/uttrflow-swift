public import struct Foundation.Date

/// What the store must answer before a turn can be finished.
public struct SuggestionQuery: Sendable, Equatable {
    /// The field the answer belongs to.
    public let surface: Surface
    /// What has been typed into it so far.
    public let typed: String
    /// Which turn asked, so an answer arriving after the user moved on is dropped.
    public let generation: Int

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

    public init(surface: Surface, typed: String, candidates: [Candidate], generation: Int) {
        self.surface = surface
        self.typed = typed
        self.candidates = candidates
        self.generation = generation
    }
}

/// What to draw and what the tap must swallow, decided together so the two cannot disagree.
public struct SuggestionUpdate: Sendable, Equatable {
    public let suggestion: Suggestion
    public let armed: ArmedKeys

    public init(suggestion: Suggestion, armed: ArmedKeys) {
        self.suggestion = suggestion
        self.armed = armed
    }

    /// Nothing drawn and no key taken, which is what most turns come to.
    public static let quiet = SuggestionUpdate(suggestion: .silent, armed: [])
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
    public let step: SuggestionStep
    /// The suggestion just typed past, which the corpus counts against it.
    public let rejected: String?

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
    /// The keystroke changed nothing here.
    case nothing
}

/// Sequences the whole tab-to-complete loop without touching a store, a clock or a screen.
public struct SuggestionSession: Sendable, Equatable {
    /// Beyond this many characters a field is a document, and its whole value is not a prefix worth matching.
    public static let maximumTypedLength = 256

    /// How long a turn may take, wide enough now to let the model answer; a superseded turn is dropped by its generation.
    public static let turnBudgetInMilliseconds = 8_000

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

    /// What the field held when it was last read, which is what an accepted suggestion continues.
    public private(set) var typed = ""

    private var isMinimised = false
    private var acceptKey = AcceptKey.tab
    /// Whether only a completion this session is sure of may be drawn, never a list to choose from.
    private var isQuiet = false
    private var pending: PredictionContext?
    private var generation = 0
    /// Whether what is on screen was invented by the model rather than remembered, which decides what typing past it means.
    private var shownIsGenerated = false

    public init() {}

    /// Takes one moment in one field and answers with what to do about it.
    public mutating func turn(
        in surface: Surface?, at moment: PredictionContext, acceptKey: AcceptKey = .tab,
        isQuiet: Bool = false
    ) -> SuggestionTurn {
        self.acceptKey = acceptKey
        self.isQuiet = isQuiet
        let rejected = adopt(surface, typing: moment.typed)
        typed = moment.typed

        guard let surface else { return SuggestionTurn(step: .settled(.quiet), rejected: rejected) }
        let context = contextualised(moment)
        pending = context

        guard !Quieting.refuses(context) else {
            return SuggestionTurn(step: .settled(settle(.silent)), rejected: rejected)
        }
        guard !context.isMinimised else {
            return SuggestionTurn(step: .settled(settle(.minimised)), rejected: rejected)
        }
        guard !context.typed.isEmpty, context.typed.count <= Self.maximumTypedLength else {
            return SuggestionTurn(step: .settled(settle(.silent)), rejected: rejected)
        }

        generation += 1
        let query = SuggestionQuery(surface: surface, typed: context.typed, generation: generation)
        return SuggestionTurn(step: .query(query), rejected: rejected)
    }

    /// Turns the store's answer into what to draw or what to verify, nothing once the user has moved on.
    public mutating func resolve(
        _ candidates: [Candidate], for query: SuggestionQuery, now: Date, elapsedMilliseconds: Int
    ) -> SuggestionResolution? {
        guard query.generation == generation, query.surface == surface, let pending else { return nil }
        // A slow read or a slow query has already cost the user the moment it was answering.
        guard elapsedMilliseconds <= Self.turnBudgetInMilliseconds else { return .settled(settle(.silent)) }
        // A candidate the user has already finished typing adds nothing, and drawing it doubles the line.
        let offerable = candidates.filter { $0.text != pending.typed }
        let drawable = PredictionEngine.suggestion(from: offerable, in: pending, now: now)
        // A turn with nothing on offer has nothing to be wrong about, so the gates are never troubled.
        guard drawable.accepting != nil else { return .settled(settle(drawable)) }
        let head = Ranking(offerable, now: now).candidates.prefix(Self.verifiedDepth).map(\.candidate)
        return .verify(
            VerificationRequest(
                surface: query.surface, typed: pending.typed, candidates: head,
                generation: generation))
    }

    /// Turns what the gates left of the head into what is drawn, nothing once the user has moved on.
    public mutating func resolve(
        _ verified: [Candidate], for request: VerificationRequest, now: Date, elapsedMilliseconds: Int
    ) -> SuggestionUpdate? {
        guard request.generation == generation, request.surface == surface, let pending else {
            return nil
        }
        // A verdict reached after the moment it was judging has already cost the user that moment.
        guard elapsedMilliseconds <= Self.turnBudgetInMilliseconds else { return settle(.silent) }
        return settle(PredictionEngine.suggestion(from: verified, in: pending, now: now))
    }

    /// Draws the model's invented continuations in its own order, since a generated line has no history to weigh.
    public mutating func resolveGenerated(
        _ completions: [String], for query: SuggestionQuery, elapsedMilliseconds: Int
    ) -> SuggestionUpdate? {
        guard query.generation == generation, query.surface == surface, let pending else { return nil }
        guard elapsedMilliseconds <= Self.turnBudgetInMilliseconds else { return settle(.silent) }
        let usable = completions.filter {
            $0 != pending.typed && $0.lowercased().hasPrefix(pending.typed.lowercased())
        }
        guard let leader = usable.first else { return settle(.silent) }
        let others = Array(usable.dropFirst().prefix(Self.verifiedDepth - 1))
        let update = settle(others.isEmpty ? .certain(leader) : .choice(leader: leader, others: others))
        shownIsGenerated = true
        return update
    }

    /// Takes one keystroke the tap swallowed and answers with what it means.
    public mutating func route(_ stroke: KeyStroke) -> SuggestionAction {
        switch KeyRouting.decision(
            for: stroke, showing: suggestion, selection: selection, acceptKey: acceptKey)
        {
        case .accept(let text):
            // The offer is gone the moment it is taken, and so is any answer still in flight for it.
            generation += 1
            clearDrawing()
            typed = text
            return .accept(text)
        case .moveSelection(let moved):
            selection = moved
            return .redraw(armed(showing: suggestion))
        case .dismiss(let dismissal):
            return .redraw(dismiss(dismissal))
        case .passThrough:
            return .nothing
        }
    }

    /// Applies one rung of the escape ladder and says what is left on screen.
    private mutating func dismiss(_ dismissal: Dismissal) -> SuggestionUpdate {
        generation += 1
        switch dismissal {
        case .minimise:
            isMinimised = true
            return settle(.minimised)
        case .silenceField:
            isSilencedHere = true
            isMinimised = false
            return settle(.silent)
        case .turnOff:
            isEnabled = false
            isMinimised = false
            return settle(.silent)
        }
    }

    /// Follows the focus, forgetting everything that belonged to the field being left.
    private mutating func adopt(_ surface: Surface?, typing: String) -> String? {
        guard surface == self.surface else {
            self.surface = surface
            isSilencedHere = false
            isMinimised = false
            rejectionsHere = 0
            clearDrawing()
            return nil
        }
        // An emptied line is a fresh start, so the suggestions typed past before it no longer count against the field.
        if typing.isEmpty { rejectionsHere = 0 }
        let lowered = typing.lowercased()
        // Case alone is not typing past, since the store matched the line regardless of it.
        guard let offered = suggestion.accepting, !offered.lowercased().hasPrefix(lowered) else { return nil }
        // Finishing the suggestion by hand and typing on is taking it, not typing past it.
        guard !lowered.hasPrefix(offered.lowercased()) else { return nil }
        // Whitespace alone typed past a suggestion is a pause or a slip of the space bar, not a refusal.
        let earlier = typed.lowercased()
        guard !(lowered.hasPrefix(earlier) && lowered.dropFirst(earlier.count).allSatisfy(\.isWhitespace))
        else { return nil }
        // Typing past a guess the model invented says the model was wrong, not that the field wants quiet.
        guard !shownIsGenerated else { return nil }
        // Only a completion of what was typed counts toward quiet; a correction typed past says the guess was wrong.
        if offered.lowercased().hasPrefix(typed.lowercased()) { rejectionsHere += 1 }
        return offered
    }

    /// The moment with the three facts only this session knows filled in.
    private func contextualised(_ moment: PredictionContext) -> PredictionContext {
        PredictionContext(
            typed: moment.typed, caretAtLineEnd: moment.caretAtLineEnd, hasSelection: moment.hasSelection,
            isComposing: moment.isComposing, isSecure: moment.isSecure, isProse: moment.isProse,
            millisecondsSinceKeystroke: moment.millisecondsSinceKeystroke,
            isEnabledHere: isEnabled && !isSilencedHere, isMinimised: isMinimised,
            rejectionsThisSession: rejectionsHere)
    }

    /// Records what is now on screen and reports it with the keys it claims.
    private mutating func settle(_ shown: Suggestion) -> SuggestionUpdate {
        shownIsGenerated = false
        let next = isQuiet ? shown.certainOnly : shown
        if next != suggestion { selection = .untouched }
        suggestion = next
        return armed(showing: next)
    }

    /// Pairs a suggestion with the keys it claims, which is the only place the two are put together.
    private func armed(showing next: Suggestion) -> SuggestionUpdate {
        SuggestionUpdate(
            suggestion: next,
            armed: KeyRouting.arming(showing: next, selection: selection, acceptKey: acceptKey))
    }

    /// Takes the surface away without disturbing what the field has been told about itself.
    private mutating func clearDrawing() {
        suggestion = .silent
        selection = .untouched
        shownIsGenerated = false
    }
}
