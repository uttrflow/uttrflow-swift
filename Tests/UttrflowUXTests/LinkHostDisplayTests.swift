import UttrflowClipboard
import Testing
@testable import UttrflowUX

@Suite("The host a link row shows", .bug(id: 3732))
struct LinkHostDisplayTests {
    @Test("a plain host is shown as written, with no flags")
    func plainHost() throws {
        let link = try #require(LinkHostDisplay.parse("https://Example.com:8443/a/b?c=d#e"))
        #expect(link.host == "example.com")
        #expect(link.rawHost == "example.com")
        #expect(!link.hasUserInfo)
        #expect(!link.isMixedScript)
        #expect(link.warnings.isEmpty)
    }

    @Test("credentials in the authority are flagged and the host after them is shown")
    func credentialsInAuthority() throws {
        let link = try #require(LinkHostDisplay.parse("https://paypal.com@other.example/login"))
        #expect(link.host == "other.example")
        #expect(link.hasUserInfo)
        #expect(link.warnings == ["Has a user name before the host"])
    }

    @Test("a user name with a password and a port still shows the real host")
    func userAndPassword() throws {
        let link = try #require(LinkHostDisplay.parse("ftp://me:secret@files.example:21/x"))
        #expect(link.host == "files.example")
        #expect(link.hasUserInfo)
    }

    @Test("an xn-- host is decoded, and the raw form is kept for the tooltip")
    func punycodeHost() throws {
        let link = try #require(LinkHostDisplay.parse("https://xn--bcher-kva.example/"))
        #expect(link.host == "bücher.example")
        #expect(link.rawHost == "xn--bcher-kva.example")
        #expect(!link.isMixedScript)
        #expect(link.tooltip.contains("xn--bcher-kva.example"))
    }

    @Test("a look-alike host that mixes Cyrillic and Latin is flagged")
    func mixedScriptHost() throws {
        let link = try #require(LinkHostDisplay.parse("https://xn--pple-43d.com/"))
        #expect(link.host == "\u{0430}pple.com")
        #expect(link.isMixedScript)
        #expect(link.warnings == ["Host mixes writing systems"])
    }

    @Test("a host in one script is not flagged, and neither is invalid punycode")
    func singleScriptAndInvalid() throws {
        #expect(try #require(LinkHostDisplay.parse("https://xn--e1afmkfd.example/")).isMixedScript == false)
        #expect(try #require(LinkHostDisplay.parse("https://xn--!!.example/")).host == "xn--!!.example")
    }

    @Test("text with no authority has no host")
    func noHost() {
        #expect(LinkHostDisplay.parse("mailto:a@example.com") == nil)
        #expect(LinkHostDisplay.parse("https:///path") == nil)
    }

    @Test("a link row carries its host and a text row does not")
    func rowCarriesHost() {
        let link = Clip(text: "https://a@b.example/", kind: .link, copiedAt: PanelFixture.now)
        let text = Clip(text: "https://a@b.example/", kind: .text, copiedAt: PanelFixture.now)
        let rows = PanelFixture.page([link, text]).rows
        #expect(rows.first { $0.id == link.id }?.linkHost?.host == "b.example")
        #expect(rows.first { $0.id == text.id }?.linkHost == nil)
    }
}
