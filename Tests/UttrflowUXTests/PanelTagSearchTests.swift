// Tests for finding a clip by its tags: whole or by the beginning, never inside a word or the text.
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("The quick panel: searching by tag")
struct PanelTagSearchTests {
    /// A tagged clip whose text shares no word with its tags, and an untagged one that mentions them.
    static let tagged = PanelFixture.clip(
        "postgres://db.example.invalid", minutesAgo: 1, tags: ["prod", "pgsql"])
    static let mentions = PanelFixture.clip("a note about reproduction", minutesAgo: 2)

    static func rows(_ query: String, in clips: [Clip] = [tagged, mentions]) -> [PanelResult] {
        PanelFixture.panel(clips, query: query).results.rows
    }

    @Test("a whole tag or its beginning finds the clip, reported as a tag")
    func wholeAndPrefix() {
        #expect(Self.rows("prod").map(\.id) == [Self.tagged.id, Self.mentions.id])
        #expect(Self.rows("prod").map(\.match) == [.tag, .content])
        #expect(Self.rows("pgs").map(\.id) == [Self.tagged.id])
        #expect(Self.rows("pgs").map(\.match) == [.tag])
    }

    @Test("case, accents and width fold the way an alias's do")
    func folding() {
        for query in ["Prod", "PROD", "próD", "ｐｒｏｄ"] {
            #expect(Self.rows(query).map(\.id).first == Self.tagged.id, "\(query)")
        }
    }

    /// Each query is inside a tag or spans tags, and a tag is only ever matched from its start.
    @Test(
        "a near miss never finds a clip by its tag",
        arguments: ["rod", "od", "sql", "gsq", "prodx", "prod pgsql", "pr od", "p", "#p"])
    func nearMisses(query: String) {
        #expect(!Self.rows(query).contains { $0.match == .tag }, "\(query)")
    }

    @Test("a tag never matches inside the clip's text, which is searched as before")
    func textStillSearched() {
        #expect(Self.rows("reproduction").map(\.id) == [Self.mentions.id])
        #expect(Self.rows("reproduction").map(\.match) == [.content])
    }

    @Test("a tag ranks after a name and before a collection and the text")
    func precedence() {
        let named = PanelFixture.clip("one", minutesAgo: 1, alias: "/prodkey")
        let filed = PanelFixture.clip("two", minutesAgo: 2, category: "Prod things")
        let text = PanelFixture.clip("prod three", minutesAgo: 3)
        let tag = PanelFixture.clip("four", minutesAgo: 4, tags: ["prod"])

        let rows = Self.rows("prod", in: [text, filed, tag, named])

        #expect(rows.map(\.match) == [.alias, .tag, .category, .content])
    }

    @Test("a whole tag outranks a tag the query only begins, and a pin")
    func wholeTagLeads() {
        let begins = PanelFixture.clip("one", minutesAgo: 1, tags: ["database"], isPinned: true)
        let whole = PanelFixture.clip("two", minutesAgo: 2, tags: ["db", "data"])

        #expect(Self.rows("data", in: [begins, whole]).map(\.id) == [whole.id, begins.id])
    }

    @Test("a hidden secret is found by its tag but never by its text")
    func secretByTag() {
        let secret = PanelFixture.clip("sk-live-prod-1234", kind: .secret, tags: ["stripe"])

        #expect(Self.rows("stripe", in: [secret]).map(\.match) == [.tag])
        #expect(Self.rows("prod", in: [secret]).isEmpty)
    }

    @Test("tag matches have their own heading")
    func heading() {
        #expect(PanelPresenter.heading(for: .tag) == "Tags you gave")
    }
}
