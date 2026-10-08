import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("SpacingPass")
struct SpacingPassTests {
    private let sut = SpacingPass()

    @Test(
        "fixes a stray mark onto the word before it and collapses doubled marks",
        arguments: [
            ("hello , there", "hello, there"),
            ("wait .", "wait."),
            ("milk,, eggs", "milk, eggs"),
            ("hello ... there", "hello... there"),
            ("hello there", "hello there"),
            (", hello", ", hello"),
            ("really ? ?", "really?"),
            ("wait ! !", "wait!"),
            ("really ? ? ?", "really?"),
            ("wait ! ! !", "wait!"),
            ("really : :", "really:"),
            ("wait : .", "wait."),
            ("done. .", "done."),
            ("done .....", "done..."),
            ("really ? .", "really?"),
        ]
    )
    func spacing(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("moves each mark the spacing table puts on the word before onto it, and leaves the rest standing")
    func markSpacingMatrix() {
        for mark in ",.?!:;…%°)]}" {
            #expect(MarkSpacing.attachesBefore(mark))
            #expect(cleaned("word \(mark) next", by: sut) == "word\(mark) next", "\(mark)")
        }
        for mark in "([{-—–/&@#" {
            #expect(!MarkSpacing.attachesBefore(mark))
            #expect(cleaned("word \(mark) next", by: sut) == "word \(mark) next", "\(mark)")
        }
    }

    @Test(
        "splits a clause mark glued between two words",
        arguments: [
            ("deploy done.Next step", "deploy done. Next step"),
            ("yes,that works", "yes, that works"),
            ("yes,no", "yes, no"),
            ("really?yes", "really? yes"),
            ("stop!Now", "stop! Now"),
            ("milk,,eggs", "milk,,eggs"),
            ("add the.env file to.gitignore", "add the .env file to .gitignore"),
            ("The.env file", "The .env file"),
        ]
    )
    func gluedMark(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a dotted or marked token that is not two words alone",
        arguments: [
            "3.5", "3.14", "v1.2.3", "1,000", "10:30", "v2.1", "2.3.1", "v10.4.2", "example.com",
            "docs.example.org",
            "www.example.net", "co.uk", "file.txt", "notes.md", "main.swift", "index.html", "maths.py",
            "Draft.pages", "Budget.numbers", "Incident.docx", "Retention.xlsx", "Node.js", "README.MD",
            "a.m.", "p.m.", "e.g.", "i.e.", "U.S.", "U.S.A.", "etc.", "Mr.Smith", "Dr.Jones", "St.Louis",
            "api:latest", "note:buy", "first;second", "so…", "Self.id", "draft.words", "com.apple.iCal",
            "net.example.App",
            "agents.md", "home.ssh", "package.json",
            "https://example.com/a", "src/app/main.swift", "user_id", "k8s", "x,y", "a.b", "etc.Next",
        ]
    )
    func dottedTokenKept(token: String) {
        #expect(cleaned(token, by: sut) == token)
    }

    @Test("records the moved mark against the word that took it")
    func provenance() {
        let draft = sut.apply(Draft(text: "hello ,"))
        #expect(draft.words[0].state == .replaced(by: SpacingPass.id, from: "hello"))
        #expect(draft.words[1].state == .removed(by: SpacingPass.id))
    }
}
