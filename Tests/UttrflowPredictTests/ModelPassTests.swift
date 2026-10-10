import Testing

@testable import UttrflowPredict

private let field = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea")
private let other = Surface(bundleIdentifier: "com.example.chat", role: "AXTextArea")

private func query(_ typed: String, in surface: Surface = field) -> SuggestionQuery {
    SuggestionQuery(surface: surface, typed: typed, generation: 1)
}

@Suite("What the model has said, and whether it is asked again")
struct ModelPassTests {
    @Test("The model is asked only when nothing is held, the turn is in budget, and a ready model exists.")
    func shouldAsk() {
        let silent = SuggestionUpdate.quiet(because: .nothingOffered)
        #expect(ModelPass.shouldAsk(after: silent, hasGenerator: true, isReady: true))
        #expect(!ModelPass.shouldAsk(after: silent, hasGenerator: false, isReady: true))
        #expect(!ModelPass.shouldAsk(after: silent, hasGenerator: true, isReady: false))
        #expect(!ModelPass.shouldAsk(after: .quiet(because: .overBudget), hasGenerator: true, isReady: true))
        let held = SuggestionUpdate(suggestion: .certain("git status"), armed: [], silence: nil)
        #expect(!ModelPass.shouldAsk(after: held, hasGenerator: true, isReady: true))
    }

    @Test("A fresh pass is asked for when nothing is remembered.")
    func asksWhenEmpty() {
        #expect(ModelPass().plan(for: query("git"), at: nil) == .ask)
    }

    @Test("An earlier answer is reused while the line types on from it, without the typed line itself.")
    func reusesKept() {
        var pass = ModelPass()
        pass.remember(
            ["git status", "Git stash", "git"], for: query("g"), at: nil,
            scores: ["git status": -0.4, "Git stash": -0.6])
        #expect(pass.plan(for: query("git st"), at: nil) == .reuse(["git status", "Git stash"], listed: []))
        #expect(pass.plan(for: query("git"), at: nil) == .reuse(["git status", "Git stash"], listed: []))
        #expect(pass.scores(for: ["git status", "Git stash"]) == ["git status": -0.4, "Git stash": -0.6])
        #expect(pass.plan(for: query("ls"), at: nil) == .ask)
        #expect(pass.plan(for: query("git", in: other), at: nil) == .ask)
    }

    @Test("A remembered answer is reused when the typed line matches it only under the shared case fold.")
    func reuseUsesTheSharedFold() {
        var pass = ModelPass()
        pass.remember(["Straße is long"], for: query("ST"), at: nil, scores: ["Straße is long": -0.4])
        #expect(pass.plan(for: query("STRASSE"), at: nil) == .reuse(["Straße is long"], listed: []))
    }

    @Test("Identical completions keep their own field's score on reuse.")
    func scoresStayWithTheirField() {
        var first = ModelPass()
        var second = ModelPass()
        first.remember(["Say yes."], for: query("Say"), at: "first", scores: ["Say yes.": -0.2])
        second.remember(["Say yes."], for: query("Say"), at: "second", scores: ["Say yes.": -4.0])

        #expect(first.plan(for: query("Say y"), at: "first") == .reuse(["Say yes."], listed: []))
        #expect(second.plan(for: query("Say y"), at: "second") == .reuse(["Say yes."], listed: []))
        let reused = first.scores(for: ["Say yes."])
        #expect(reused == ["Say yes.": -0.2])
        #expect(
            SuggestionSession.generatedDecision(["Say yes."], typed: "Say y", scores: reused)
                == .certain("Say yes."))
        #expect(second.scores(for: ["Say yes."]) == ["Say yes.": -4.0])
        #expect(first.plan(for: query("Say y", in: other), at: "second") == .ask)
    }

    @Test("A reused list remembers which lines were machine-listed, so the gate can skip them.")
    func reuseCarriesListed() {
        var pass = ModelPass()
        pass.remember(
            ["git checkout main", "git checkout dev", "git checkout develop"],
            for: query("git checkout "), at: nil,
            listed: ["git checkout dev", "git checkout develop"])
        guard case .reuse(let kept, let listed) = pass.plan(for: query("git checkout d"), at: nil)
        else { Issue.record("expected reuse"); return }
        #expect(kept == ["git checkout dev", "git checkout develop"])
        #expect(listed == Set(["git checkout dev", "git checkout develop"]))
    }

    @Test("A line that deletes back past the answered one is asked again, and the answer is forgotten.")
    func backspaceForgets() {
        var pass = ModelPass()
        let asked = query("I will send the rep")
        pass.remember(["I will send the report tomorrow"], for: asked, at: nil)
        let deleted = query("I will send the ")
        #expect(pass.plan(for: deleted, at: nil) == .ask)
        pass.follow(deleted, at: nil)
        #expect(pass.lastGenerated == nil)
        #expect(pass.plan(for: asked, at: nil) == .ask)
    }

    @Test("The same words on another line, after other text, are asked again, and the answer is forgotten.")
    func anotherLineForgets() {
        var pass = ModelPass()
        let line = query("Meeting with")
        pass.remember(["Meeting with the design team"], for: line, at: "Monday agenda")
        #expect(
            pass.plan(for: line, at: "Monday agenda") == .reuse(["Meeting with the design team"], listed: []))
        #expect(pass.plan(for: line, at: "Budget review notes") == .ask)
        #expect(pass.plan(for: line, at: nil) == .ask)
        pass.follow(line, at: "Budget review notes")
        #expect(pass.lastGenerated == nil)
    }

    @Test("Typing on from the answered line keeps the answer.")
    func typingOnKeeps() {
        var pass = ModelPass()
        pass.remember(["Meeting with the design team"], for: query("Meeting"), at: "agenda")
        pass.follow(query("Meeting with"), at: "agenda")
        #expect(pass.lastGenerated != nil)
        #expect(
            pass.plan(for: query("Meeting with"), at: "agenda")
                == .reuse(["Meeting with the design team"], listed: []))
    }

    @Test("An empty or failed line is skipped only on that exact line, field and place.")
    func skipsEmpty() {
        var pass = ModelPass()
        pass.remember([], for: query("xyz"), at: nil)
        #expect(pass.plan(for: query("xyz"), at: nil) == .skip)
        #expect(pass.plan(for: query("xyz"), at: "earlier text") == .ask)
        #expect(pass.plan(for: query("xyzw"), at: nil) == .ask)
        #expect(pass.plan(for: query("xyz", in: other), at: nil) == .ask)
        pass.rememberEmpty(query("abc"), at: nil)
        #expect(pass.plan(for: query("abc"), at: nil) == .skip)
        #expect(pass.plan(for: query("xyz"), at: nil) == .ask)
    }

    @Test("An empty answer keeps the earlier one, which still wins over the empty mark.")
    func emptyKeepsEarlier() {
        var pass = ModelPass()
        pass.remember(["git status"], for: query("g"), at: nil)
        pass.remember([], for: query("git s"), at: nil)
        #expect(pass.plan(for: query("git s"), at: nil) == .reuse(["git status"], listed: []))
    }

    @Test("A new field or an emptied line forgets both memories, and anything else keeps them.")
    func freshStart() {
        var pass = ModelPass()
        pass.remember(["git status"], for: query("g"), at: nil)
        pass.rememberEmpty(query("zz"), at: nil)
        pass.freshStart(surfaceChanged: false, lineIsEmpty: false)
        #expect(pass.lastGenerated != nil && pass.lastEmpty != nil)
        pass.freshStart(surfaceChanged: true, lineIsEmpty: false)
        #expect(pass.lastGenerated == nil && pass.lastEmpty == nil)
        pass.remember(["git status"], for: query("g"), at: nil)
        pass.freshStart(surfaceChanged: false, lineIsEmpty: true)
        #expect(pass.lastGenerated == nil)
    }

    @Test("An answer is fresh only when nothing moved: keystrokes, session, reading and line.")
    func freshness() {
        #expect(
            ModelPass.isFresh(
                keystrokesBefore: 3, keystrokesNow: 3, isCurrent: true, sameReading: true, sameLine: true))
        #expect(
            !ModelPass.isFresh(
                keystrokesBefore: 3, keystrokesNow: 4, isCurrent: true, sameReading: true, sameLine: true))
        #expect(
            !ModelPass.isFresh(
                keystrokesBefore: 3, keystrokesNow: 3, isCurrent: false, sameReading: true, sameLine: true))
        #expect(
            !ModelPass.isFresh(
                keystrokesBefore: 3, keystrokesNow: 3, isCurrent: true, sameReading: false, sameLine: true))
        #expect(
            !ModelPass.isFresh(
                keystrokesBefore: 3, keystrokesNow: 3, isCurrent: true, sameReading: true, sameLine: false))
    }

    @Test("The machine's other values are the alternatives when it listed any, otherwise the model is asked.")
    func alternatives() {
        #expect(ModelPass.alternativesSource(typed: "git checkout ", choices: [], leader: "x") == .model)
        let leader = Verification.completed("git checkout ", with: ["main"]).first ?? ""
        guard
            case .values(let others) = ModelPass.alternativesSource(
                typed: "git checkout ", choices: ["main", "dev"], leader: leader)
        else { Issue.record("expected values"); return }
        #expect(
            others == Verification.completed("git checkout ", with: ["main", "dev"]).filter { $0 != leader })
        #expect(!others.contains(leader))
    }
}
