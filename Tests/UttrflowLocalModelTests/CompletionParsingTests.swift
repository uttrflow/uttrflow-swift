import Testing

@testable import UttrflowLocalModel

/// What the model's reply is allowed to become, decided without loading a model.
@Suite("Completion parsing")
struct CompletionParsingTests {
    @Test(
        "An indented line is read against the typed text without its indentation, and keeps it in the answer."
    )
    func indentationIsKept() {
        #expect(MLXCandidateScorer.parse("    return a + b", typed: "    return ") == ["    return a + b"])
        #expect(MLXCandidateScorer.parse("  return a + b;", typed: "  return a ") == ["  return a + b;"])
    }

    @Test("Lines that extend what was typed are kept in order, once each, whatever marks the model added.")
    func extendingLinesAreKept() {
        let reply = "```\n1. git checkout main\n- git commit -m\n* git checkout main\ngit c\n```"
        #expect(MLXCandidateScorer.parse(reply, typed: "git c") == ["git checkout main", "git commit -m"])
    }

    @Test("A line quoting the prompt back is not a completion, however it begins.")
    func promptEchoesAreDropped() {
        let reply = "Notes, field AXTextArea, continue this text:\nnavigate to the settings"
        #expect(MLXCandidateScorer.parse(reply, typed: "n") == ["navigate to the settings"])
        let headings = """
            on my way. Continue this line:
            on screen around the field: Priya
            on my way, Lines this person wrote here before
            on my way, be there at 7
            """
        #expect(MLXCandidateScorer.parse(headings, typed: "on my") == ["on my way, be there at 7"])
    }

    @Test(
        "A line the model repeated without its marks, in another case or spacing, is still read past what was typed."
    )
    func rewrittenEchoesAreStillRead() {
        let typed = "what is the price of MitoActive™  serum"
        let reply = "What is the price of MitoActive serum, and is it in stock?"
        #expect(MLXCandidateScorer.parse(reply, typed: typed) == [typed + ", and is it in stock?"])
        #expect(MLXCandidateScorer.continuation(of: "Git Commit -m", past: "git c") == "ommit -m")
        #expect(MLXCandidateScorer.continuation(of: "svn commit", past: "git c") == nil)
        #expect(MLXCandidateScorer.continuation(of: "git c", past: "git c") == "")
        #expect(MLXCandidateScorer.continuation(of: "anything", past: "") == "anything")
        #expect(MLXCandidateScorer.comparable("A™  b\u{200E}C") == "a bc")
    }

    @Test(
        "One slip inside the echo, two characters swapped or one added or changed, still reads past what was typed."
    )
    func oneSlipInTheEchoIsReadPast() {
        #expect(MLXCandidateScorer.continuation(of: "don't know", past: "dont") == " know")
        #expect(MLXCandidateScorer.continuation(of: "the quick fix", past: "teh") == " quick fix")
        #expect(MLXCandidateScorer.continuation(of: "receive the parcel", past: "recieve") == " the parcel")
        #expect(MLXCandidateScorer.continuation(of: "git commit -m", past: "gitcommit") == " -m")
        #expect(MLXCandidateScorer.continuation(of: "colour scheme", past: "color") == " scheme")
        #expect(MLXCandidateScorer.continuation(of: "git  commit -m", past: "git commit") == " -m")
        #expect(MLXCandidateScorer.parse("don't know\n", typed: "dont") == ["dont know"])
        #expect(MLXCandidateScorer.parse("The quick fix", typed: "teh") == ["teh quick fix"])
    }

    @Test(
        "A second slip, or a changed last character with nothing typed after it, is another line and not an echo."
    )
    func twoSlipsOrAChangedEndAreNotAnEcho() {
        #expect(MLXCandidateScorer.continuation(of: "git status", past: "git c") == nil)
        #expect(MLXCandidateScorer.continuation(of: "do'n't know", past: "dont") == nil)
        #expect(MLXCandidateScorer.continuation(of: "§§dont know", past: "dont") == nil)
        #expect(
            MLXCandidateScorer.parse("git status\ngit checkout main", typed: "git c") == ["git checkout main"]
        )
    }

    @Test("A line the model returned unchanged, or with only whitespace added, is nothing to offer.")
    func unchangedLinesAreNothing() {
        #expect(MLXCandidateScorer.parse("git c\ngit c  ", typed: "git c").isEmpty)
        #expect(
            MLXCandidateScorer.parse(
                "What is the price of MitoActive serum", typed: "what is the price of MitoActive™ serum"
            ).isEmpty)
    }

    @Test("A continuation that loops on itself is dropped rather than drawn across the screen.")
    func repetitionIsDropped() {
        let looping = "sr" + String(repeating: " -  sr", count: 40)
        #expect(MLXCandidateScorer.parse(looping + "\nsrc/main.swift", typed: "sr") == ["src/main.swift"])
        #expect(MLXCandidateScorer.isDegenerate(" - sr - sr - sr - sr - sr - sr"))
        #expect(!MLXCandidateScorer.isDegenerate(" -l"))
        #expect(!MLXCandidateScorer.isDegenerate("toring the data in the table for the next run"))
    }

    @Test("A continuation the length of a paragraph is not the rest of a line.")
    func paragraphsAreDropped() {
        let paragraph = String(repeating: "word ", count: 60)
        #expect(MLXCandidateScorer.isDegenerate(paragraph))
        #expect(MLXCandidateScorer.parse("st" + paragraph, typed: "st").isEmpty)
    }

    @Test("Nothing is made of one typed character, since a guess about nothing is noise.")
    func oneCharacterIsTooLittle() {
        #expect(MLXCandidateScorer.minimumTypedLength == 2)
        #expect("s".trimmingCharacters(in: .whitespaces).count < MLXCandidateScorer.minimumTypedLength)
        #expect("ls".trimmingCharacters(in: .whitespaces).count >= MLXCandidateScorer.minimumTypedLength)
    }

    @Test(
        "A line is cut where it takes up a part of a screen label, and dropped when nothing of its own is left."
    )
    func copiesOfTheScreenAreCut() {
        let screen =
            "message, Baby busy ho?, 3Septemberat6:41\u{202F}PM, Received from Priya\nYour message, Haan, Sent to Priya, Delivered"
        #expect(
            MLXCandidateScorer.trimmed(
                "phone pe nahi, 4Septemberat6:42 PM, Received from Priya", typed: "phone", echoing: [screen])
                == "phone pe nahi")
        #expect(
            MLXCandidateScorer.trimmed("phone, Received from Priya", typed: "phone", echoing: [screen]) == nil
        )
        #expect(
            MLXCandidateScorer.trimmed("phone pe nahi, Delivered", typed: "phone", echoing: [screen])
                == "phone pe nahi")
        #expect(
            MLXCandidateScorer.trimmed("phone pe nahi yaar", typed: "phone", echoing: [screen])
                == "phone pe nahi yaar")
        #expect(MLXCandidateScorer.trimmed("phone pe nahi", typed: "phone", echoing: []) == "phone pe nahi")
        // Quoting the screen in the line's own words is a reply, not a copy of a label.
        #expect(
            MLXCandidateScorer.trimmed("phone busy ho?", typed: "phone", echoing: [screen])
                == "phone busy ho?")
        #expect(
            MLXCandidateScorer.trimmed(
                "khana bhi wahi kha lenge", typed: "khana ", echoing: ["Priya: wahi kha lenge?"])
                == "khana bhi wahi kha lenge")
        // A shell reuses a file name and a query a column list from the screen; neither is a label part.
        #expect(
            MLXCandidateScorer.trimmed(
                "git add Sources/Login/Session.swift", typed: "git add ",
                echoing: ["Sources/Login/Session.swift"])
                == "git add Sources/Login/Session.swift")
        #expect(
            MLXCandidateScorer.trimmed(
                "INSERT INTO products (id, name, price, stock)", typed: "INSERT INTO products ",
                echoing: ["products: id, name, price, stock"])
                == "INSERT INTO products (id, name, price, stock)")
    }

    @Test(
        "A new word of one or two characters is nothing, while a character that finishes the typed word stays."
    )
    func aStubOfANewWordIsNothing() {
        #expect(MLXCandidateScorer.trimmed("busy nahi h", typed: "busy nahi", echoing: []) == nil)
        #expect(
            MLXCandidateScorer.trimmed("busy nahi hoon", typed: "busy nahi", echoing: []) == "busy nahi hoon")
        #expect(MLXCandidateScorer.trimmed("git add", typed: "git ad", echoing: []) == "git add")
        #expect(MLXCandidateScorer.trimmed("yes!", typed: "yes", echoing: []) == "yes!")
    }

    @Test(
        "An answer without its echo joins the line only where a boundary says how, never letters against letters."
    )
    func anEchoLessAnswerJoinsOnlyAtABoundary() {
        #expect(MLXCandidateScorer.joined("busy nahi ", with: "hoon bolo") == "busy nahi hoon bolo")
        #expect(MLXCandidateScorer.joined("busy nahi", with: " hoon bolo") == "busy nahi hoon bolo")
        #expect(MLXCandidateScorer.joined("see you at 8", with: ", then") == "see you at 8, then")
        #expect(MLXCandidateScorer.joined("busy nahi", with: "hoon bolo") == nil)
        #expect(MLXCandidateScorer.joined("git c", with: "ommit -m") == nil)
        #expect(MLXCandidateScorer.joined("", with: "hoon") == nil)
        #expect(MLXCandidateScorer.joined("busy", with: "") == nil)
    }
}
