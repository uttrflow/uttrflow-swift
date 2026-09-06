import Foundation
import Testing

@testable import UttrflowPredict

/// The fields a script may move between, with nothing focused among them.
private let places: [Surface?] = [
    Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea"),
    Surface(bundleIdentifier: "com.apple.Safari", role: "AXTextField"),
    Surface(bundleIdentifier: "com.example.chat", role: "AXTextArea", locator: "Message"),
    nil,
]

/// Every line the fake corpus remembers, with a fixed weight so the ranking is the same on every run.
private let corpus: [(text: String, count: Int)] = [
    ("git commit -m", 40), ("git checkout main", 12), ("git checkout -b", 11), ("git clone", 3),
    ("git status", 30), ("ls -la", 25), ("ls", 26), ("make verify", 9), ("make app", 8), ("npm run dev", 5),
    ("on my way", 20), ("ok bhai kal milenge", 2), ("rm -rf build", 15),
]

/// What the store answers for a line: every remembered line it opens, weighted, the destructive one marked.
private func stored(for typed: String) -> [Candidate] {
    corpus.filter { $0.text.lowercased().hasPrefix(typed.lowercased()) }.map {
        remembered($0.text, count: $0.count, irreversible: $0.text.hasPrefix("rm "))
    }
}

/// Every keystroke the tap might hand the session.
private let strokes = [
    KeyStroke(.tab), KeyStroke(.tab, modifiers: .option), KeyStroke(.return), KeyStroke(.escape),
    KeyStroke(.escape, modifiers: .option), KeyStroke(.downArrow), KeyStroke(.upArrow),
    KeyStroke(.rightArrow),
    KeyStroke(.other), KeyStroke(.downArrow, modifiers: .command),
]

/// One random run of turns and keystrokes against one session, checking the session's promises after each.
private struct Script {
    /// The seeded generator every choice in the run is drawn from.
    var random: Seeded
    /// The session under test.
    var session = SuggestionSession()
    /// The field the script is typing into, or nothing when it has moved away.
    var surface: Surface?
    /// What has been typed into it.
    var typed = ""
    /// The key this application accepts with.
    var acceptKey = AcceptKey.tab
    /// Whether only a completion the session is sure of may be drawn.
    var isQuiet = false
    /// The question the store is answering right now, which the next turn makes stale.
    var live: SuggestionQuery?
    /// The questions the user has moved on from, which must all be dropped.
    var stale: [SuggestionQuery] = []
    /// Whether what is on screen came from the model, mirrored from outside the session.
    var shownGenerated = false
    /// Whether ⎋ has left only the dot in this field, mirrored from outside the session.
    var minimised = false
    /// The last thing the session said to draw and arm.
    var last = SuggestionUpdate.quiet(because: .nothingFocused)
    /// The line the drawn suggestion was asked about.
    var asked = ""

    /// One run drawn from the seed, starting in the first field with nothing typed.
    init(seed: Int) {
        random = Seeded(seed: seed)
        surface = places[0]
    }

    /// Runs this many steps, checking every promise the session makes after each of them.
    mutating func run(steps: Int) {
        for _ in 0..<steps {
            switch Int.random(in: 0..<100, using: &random) {
            case 0..<32: type()
            case 32..<42: typed = String(typed.dropLast())
            case 42..<50: typed = ""
            case 50..<57: surface = random.pick(places)
            case 57..<62:
                acceptKey = random.pick(AcceptKey.allCases)
                isQuiet = random.chance(0.3)
            case 62..<80:
                press(random.pick(strokes))
                continue
            case 80..<90:
                probeStale()
                continue
            default: typed = random.chance(0.5) ? String(repeating: "a", count: 300) : "Git C"
            }
            turn()
        }
    }

    /// Types one more character, usually along a remembered line so the corpus has something to offer.
    private mutating func type() {
        let ahead = corpus.map(\.text).filter {
            $0.lowercased().hasPrefix(typed.lowercased()) && $0.count > typed.count
        }
        if let line = ahead.randomElement(using: &random), random.chance(0.8) {
            typed += String(line[line.index(line.startIndex, offsetBy: typed.count)])
        } else {
            typed += String(random.pick(Array("gitls -mxq")))
        }
    }

    /// One moment in the field, with every fact the gates read drawn at random.
    private mutating func randomContext() -> PredictionContext {
        PredictionContext(
            typed: typed, caretAtLineEnd: random.chance(0.9), hasSelection: random.chance(0.05),
            isComposing: random.chance(0.05), isSecure: random.chance(0.03), isProse: random.chance(0.3),
            millisecondsSinceKeystroke: random.pick([0, 100, 399, 400, 1_000]))
    }

    /// One turn, and everything it must be true of before and after it.
    private mutating func turn() {
        let context = randomContext()
        let before = session.rejectionsHere
        let shownBefore = session.suggestion.accepting
        let generatedBefore = shownGenerated
        let sameField = surface == session.surface
        let turn = session.turn(in: surface, at: context, acceptKey: acceptKey, isQuiet: isQuiet)
        retire()
        if let rejected = turn.rejected { #expect(rejected == shownBefore) }
        if !sameField || context.typed.isEmpty {
            #expect(session.rejectionsHere == 0)
            minimised = false
        } else {
            #expect(session.rejectionsHere == before || session.rejectionsHere == before + 1)
            if generatedBefore {
                #expect(session.rejectionsHere == before)
                #expect(turn.rejected == nil)
            }
        }
        #expect(session.rejectionsHere <= Quieting.rejectionsBeforeSilence)
        switch turn.step {
        case .settled(let update):
            settled(update, generated: false)
            if surface == nil {
                #expect(update == .quiet(because: .nothingFocused))
            } else {
                #expect(update.silence == expectedSilence(of: context))
            }
        case .query(let query):
            #expect(query.typed == context.typed && query.surface == surface)
            #expect(!Quieting.refuses(context) && !context.typed.isEmpty && !minimised)
            live = query
            asked = query.typed
            if random.chance(0.35) { generate(for: query) } else { answer(query) }
        }
    }

    /// Why a turn settles before asking anything, in the order the session checks: the moment's rules, the dot, the line.
    private func expectedSilence(of context: PredictionContext) -> Quieting.Reason {
        let known = PredictionContext(
            typed: context.typed, caretAtLineEnd: context.caretAtLineEnd, hasSelection: context.hasSelection,
            isSecure: context.isSecure, isProse: context.isProse,
            millisecondsSinceKeystroke: context.millisecondsSinceKeystroke,
            isEnabledHere: session.isEnabled && !session.isSilencedHere,
            rejectionsThisSession: session.rejectionsHere)
        if let refused = Quieting.reason(known) { return refused }
        if minimised { return .minimised }
        return context.typed.isEmpty ? .emptyLine : .lineTooLong
    }

    /// The store answers, the gates judge what is drawable, and the session draws what they left.
    private mutating func answer(_ query: SuggestionQuery) {
        let budget = SuggestionSession.turnBudgetInMilliseconds
        let before = session.suggestion
        let elapsed = random.chance(0.05) ? budget + 1 : Int.random(in: 0...budget, using: &random)
        let candidates = stored(for: query.typed)
        switch session.resolve(candidates, for: query, now: moment, elapsedMilliseconds: elapsed) {
        case nil:
            Issue.record("a live query must be answered")
        case .settled(let update):
            settled(update, generated: false)
            if elapsed > budget { #expect(update == .quiet(because: .overBudget)) }
        case .verify(let request):
            #expect(elapsed <= budget)
            #expect(request.typed == query.typed && request.surface == query.surface)
            #expect(request.candidates.count <= SuggestionSession.verifiedDepth)
            #expect(request.candidates.allSatisfy { candidates.contains($0) })
            let verified = request.candidates.filter { _ in random.chance(0.7) }
            guard
                let update = session.resolve(
                    verified, for: request, now: moment, elapsedMilliseconds: elapsed)
            else {
                Issue.record("a live verification must be answered")
                return
            }
            // The same line drawn again keeps the list that stood behind it, and with it whether the model drew that list.
            let others = listed(in: update.suggestion)
            let kept =
                before.accepting == update.suggestion.accepting && !others.isEmpty
                && others.allSatisfy { listed(in: before).contains($0) }
            settled(update, generated: kept ? shownGenerated : false)
            let drawn = [update.suggestion.accepting].compactMap { $0 } + others
            let texts = verified.map(\.text)
            #expect(drawn.allSatisfy { texts.contains($0) || (kept && listed(in: before).contains($0)) })
        }
    }

    /// The model answers instead, one line first and the alternatives behind it.
    private mutating func generate(for query: SuggestionQuery) {
        let budget = SuggestionSession.turnBudgetInMilliseconds
        let elapsed = random.chance(0.05) ? budget + 1 : Int.random(in: 0...budget, using: &random)
        let completions = invented(for: query.typed)
        guard let update = session.resolveGenerated(completions, for: query, elapsedMilliseconds: elapsed)
        else {
            Issue.record("a live query must take the model's answer")
            return
        }
        settled(update, generated: true)
        let usable = distinct(
            completions.filter { $0 != query.typed && $0.lowercased().hasPrefix(query.typed.lowercased()) })
        guard elapsed <= budget else {
            #expect(update == .quiet(because: .overBudget))
            return
        }
        guard let leader = usable.first else {
            #expect(update == .quiet(because: .nothingOffered))
            return
        }
        let others = Array(usable.dropFirst().prefix(SuggestionSession.verifiedDepth - 1))
        let expected: Suggestion = others.isEmpty ? .certain(leader) : .choice(leader: leader, others: others)
        #expect(update.suggestion == (isQuiet ? expected.certainOnly : expected))
        if others.isEmpty, random.chance(0.7) { expand(query, behind: leader) }
    }

    /// The alternatives arrive behind the one line, which must stay the leader whatever they add.
    private mutating func expand(_ query: SuggestionQuery, behind leader: String) {
        let alternatives = invented(for: query.typed) + (random.chance(0.3) ? [leader] : [])
        let before = session.suggestion
        let expanded = session.expandGenerated(alternatives, for: query)
        let usable = distinct(
            alternatives.filter {
                $0.lowercased() != leader.lowercased() && $0 != query.typed
                    && $0.lowercased().hasPrefix(query.typed.lowercased())
            })
        #expect(session.suggestion.accepting == before.accepting)
        guard case .certain(let shown) = before, shown == leader, !usable.isEmpty else {
            #expect(expanded == nil)
            #expect(session.suggestion == before)
            return
        }
        guard let expanded else {
            #expect(isQuiet)
            return
        }
        settled(expanded, generated: true)
        #expect(
            expanded.suggestion
                == .choice(leader: leader, others: Array(usable.prefix(SuggestionSession.verifiedDepth - 1))))
    }

    /// Continuations the model might invent: some extending the line, some not, some the line itself.
    private mutating func invented(for typed: String) -> [String] {
        var lines: [String] = []
        for _ in 0..<Int.random(in: 0...4, using: &random) {
            switch Int.random(in: 0..<6, using: &random) {
            case 0: lines.append(typed)
            case 1: lines.append("svn " + typed)
            case 2: lines.append(typed.uppercased() + " " + random.pick(["main", "-b", "dev"]))
            default: lines.append(typed + random.pick([" main", " -m 'fix'", "x", " origin", " milenge"]))
            }
        }
        return lines
    }

    /// One keystroke the tap swallowed, which must agree with what the last update armed.
    private mutating func press(_ stroke: KeyStroke) {
        let before = session.suggestion
        let slot = ArmedKeys.slot(of: stroke)
        let armed = !slot.isEmpty && last.armed.contains(slot)
        switch session.route(stroke) {
        case .accept(let text):
            #expect(armed)
            #expect(session.suggestion == .silent)
            #expect(session.typed == text)
            #expect(text == before.accepting || listed(in: before).contains(text))
            typed = text
            retire()
            shownGenerated = false
            last = .quiet(because: .nothingOffered)
        case .redraw(let update):
            #expect(armed)
            if update.suggestion == before {
                #expect(session.selection.hasMoved)
                check(update)
                last = update
            } else {
                // One ⎋ leaves the dot; a further rung, or ⌥⎋, turns the field off and lifts the dot with it.
                minimised = update.suggestion == .minimised
                #expect(update.silence == (minimised ? .minimised : .turnedOffHere))
                retire()
                settled(update, generated: false)
            }
        case .nothing:
            #expect(!armed)
            #expect(session.suggestion == before)
        }
    }

    /// An answer to a question the user has moved on from must be dropped whatever it says.
    private mutating func probeStale() {
        guard let query = stale.randomElement(using: &random) else { return }
        #expect(
            session.resolve(stored(for: query.typed), for: query, now: moment, elapsedMilliseconds: 0) == nil)
        #expect(session.resolveGenerated([query.typed + "x"], for: query, elapsedMilliseconds: 0) == nil)
        #expect(session.expandGenerated([query.typed + "y"], for: query) == nil)
    }

    /// The live question, if any, is now stale.
    private mutating func retire() {
        if let live { stale = Array((stale + [live]).suffix(8)) }
        live = nil
    }

    /// Records what is now drawn, and whether the model rather than the corpus produced it.
    private mutating func settled(_ update: SuggestionUpdate, generated: Bool) {
        check(update)
        last = update
        shownGenerated = generated
    }

    /// What every update must satisfy: it matches the session, and the keys follow the drawing.
    private func check(_ update: SuggestionUpdate) {
        #expect(session.suggestion == update.suggestion)
        // Every silence has a reason and nothing drawn has one, so a log line can never read `reason=nil` under nothing.
        #expect((update.silence == nil) == (update.suggestion.accepting != nil))
        let armed = update.armed
        let accept = ArmedKeys.slot(of: acceptKey.stroke)
        switch update.suggestion {
        case .silent:
            #expect(armed.isEmpty)
            if !isQuiet { #expect(update.silence != .quietModeChoice) }
        case .minimised:
            #expect(armed == [.escape, .optionEscape])
            #expect(update.silence == .minimised)
        case .certain(let text):
            #expect(armed.contains(accept) && armed.contains(.escape) && armed.contains(.optionEscape))
            #expect(!armed.contains(.downArrow) && !armed.contains(.return) && !armed.contains(.upArrow))
            #expect(extends(text))
        case .choice(let leader, let others):
            #expect(!isQuiet)
            #expect(!others.isEmpty && others.count < SuggestionSession.verifiedDepth)
            let lowered = others.map { $0.lowercased() }
            #expect(!lowered.contains(leader.lowercased()) && Set(lowered).count == others.count)
            #expect(armed.contains(accept) && armed.contains(.downArrow) && armed.contains(.escape))
            #expect(armed.contains(.return) == session.selection.hasMoved)
            #expect(armed.contains(.upArrow) == session.selection.hasMoved)
            #expect(extends(leader) && others.allSatisfy(extends))
        }
    }

    /// Whether a drawn line adds something to the line under it.
    private func extends(_ text: String) -> Bool {
        text.lowercased().hasPrefix(asked.lowercased()) && text != asked
    }

    /// The lines with repeats in any case dropped, first occurrence kept, which is what a list may show.
    private func distinct(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        return lines.filter { seen.insert($0.lowercased()).inserted }
    }

    /// The lines under the leader, none where there is no list.
    private func listed(in suggestion: Suggestion) -> [String] {
        if case .choice(_, let others) = suggestion { return others }
        return []
    }
}

@Suite("Sequencing random runs of turns and keystrokes")
struct SuggestionSessionPropertyTests {
    @Test(
        "Across random scripts, every promise the session makes about drawing, arming and forgetting holds.",
        arguments: 0..<250)
    func randomScriptsKeepThePromises(seed: Int) {
        var script = Script(seed: seed)
        script.run(steps: 40)
    }

    @Test(
        "The rejection count never passes the silence threshold and clears with the line.", arguments: 0..<40)
    func rejectionsAreBounded(seed: Int) throws {
        var random = Seeded(seed: seed)
        var session = SuggestionSession()
        let field = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea")
        for round in 0..<12 {
            _ = try draw(&session, typing: "git c", candidates: stored(for: "git c"), in: field)
            _ = session.turn(
                in: field, at: PredictionContext(typed: random.pick(["zzz\(round)", "git x", "ls"])))
            #expect(session.rejectionsHere <= Quieting.rejectionsBeforeSilence)
            if random.chance(0.3) {
                _ = session.turn(in: field, at: PredictionContext(typed: ""))
                #expect(session.rejectionsHere == 0)
            }
        }
    }
}
