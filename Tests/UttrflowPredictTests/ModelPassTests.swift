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
        #expect(ModelPass().plan(for: query("git")) == .ask)
    }

    @Test("An earlier answer is reused while the line begins it, case-folded, without the typed line itself.")
    func reusesKept() {
        var pass = ModelPass()
        pass.remember(["git status", "Git stash", "git"], for: query("g"))
        #expect(pass.plan(for: query("GIT ST")) == .reuse(["git status", "Git stash"]))
        #expect(pass.plan(for: query("git")) == .reuse(["git status", "Git stash"]))
        #expect(pass.plan(for: query("ls")) == .ask)
        #expect(pass.plan(for: query("git", in: other)) == .ask)
    }

    @Test("An empty or failed line is skipped only on that exact line and field.")
    func skipsEmpty() {
        var pass = ModelPass()
        pass.remember([], for: query("xyz"))
        #expect(pass.plan(for: query("xyz")) == .skip)
        #expect(pass.plan(for: query("xyzw")) == .ask)
        #expect(pass.plan(for: query("xyz", in: other)) == .ask)
        pass.rememberEmpty(query("abc"))
        #expect(pass.plan(for: query("abc")) == .skip)
        #expect(pass.plan(for: query("xyz")) == .ask)
    }

    @Test("An empty answer keeps the earlier one, which still wins over the empty mark.")
    func emptyKeepsEarlier() {
        var pass = ModelPass()
        pass.remember(["git status"], for: query("g"))
        pass.remember([], for: query("git s"))
        #expect(pass.plan(for: query("git s")) == .reuse(["git status"]))
    }

    @Test("A new field or an emptied line forgets both memories, and anything else keeps them.")
    func freshStart() {
        var pass = ModelPass()
        pass.remember(["git status"], for: query("g"))
        pass.rememberEmpty(query("zz"))
        pass.freshStart(surfaceChanged: false, lineIsEmpty: false)
        #expect(pass.lastGenerated != nil && pass.lastEmpty != nil)
        pass.freshStart(surfaceChanged: true, lineIsEmpty: false)
        #expect(pass.lastGenerated == nil && pass.lastEmpty == nil)
        pass.remember(["git status"], for: query("g"))
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
